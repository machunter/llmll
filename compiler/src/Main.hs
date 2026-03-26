-- |
-- Module      : Main
-- Description : CLI entry point for the LLMLL compiler.
--
-- Subcommands:
--   check  — parse + type-check, optional --json output
--   holes  — list and classify all holes, optional --json output
--   test   — run property-based tests (check blocks)
--   build  — emit Haskell/JSON-AST, optional --emit json-ast / --from-json
--   run    — build into temp dir and execute
--   repl   — interactive read-eval-print loop
module Main (main) where

import System.IO (hSetEncoding, hFlush, hPutStrLn, stdout, stderr, utf8)
import System.Exit (exitFailure, exitSuccess, ExitCode(..))
import System.FilePath (takeBaseName, (</>), takeExtension)
import System.Directory (createDirectoryIfMissing, findExecutable, doesFileExist)
import System.Process (readProcessWithExitCode)
import Control.Monad (unless, forM_, when, foldM)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString.Lazy as BL
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BLC
import Options.Applicative
import qualified Data.Set as Set

import LLMLL.Parser (parseTopLevel)
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.AstEmit (emitJsonAST)
import LLMLL.Syntax (Statement(..), Span(..), ModuleCache, ModulePath, Import(..))
import LLMLL.TypeCheck (typeCheck, typeCheckWithCache, emptyEnv)
import LLMLL.Module (loadModule, isBuiltinImport, topoSortedEnvs)
import LLMLL.Hub (hubFetchLocal)
import LLMLL.HoleAnalysis
  ( analyzeHoles, HoleReport, HoleStatus(..)
  , totalHoles, blockingHoles, holeEntries
  , holeName, holeContext, holeDescription, holeStatus
  , formatHoleReport, formatHoleReportSExp
  , formatHoleReportJson, holeDensityWarnings)
import LLMLL.PBT (runPropertyTests, PBTResult(..), PBTRun(..), PBTStatus(..))
import LLMLL.CodegenHs (generateHaskell, generateHaskellMulti, CodegenResult(..))
import LLMLL.Diagnostic
  ( DiagnosticReport(..), Diagnostic(..), Severity(..)
  , formatDiagnostic, formatDiagnosticSExp, formatDiagnosticJson
  , formatReportJson, megaparsecToDiagnostic)

import qualified Data.Map.Strict as Map

-- ---------------------------------------------------------------------------
-- CLI Argument Parsing
-- ---------------------------------------------------------------------------

data Command
  = CmdCheck  FilePath
  | CmdHoles  FilePath
  | CmdTest   FilePath Bool                         -- file, --emit-only
  | CmdBuild  FilePath (Maybe FilePath) Bool Bool Bool  -- file, outdir, --wasm, --emit-json-ast, --emit-only
  | CmdBuildFromJson FilePath (Maybe FilePath) Bool     -- file, outdir, --emit-only
  | CmdRun    FilePath [String]                         -- file, extra args
  | CmdRepl
  | CmdHub    FilePath                                  -- Phase 2a: hub fetch --from-file <tarball>
  deriving (Show)

data Options = Options
  { optCommand :: Command
  , optJson    :: Bool
  } deriving (Show)

