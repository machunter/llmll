-- |
-- Module      : Main
-- Description : CLI entry point for the LLMLL compiler.
--
-- Subcommands:
--   check  — parse + type-check, optional --json output
--   holes  — list and classify all holes
--   test   — run property-based tests (check blocks)
--   build  — emit Rust source + Cargo.toml, optional wasm-pack compilation
--   repl   — interactive read-eval-print loop for LLMLL expressions
module Main (main) where

import System.IO (hSetEncoding, hFlush, stdout, stderr, utf8)
import System.Exit (exitFailure, exitSuccess, ExitCode(..))
import System.FilePath (takeBaseName)
import System.Directory (createDirectoryIfMissing, findExecutable)
import System.Process (readProcessWithExitCode)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import Options.Applicative

import LLMLL.Parser (parseTopLevel)
import LLMLL.Syntax (Statement, Span(..))
import LLMLL.TypeCheck (typeCheck, emptyEnv)
import LLMLL.HoleAnalysis
  ( analyzeHoles, HoleReport, HoleStatus(..)
  , totalHoles, blockingHoles, holeEntries
  , holeName, holeContext, holeDescription, holeStatus
  , formatHoleReport, formatHoleReportSExp)
import LLMLL.PBT (runPropertyTests, PBTResult(..), PBTRun(..), PBTStatus(..))
import LLMLL.Codegen (generateRust, CodegenResult(..))
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
  | CmdTest   FilePath
  | CmdBuild  FilePath (Maybe FilePath) Bool   -- file, outdir, --wasm
  | CmdRepl
  deriving (Show)

data Options = Options
  { optCommand :: Command
  , optJson    :: Bool
  } deriving (Show)

optionsParser :: ParserInfo Options
optionsParser = info (helper <*> opts) $
  fullDesc
  <> progDesc "LLMLL — Large Language Model Logical Language Compiler (v0.1.0)"
  <> header "llmll — AI-to-AI programming language compiler"
  where
    opts = Options
      <$> commandParser
      <*> switch (long "json" <> help "Output diagnostics as JSON")

    commandParser = subparser
      ( command "check" (info (CmdCheck <$> fileArg)
          (progDesc "Parse and type-check a .llmll file"))
      <> command "holes" (info (CmdHoles <$> fileArg)
          (progDesc "List and classify all holes in a .llmll file"))
      <> command "test"  (info (CmdTest  <$> fileArg)
          (progDesc "Run property-based tests (check blocks)"))
      <> command "build" (info buildCmd
          (progDesc "Compile .llmll to Rust; optionally invoke wasm-pack for WASM output"))
      <> command "repl"  (info (pure CmdRepl)
          (progDesc "Start an interactive LLMLL REPL"))
      )

    fileArg = strArgument (metavar "FILE" <> help "Path to .llmll source file")

    buildCmd = CmdBuild
      <$> fileArg
      <*> optional (strOption
            (short 'o' <> long "output" <> metavar "DIR"
            <> help "Output directory for generated Rust crate (default: generated/<name>)"))
      <*> switch (long "wasm" <> help "Run wasm-pack after generating Rust (requires wasm-pack in PATH)")

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
    CmdCheck fp           -> doCheck  json fp
    CmdHoles fp           -> doHoles  json fp
    CmdTest  fp           -> doTest   json fp
    CmdBuild fp mOut wasm -> doBuild  json fp mOut wasm
    CmdRepl               -> doRepl

-- ---------------------------------------------------------------------------
-- Shared source loader
-- ---------------------------------------------------------------------------

-- | Parse a .llmll file. Accepts both bare top-level statements and files
-- wrapped in a single @(module Name ...)@ form (single-file model, v0.1.1).
-- See LLMLL.md §8 for the module/import limitations.
parseSrc :: FilePath -> T.Text -> Either Diagnostic [Statement]
parseSrc fp src =
  case parseTopLevel fp src of
    Right stmts -> Right stmts
    Left  err   -> Left (megaparsecToDiagnostic fp err)

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
-- check
-- ---------------------------------------------------------------------------

doCheck :: Bool -> FilePath -> IO ()
doCheck json fp = do
  src <- TIO.readFile fp
  case parseSrc fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
      let report = typeCheck emptyEnv stmts
      if json
        then TIO.putStrLn (formatReportJson report)
        else if reportSuccess report
          then TIO.putStrLn $
            "\x2705 " <> T.pack fp <> " \8212 OK (" <> tshow (length stmts) <> " statements)"
          else mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics report)
      if reportSuccess report then exitSuccess else exitFailure

-- ---------------------------------------------------------------------------
-- holes
-- ---------------------------------------------------------------------------

doHoles :: Bool -> FilePath -> IO ()
doHoles json fp = do
  src <- TIO.readFile fp
  case parseSrc fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
      let report = analyzeHoles stmts
      if json
        then TIO.putStrLn (holeReportJson fp report)
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