optionsParser :: ParserInfo Options
optionsParser = info (helper <*> opts) $
  fullDesc
  <> progDesc "LLMLL — Large Language Model Logical Language Compiler (v0.1.2)"
  <> header "llmll — AI-to-AI programming language compiler"
  where
    opts = Options
      <$> commandParser
      <*> switch (long "json" <> help "Output diagnostics as JSON")

    commandParser = subparser
      ( command "check" (info (CmdCheck <$> fileArg)
          (progDesc "Parse and type-check a .llmll or .ast.json file"))
      <> command "holes" (info (CmdHoles <$> fileArg)
          (progDesc "List and classify all holes in a .llmll file"))
      <> command "test"  (info testCmd
          (progDesc "Run property-based tests (check blocks)"))
      <> command "build" (info buildCmd
          (progDesc "Compile .llmll to Rust; use --emit json-ast to emit JSON-AST instead"))
      <> command "build-json" (info buildJsonCmd
          (progDesc "Compile a .ast.json file (JSON-AST) — same as build but from JSON input"))
      <> command "run"   (info runCmd
          (progDesc "Compile and immediately run an LLMLL program (requires def-main)"))
      <> command "repl"  (info (pure CmdRepl)
          (progDesc "Start an interactive LLMLL REPL"))
      <> command "hub"   (info hubCmd
          (progDesc "Manage llmll-hub local package cache"))
      )

    fileArg = strArgument (metavar "FILE" <> help "Path to .llmll or .ast.json source file")

    buildCmd = CmdBuild
      <$> fileArg
      <*> optional (strOption
            (short 'o' <> long "output" <> metavar "DIR"
            <> help "Output directory for generated Haskell package (default: generated/<name>)"))
      <*> switch (long "wasm" <> help "Run wasm-pack after generating (requires wasm-pack in PATH)")
      <*> switch (long "emit" <> help "Emit JSON-AST (.ast.json) instead of compiling to Haskell")
      <*> switch (long "emit-only" <> help "Write Haskell files but skip the internal stack build (avoids Stack lock deadlock)")

    buildJsonCmd = CmdBuildFromJson
      <$> fileArg
      <*> optional (strOption
            (short 'o' <> long "output" <> metavar "DIR"
            <> help "Output directory (default: generated/<name>)"))
      <*> switch (long "emit-only" <> help "Write Haskell files but skip the internal stack build")

    testCmd = CmdTest
      <$> fileArg
      <*> switch (long "emit-only" <> help "Generate QuickCheck Haskell but skip running stack test (avoids Stack lock deadlock)")

    runCmd = CmdRun
      <$> fileArg
      <*> many (strArgument (metavar "..." <> help "Arguments passed through to the program"))

    hubCmd = CmdHub
      <$> strOption
            (long "from-file" <> metavar "TARBALL"
            <> help "Install a .tar.gz package into the local hub cache (~/.llmll/modules/)")


-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  opts <- execParser optionsParser
  let json = optJson opts
  case optCommand opts of
    CmdCheck fp               -> doCheck  json fp
    CmdHoles fp               -> doHoles  json fp
    CmdTest  fp emitOnly         -> doTest   json fp emitOnly
    CmdBuild fp mOut wasm emitJson emitOnly -> doBuild  json fp mOut wasm emitJson emitOnly
    CmdBuildFromJson fp mOut emitOnly       -> doBuildFromJson json fp mOut emitOnly
    CmdRun   fp args          -> doRun    json fp args
    CmdRepl                   -> doRepl
    CmdHub   tarball          -> doHubFetch json tarball

-- ---------------------------------------------------------------------------
-- Shared source loader
-- ---------------------------------------------------------------------------

-- | Parse source (S-expression or JSON-AST). Dispatches on file extension.
-- .ast.json / .json files are read as ByteString and routed to ParserJSON;
-- all other files go through the S-expression parser.
parseSrc :: FilePath -> T.Text -> Either Diagnostic [Statement]
parseSrc fp src =
  -- JSON path is handled by loadStatements (reads as BS); this path is S-expr only.
  case parseTopLevel fp src of
    Right stmts -> Right stmts
    Left  err   -> Left (megaparsecToDiagnostic fp err)

-- | Parse source from a lazy ByteString (used for .ast.json files).
parseSrcBS :: FilePath -> BL.ByteString -> Either Diagnostic [Statement]
parseSrcBS fp bs = parseJSONAST fp bs

-- | Unified file loader: reads the file and dispatches to the right parser.
-- Returns Left () if an error was already emitted to stdout/stderr.
loadStatements :: Bool -> FilePath -> IO (Either () [Statement])
loadStatements json fp
  | takeExtension fp == ".json" = do
      bs <- BL.readFile fp
      case parseSrcBS fp bs of
        Left diag -> do { emitParseDiag json fp diag; return (Left ()) }
        Right ss  -> return (Right ss)
  | otherwise = do
      src <- TIO.readFile fp
      case parseSrc fp src of
        Left diag -> do { emitParseDiag json fp diag; return (Left ()) }
        Right ss  -> return (Right ss)

-- | Format a parse Diagnostic — S-expression by default, JSON with --json.
emitParseDiag :: Bool -> FilePath -> Diagnostic -> IO ()
emitParseDiag json fp d
  | json      = TIO.putStrLn (formatDiagnosticJson d)
  | otherwise = TIO.putStrLn $
      "(error :phase parse"
      <> " :file \"" <> T.pack fp <> "\""
      <> locPart
      <> " :message " <> quote (diagMessage d)
      <> maybe "" (\h -> " :hint " <> quote h) (diagSuggestion d)
      <> ")"
  where
    locPart = case diagSpan d of
      Nothing -> ""
      Just sp -> " :line " <> tshow (spanLine sp) <> " :col " <> tshow (spanCol sp)
    quote t = "\"" <> T.replace "\"" "\\\"" t <> "\""

-- ---------------------------------------------------------------------------
-- Multi-file loader (Phase 2a)
-- ---------------------------------------------------------------------------

-- | Load an entry-point file and recursively load all its transitive imports.
-- Returns (entryStmts, moduleCache, loadOrder) where loadOrder is a
-- topologically-sorted list of module paths (dependencies first) for codegen.
-- Falls back gracefully when no filesystem imports are found (single-file path).
loadStatementsMulti :: Bool -> FilePath -> IO (Either () ([Statement], ModuleCache, [ModulePath]))
loadStatementsMulti json fp = do
  mStmts <- loadStatements json fp
  case mStmts of
    Left ()     -> pure (Left ())
    Right stmts -> do
      let imports = [imp | SImport imp <- stmts]
          srcRoot = takeDirectory fp
      -- Build ModuleCache + load-order by post-order DFS over all imports
      result <- foldM (loadOneImp json srcRoot) (Right (Map.empty, [])) imports
      case result of
        Left diags -> do
          mapM_ (emitDiag json fp) diags
          pure (Left ())
        Right (cache, loadOrder) -> pure (Right (stmts, cache, loadOrder))
  where
    -- P1 fix: skip built-in capability namespace imports (wasi.*, haskell.*, c.*).
    -- These are resolved by the codegen preamble, not by file-system lookup.
    loadOneImp j srcRoot (Left e) _   = pure (Left e)
    loadOneImp j srcRoot (Right (c, ord)) imp = do
      let path = T.splitOn "." (importPath imp)
      if isBuiltinImport path
        then pure (Right (c, ord))
        else do
          res <- loadModule j srcRoot [] c Set.empty path
          case res of
            Left diags         -> pure (Left diags)
            Right (c', o', _)  -> pure (Right (c', ord ++ o'))

    emitDiag j fp_ d
      | j         = TIO.putStrLn (formatDiagnosticJson d)
      | otherwise = TIO.putStrLn (formatDiagnostic d)

takeDirectory :: FilePath -> FilePath
takeDirectory = reverse . dropWhile (\c -> c /= '/' && c /= '\\') . drop 1 . reverse

-- ---------------------------------------------------------------------------
-- check
-- ---------------------------------------------------------------------------

doCheck :: Bool -> FilePath -> IO ()
doCheck json fp = do
  mResult <- loadStatementsMulti json fp
  case mResult of
    Left ()                      -> pure ()
    Right (ss, cache, _loadOrder) -> do
      let report = typeCheckWithCache cache emptyEnv ss
      if json
        then TIO.putStrLn (formatReportJson report)
        else if reportSuccess report
          then TIO.putStrLn $
            "\x2705 " <> T.pack fp <> " \8212 OK (" <> tshow (length ss) <> " statements)"
          else mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics report)
      if reportSuccess report then exitSuccess else exitFailure