holeReportJson :: FilePath -> HoleReport -> T.Text
holeReportJson fp report =
  T.pack . BL.unpack . encode $ object
    [ "file"     .= fp
    , "total"    .= totalHoles report
    , "blocking" .= blockingHoles report
    , "holes"    .= map holeEntryJson (holeEntries report)
    ]
  where
    holeEntryJson e = object
      [ "name"    .= holeName e
      , "context" .= holeContext e
      , "status"  .= (show (holeStatus e) :: String)
      , "desc"    .= holeDescription e
      ]

-- ---------------------------------------------------------------------------
-- test
-- ---------------------------------------------------------------------------

doTest :: Bool -> FilePath -> IO ()
doTest json fp = do
  src <- TIO.readFile fp
  case parseSrc fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
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
  T.pack . BL.unpack . encode $ object
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

doBuild :: Bool -> FilePath -> Maybe FilePath -> Bool -> IO ()
doBuild json fp mOutDir doWasm = do
  src <- TIO.readFile fp
  case parseSrc fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
      let modName = T.pack $ takeBaseName fp
          result  = generateRust modName stmts
          outDir  = case mOutDir of
                      Just d  -> d
                      Nothing -> "generated/" <> T.unpack modName
      -- Write Rust source
      createDirectoryIfMissing True (outDir <> "/src")
      TIO.writeFile (outDir <> "/src/lib.rs") (cgRustSource result)
      TIO.writeFile (outDir <> "/Cargo.toml") (cgCargoToml result)

      if not json
        then do
          TIO.putStrLn $ "   src/lib.rs -- " <> tshow (T.length (cgRustSource result)) <> " chars"
          mapM_ (\w -> TIO.putStrLn $ "   WARNING: " <> w) (cgWarnings result)
        else pure ()

      -- Run cargo check to validate the generated code
      cargoOk <- runCargoCheck json outDir

      if cargoOk
        then do
          if json
            then TIO.putStrLn (buildResultJson fp outDir (cgWarnings result) Nothing)
            else TIO.putStrLn $ "OK Generated Rust crate: " <> T.pack outDir
        else exitFailure

      -- Optionally run wasm-pack
      if doWasm
        then runWasmPack json outDir
        else if json
          then pure ()
          else TIO.putStrLn "   INFO: pass --wasm to compile to WebAssembly (requires wasm-pack)"

      exitSuccess

runCargoCheck :: Bool -> FilePath -> IO Bool
runCargoCheck json outDir = do
  mCargo <- findExecutable "cargo"
  case mCargo of
    Nothing -> do
      let msg = "cargo not found in PATH -- install Rust from https://rustup.rs"
      if json
        then TIO.putStrLn . T.pack . BL.unpack . encode $
               object ["cargo_check" .= False, "error" .= msg]
        else TIO.putStrLn $ "WARN: " <> T.pack msg
      pure True  -- treat missing cargo as non-fatal; user may build manually
    Just cargoBin -> do
      if not json
        then TIO.putStrLn "   Running cargo check ..."
        else pure ()
      (code, _out, stderr_) <- readProcessWithExitCode cargoBin
        ["check", "--manifest-path", outDir <> "/Cargo.toml", "--quiet"] ""
      case code of
        ExitSuccess -> do
          if not json
            then TIO.putStrLn "   cargo check OK"
            else pure ()
          pure True
        ExitFailure _ -> do
          if json
            then TIO.putStrLn . T.pack . BL.unpack . encode $
                   object ["cargo_check" .= False, "stderr" .= stderr_]
            else do
              TIO.putStrLn "FAIL: cargo check failed:"
              TIO.putStr (T.pack stderr_)
          pure False

runWasmPack :: Bool -> FilePath -> IO ()
runWasmPack json outDir = do
  mWasmPack <- findExecutable "wasm-pack"
  case mWasmPack of
    Nothing -> do
      let msg = "wasm-pack not found in PATH — install from https://rustwasm.github.io/wasm-pack/"
      if json
        then TIO.putStrLn . T.pack . BL.unpack . encode $
               object ["wasm" .= False, "error" .= msg]
        else TIO.putStrLn $ "❌ " <> T.pack msg
    Just wasmPackBin -> do
      if not json
        then TIO.putStrLn $ "🔨 Running wasm-pack build " <> T.pack outDir <> " ..."
        else pure ()
      (code, out, err) <- readProcessWithExitCode wasmPackBin
        ["build", outDir, "--target", "web", "--release"] ""
      case code of
        ExitSuccess -> do
          let wasmDir = outDir <> "/pkg"
          if json
            then TIO.putStrLn . T.pack . BL.unpack . encode $
                   object ["wasm" .= True, "pkg_dir" .= wasmDir]
            else TIO.putStrLn $ "✅ WASM output: " <> T.pack wasmDir
        ExitFailure n -> do
          if json
            then TIO.putStrLn . T.pack . BL.unpack . encode $
                   object ["wasm" .= False, "exit_code" .= n, "stderr" .= err]
            else do
              TIO.putStrLn $ "❌ wasm-pack failed (exit " <> tshow n <> ")"
              TIO.putStr (T.pack err)

buildResultJson :: FilePath -> FilePath -> [T.Text] -> Maybe T.Text -> T.Text
buildResultJson fp outDir warnings mWasmPkg =
  T.pack . BL.unpack . encode $ object $
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