-- ---------------------------------------------------------------------------
-- holes
-- ---------------------------------------------------------------------------

doHoles :: Bool -> FilePath -> IO ()
doHoles json fp = do
  stmts <- loadStatements json fp
  case stmts of
    Left () -> pure ()
    Right ss -> do
      let report = analyzeHoles ss
          warnings = holeDensityWarnings ss
      -- Emit density warnings to stderr (informational, not blocking)
      forM_ warnings $ \w ->
        hPutStrLn stderr (T.unpack ("WARNING: " <> diagMessage w))
      if json
        then TIO.putStrLn (formatHoleReportJson fp report)
        else do
          TIO.putStrLn $
            T.pack fp <> " \8212 " <> tshow (totalHoles report)
            <> " holes (" <> tshow (blockingHoles report) <> " blocking)"
          mapM_ printHoleEntry (holeEntries report)
      exitSuccess
  where
    printHoleEntry e = TIO.putStrLn $
      "  [" <> statusLabel (holeStatus e) <> "] " <> holeName e <> " in " <> holeContext e
      where
        statusLabel Blocking    = "BLOCK"
        statusLabel AgentTask   = "AGENT"
        statusLabel NonBlocking = " info"

-- (removed — now using HoleAnalysis.formatHoleReportJson)

-- ---------------------------------------------------------------------------
-- test
-- ---------------------------------------------------------------------------

doTest :: Bool -> FilePath -> Bool -> IO ()
doTest json fp emitOnly = do
  -- P4 fix: use loadStatements so .ast.json is routed to JSON parser
  mStmts <- loadStatements json fp
  case mStmts of
    Left ()    -> exitFailure
    Right stmts -> do
      -- --emit-only: generate the QuickCheck Haskell source and print it,
      -- but skip running stack test (avoids Stack project lock deadlock when
      -- called from inside a running `stack exec llmll` session).
      if emitOnly
        then do
          let modName = T.pack $ takeBaseName fp
              result  = generateHaskell modName stmts
              libSrc  = cgHsSource result
          if json
            then TIO.putStrLn . T.pack . BLC.unpack . encode $
                   object ["file" .= fp, "emit_only" .= True
                          , "lib_chars" .= T.length libSrc]
            else do
              TIO.putStrLn $ "   src/Lib.hs -- " <> tshow (T.length libSrc) <> " chars"
              TIO.putStrLn    "   (stack test skipped — --emit-only)"
          exitSuccess
        else do
          result <- runPropertyTests stmts
          if json
            then TIO.putStrLn (pbtResultJson fp result)
            else printPbtResult fp result
          if pbtFailed result > 0 then exitFailure else exitSuccess

printPbtResult :: FilePath -> PBTResult -> IO ()
printPbtResult fp r = do
  TIO.putStrLn $ T.pack fp <> " — " <> tshow (pbtTotal r) <> " properties"
  TIO.putStrLn $ "  ✅ Passed:  " <> tshow (pbtPassed r)
  TIO.putStrLn $ "  ❌ Failed:  " <> tshow (pbtFailed r)
  TIO.putStrLn $ "  ⚠️  Skipped: " <> tshow (pbtSkipped r)
  mapM_ printRun (pbtResults r)
  where
    printRun run = case pbtStatus run of
      PBTFailed -> do
        TIO.putStrLn $ "  ❌  \"" <> pbtDescription run <> "\""
        mapM_ (\cx -> TIO.putStrLn $ "     counterexample: " <> cx) (pbtCounterexample run)
      _ -> pure ()

pbtResultJson :: FilePath -> PBTResult -> T.Text
pbtResultJson fp r =
  T.pack . BLC.unpack . encode $ object
    [ "file"    .= fp
    , "total"   .= pbtTotal r
    , "passed"  .= pbtPassed r
    , "failed"  .= pbtFailed r
    , "skipped" .= pbtSkipped r
    , "results" .= map runJson (pbtResults r)
    ]
  where
    runJson run = object
      [ "description"   .= pbtDescription run
      , "status"        .= (show (pbtStatus run) :: String)
      , "samples_run"   .= pbtSamplesRun run
      , "counterexample".= pbtCounterexample run
      ]
-- ---------------------------------------------------------------------------
-- build (Rust codegen + optional WASM)
-- ---------------------------------------------------------------------------

doBuild :: Bool -> FilePath -> Maybe FilePath -> Bool -> Bool -> Bool -> IO ()
doBuild json fp mOutDir doWasm emitJson emitOnly = do
  -- Auto-detect JSON-AST files and delegate to the JSON build path.
  if takeExtension fp == ".json"
    then doBuildFromJson json fp mOutDir emitOnly
    else do
      -- --emit json-ast: parse the file directly to round-trip to JSON (no module merge needed)
      when emitJson $ do
        src <- TIO.readFile fp
        case parseSrc fp src of
          Left diag -> do { emitParseDiag json fp diag; exitFailure }
          Right stmts -> do
            let modName = T.pack $ takeBaseName fp
                outDir  = case mOutDir of
                            Just d  -> d
                            Nothing -> "generated/" <> T.unpack modName
                astFile = outDir <> "/" <> T.unpack modName <> ".ast.json"
            createDirectoryIfMissing True outDir
            BL.writeFile astFile (emitJsonAST stmts)
            if json
              then TIO.putStrLn . T.pack . BLC.unpack . encode $
                     object ["file" .= fp, "ast_json" .= astFile, "success" .= True]
              else TIO.putStrLn $ "✅ JSON-AST written to " <> T.pack astFile
            exitSuccess

      -- B3: use loadStatementsMulti so imported modules' definitions are
      -- inlined into Lib.hs (mirrors the doBuildFromJson path).
      mResult <- loadStatementsMulti json fp
      case mResult of
        Left () -> exitFailure
        Right (stmts, cache, loadOrder) -> do
          let modName      = T.pack $ takeBaseName fp
              importedEnvs = topoSortedEnvs cache loadOrder
              result       = generateHaskellMulti modName importedEnvs stmts
              outDir       = case mOutDir of
                               Just d  -> d
                               Nothing -> "generated/" <> T.unpack modName
          -- Write Haskell source + optional Main.hs
          createDirectoryIfMissing True (outDir <> "/src")
          TIO.writeFile (outDir <> "/src/Lib.hs")     (cgHsSource result)
          TIO.writeFile (outDir <> "/package.yaml")   (cgPackageYaml result)
          TIO.writeFile (outDir <> "/stack.yaml")     (cgStackYaml result)
          case cgMainHs result of
            Nothing   -> pure ()
            Just mainSrc -> do
              TIO.writeFile (outDir <> "/src/Main.hs") mainSrc
              unless json $ TIO.putStrLn $ "   src/Main.hs -- " <> tshow (T.length mainSrc) <> " chars"

          -- Write FFI hub module
          case cgFfiModHs result of
            Nothing -> pure ()
            Just ffiModSrc -> do
              createDirectoryIfMissing True (outDir <> "/src/FFI")
              TIO.writeFile (outDir <> "/src/FFI.hs") ffiModSrc
              unless json $ TIO.putStrLn $ "   src/FFI.hs -- " <> tshow (T.length ffiModSrc) <> " chars"

          -- Write per-library FFI stubs (generated ONCE, do not overwrite)
          forM_ (cgFfiFiles result) $ \(modN, stubsSrc) -> do
              let stubPath = outDir <> "/src/FFI/" <> T.unpack modN <> ".hs"
              exists <- doesFileExist stubPath
              if exists
                then unless json $ TIO.putStrLn $ "   src/FFI/" <> modN <> ".hs -- KEEPING existing developer file"
                else do
                  TIO.writeFile stubPath stubsSrc
                  unless json $ TIO.putStrLn $ "   src/FFI/" <> modN <> ".hs -- generated " <> tshow (T.length stubsSrc) <> " chars"

          unless json $ do
            TIO.putStrLn $ "   src/Lib.hs -- " <> tshow (T.length (cgHsSource result)) <> " chars"
            mapM_ (\w -> TIO.putStrLn $ "   WARNING: " <> w) (cgWarnings result)

          -- Validate generated Haskell with GHC (skip when --emit-only)
          ghcOk <- if emitOnly
            then do
              unless json $ TIO.putStrLn "   (stack build skipped — --emit-only)"
              pure True
            else runGhcCheck json outDir

          if ghcOk
            then do
              if json
                then TIO.putStrLn (buildResultJson fp outDir (cgWarnings result) Nothing)
                else TIO.putStrLn $ "OK Generated Haskell package: " <> T.pack outDir
            else exitFailure

          -- Optionally run wasm-pack (WASM PoC deferred to v0.4)
          if doWasm
            then TIO.putStrLn "   INFO: --wasm targets Haskell WASM backend (ghc --target=wasm32-wasi). See docs/wasm-compat-report.md"
            else unless json $ TIO.putStrLn "   INFO: pass --wasm for WASM PoC output (requires GHC WASM backend)"

          exitSuccess

    -- | Build from a JSON-AST (.ast.json) file.

doBuildFromJson :: Bool -> FilePath -> Maybe FilePath -> Bool -> IO ()
doBuildFromJson json fp mOutDir emitOnly = do
  -- P3: use loadStatementsMulti to resolve imports and get load-order
  mResult <- loadStatementsMulti json fp
  case mResult of
    Left () -> exitFailure
    Right (stmts, cache, loadOrder) -> do
      let rawName = T.pack $ takeBaseName fp
          modName = T.replace ".ast" "" rawName
          -- P3: collect imported envs in topo order and call generateHaskellMulti
          importedEnvs = topoSortedEnvs cache loadOrder
          result  = generateHaskellMulti modName importedEnvs stmts
          outDir  = case mOutDir of
                      Just d  -> d
                      Nothing -> "generated/" <> T.unpack modName
      createDirectoryIfMissing True (outDir <> "/src")
      TIO.writeFile (outDir <> "/src/Lib.hs")   (cgHsSource result)
      TIO.writeFile (outDir <> "/package.yaml")  (cgPackageYaml result)
      TIO.writeFile (outDir <> "/stack.yaml")    (cgStackYaml result)
      case cgMainHs result of
        Nothing      -> pure ()
        Just mainSrc -> TIO.writeFile (outDir <> "/src/Main.hs") mainSrc
      forM_ (cgFfiFiles result) $ \(modN, stubsSrc) -> do
        let stubPath = outDir <> "/src/FFI/" <> T.unpack modN <> ".hs"
        exists <- doesFileExist stubPath
        unless exists $ TIO.writeFile stubPath stubsSrc
      -- Validate generated Haskell with GHC (skip when --emit-only)
      ghcOk <- if emitOnly
        then do
          unless json $ TIO.putStrLn "   (stack build skipped — --emit-only)"
          pure True
        else runGhcCheck json outDir
      if ghcOk
        then do
          if json
            then TIO.putStrLn (buildResultJson fp outDir (cgWarnings result) Nothing)
            else TIO.putStrLn $ "OK Generated Haskell package from JSON-AST: " <> T.pack outDir
          exitSuccess
        else exitFailure

-- ---------------------------------------------------------------------------
-- run (build into temp dir + cargo run)
-- ---------------------------------------------------------------------------

doRun :: Bool -> FilePath -> [String] -> IO ()
doRun json fp extraArgs = do
  let modName = T.unpack . T.pack $ takeBaseName fp
      tmpDir  = "/tmp/llmll-run-" <> modName
  -- Build into tmp dir (reuses doBuild logic via shared helpers)
  src <- TIO.readFile fp
  case parseSrc fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
      let modNameT = T.pack modName
          result   = generateHaskell modNameT stmts
          outDir   = tmpDir
      createDirectoryIfMissing True (outDir <> "/src")
      TIO.writeFile (outDir <> "/src/Lib.hs")   (cgHsSource result)
      TIO.writeFile (outDir <> "/package.yaml")  (cgPackageYaml result)
      TIO.writeFile (outDir <> "/stack.yaml")   (cgStackYaml result)

      -- Write FFI hub
      case cgFfiModHs result of
        Nothing -> pure ()
        Just ffiModSrc -> do
          createDirectoryIfMissing True (outDir <> "/src/FFI")
          TIO.writeFile (outDir <> "/src/FFI.hs") ffiModSrc

      -- Write per-library FFI stubs
      forM_ (cgFfiFiles result) $ \(modN, stubsSrc) -> do
          let stubPath = outDir <> "/src/FFI/" <> T.unpack modN <> ".hs"
          exists <- doesFileExist stubPath
          unless exists $ TIO.writeFile stubPath stubsSrc

      case cgMainHs result of
        Nothing -> do
          TIO.putStrLn "ERROR: (def-main ...) is required for `llmll run`. Add a def-main to your .llmll file."
          exitFailure
        Just mainSrc -> do
          TIO.writeFile (outDir <> "/src/Main.hs") mainSrc
          mStack <- findExecutable "stack"
          case mStack of
            Nothing -> do
              TIO.putStrLn "ERROR: stack not found in PATH. Install from https://haskellstack.org"
              exitFailure
            Just stackBin -> do
              (code, _out, err) <- readProcessWithExitCode stackBin
                (["exec", "--stack-yaml", outDir <> "/stack.yaml", "--"] ++ extraArgs) ""
              case code of
                ExitSuccess   -> pure ()
                ExitFailure _ -> do
                  TIO.putStr (T.pack err)
                  exitFailure

runCargoCheck :: Bool -> FilePath -> IO Bool
runCargoCheck = runGhcCheck  -- legacy alias

-- | Validate generated Haskell using stack build or ghc --make.
runGhcCheck :: Bool -> FilePath -> IO Bool
runGhcCheck json outDir = do
  mStack <- findExecutable "stack"
  case mStack of
    Just stackBin -> do
      if not json then TIO.putStrLn "   Running stack build ..." else pure ()
      (code, _out, stderr_) <- readProcessWithExitCode stackBin
        ["build", "--no-terminal"] ""
      case code of
        ExitSuccess -> do
          if not json then TIO.putStrLn "   stack build OK" else pure ()
          pure True
        ExitFailure _ -> do
          if json
            then TIO.putStrLn . T.pack . BLC.unpack . encode $
                   object ["ghc_check" .= False, "stderr" .= stderr_]
            else do
              TIO.putStrLn "FAIL: stack build failed:"
              TIO.putStr (T.pack stderr_)
          pure False
    Nothing -> do
      mGhc <- findExecutable "ghc"
      case mGhc of
        Nothing -> do
          let msg = "stack/ghc not found -- install from https://haskellstack.org"
          if json
            then TIO.putStrLn . T.pack . BLC.unpack . encode $
                   object ["ghc_check" .= False, "error" .= msg]
            else TIO.putStrLn $ "WARN: " <> T.pack msg
          pure True  -- non-fatal; user can build manually
        Just ghcBin -> do
          if not json then TIO.putStrLn "   Running ghc --make ..." else pure ()
          (code, _out, stderr_) <- readProcessWithExitCode ghcBin
            ["--make", "-isrc", outDir <> "/src/Lib.hs"] ""
          case code of
            ExitSuccess -> do
              if not json then TIO.putStrLn "   ghc OK" else pure ()
              pure True
            ExitFailure _ -> do
              if json
                then TIO.putStrLn . T.pack . BLC.unpack . encode $
                       object ["ghc_check" .= False, "stderr" .= stderr_]
                else do
                  TIO.putStrLn "FAIL: ghc --make failed:"
                  TIO.putStr (T.pack stderr_)
              pure False

runWasmPack :: Bool -> FilePath -> IO ()
runWasmPack _json _outDir =
  TIO.putStrLn "INFO: WASM now uses GHC WASM backend -- see docs/wasm-compat-report.md"

buildResultJson :: FilePath -> FilePath -> [T.Text] -> Maybe T.Text -> T.Text
buildResultJson fp outDir warnings mWasmPkg =
  T.pack . BLC.unpack . encode $ object $
    [ "file"       .= fp
    , "out_dir"    .= outDir
    , "success"    .= True
    , "warnings"   .= warnings
    ] ++
    maybe [] (\pkg -> ["wasm_pkg" .= pkg]) mWasmPkg

-- ---------------------------------------------------------------------------
-- repl
-- ---------------------------------------------------------------------------

doRepl :: IO ()
doRepl = do
  TIO.putStrLn "LLMLL REPL v0.1 — type :help for commands, :quit to exit"
  TIO.putStrLn "Parse expressions and see their AST representation."
  TIO.putStrLn ""
  replLoop Map.empty

replLoop :: Map.Map T.Text T.Text -> IO ()
replLoop _env = do
  TIO.putStr "llmll> "
  hFlush stdout
  line <- TIO.getLine
  let trimmed = T.strip line
  case trimmed of
    ":quit" -> TIO.putStrLn "Goodbye."
    ":q"    -> TIO.putStrLn "Goodbye."
    ":help" -> do
      TIO.putStrLn ":help     — show this help"
      TIO.putStrLn ":quit     — exit the REPL"
      TIO.putStrLn ":check F  — parse and type-check file F"
      TIO.putStrLn ":holes F  — show holes in file F"
      TIO.putStrLn ""
      TIO.putStrLn "Enter any LLMLL expression or statement to parse and display its AST."
      replLoop _env
    _ | T.isPrefixOf ":check " trimmed -> do
        let fp = T.unpack (T.drop 7 trimmed)
        doCheck False fp
        replLoop _env
      | T.isPrefixOf ":holes " trimmed -> do
        let fp = T.unpack (T.drop 7 trimmed)
        doHoles False fp
        replLoop _env
      | T.null trimmed -> replLoop _env
      | otherwise -> do
          -- Try to parse as a statement or expression
          case parseTopLevel "<repl>" trimmed of
            Left err ->
              TIO.putStrLn $ formatDiagnosticSExp (megaparsecToDiagnostic "<repl>" err)
            Right stmts -> do
              mapM_ (\stmt -> TIO.putStrLn $ T.pack (show stmt)) stmts
              let report = typeCheck emptyEnv stmts
              mapM_ (TIO.putStrLn . ("  type: " <>) . formatDiagnostic)
                    (reportDiagnostics report)
          replLoop _env

-- ---------------------------------------------------------------------------
-- Shared Helpers
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> T.Text
tshow = T.pack . show

-- ---------------------------------------------------------------------------
-- hub (Phase 2a: local tarball install)
-- ---------------------------------------------------------------------------

doHubFetch :: Bool -> FilePath -> IO ()
doHubFetch json tarball = do
  result <- hubFetchLocal tarball
  case result of
    Left err -> do
      if json
        then TIO.putStrLn . T.pack . BLC.unpack . encode $
               object ["success" .= False, "error" .= err]
        else TIO.putStrLn $ "ERROR: " <> T.pack err
      exitFailure
    Right () -> do
      if json
        then TIO.putStrLn . T.pack . BLC.unpack . encode $
               object ["success" .= True, "tarball" .= tarball]
        else TIO.putStrLn $ "\x2705 Hub package installed from: " <> T.pack tarball
      exitSuccess
