-- |
-- Module      : Main
-- Description : CLI entry point for the LLMLL compiler.
--
-- Subcommands:
--   check      — parse + type-check, optional --json output
--   holes      — list and classify all holes, optional --json output
--   test       — run property-based tests (check blocks)
--   build      — emit Haskell/JSON-AST, optional --emit json-ast / --from-json
--   run        — build into temp dir and execute
--   repl       — interactive read-eval-print loop
--   verify     — D4: emit .fq constraints + run liquid-fixpoint (if installed)
--   typecheck  — Phase 2c: parse + type-check; --sketch infers hole types
--   serve      — Phase 2c: HTTP endpoint for agent sketch queries (localhost:7777)
--   checkout   — v0.3: lock a hole for exclusive editing
--   patch      — v0.3: apply RFC 6902 JSON-Patch to a checked-out hole
module Main (main) where

import System.IO (hSetEncoding, hFlush, hPutStrLn, stdout, stderr, utf8)
import Data.Version (showVersion)
import Paths_llmll (version)
import System.Exit (exitFailure, exitSuccess, exitWith, ExitCode(..))
import System.FilePath (takeBaseName, takeFileName, (</>), takeExtension)
import System.Directory (createDirectoryIfMissing, findExecutable, doesFileExist)
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import System.Process (readProcessWithExitCode)
import Control.Monad (unless, forM_, when, foldM)
import Numeric (showFFloat)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString.Lazy as BL
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy.Char8 as BLC
import Options.Applicative
import qualified Data.Set as Set

import LLMLL.Parser (parseTopLevel)
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.AstEmit (emitJsonAST)
import LLMLL.Syntax (Statement(..), Span(..), ModuleCache, ModulePath, Import(..), ModuleEnv(..), typeLabel, Type(..), Contract(..), ContractStatus(..), DisplayLevel(..), EvidenceRecord(..), Name, Expr(..), HoleKind(..), GrammarMode(..), normalizeDefStmt)
import LLMLL.TypeCheck (typeCheck, typeCheckWithCache, typeCheckStrictWithCache, typeCheckStrictWithCacheAndStatus, typeCheckStrict, emptyEnv, builtinEnv, runSketch, SketchResult(..), HoleStatus(..), SketchHole(..), ScopeBinding(..))
import LLMLL.Module (loadModule, isBuiltinImport, topoSortedEnvs)
import LLMLL.Hub (hubFetchLocal, resolveScaffold)
import LLMLL.HubQuery (queryBySignature, QueryResult(..))
import LLMLL.HoleAnalysis
  ( analyzeHoles, analyzeHolesWithDeps, HoleReport, HoleStatus(..)
  , totalHoles, blockingHoles, holeEntries
  , holeName, holeContext, holeDescription, holeStatus
  , formatHoleReport, formatHoleReportSExp
  , formatHoleReportJson, holeDensityWarnings)
import LLMLL.PBT (runPropertyTests, assembleTestStatements, pbtTrustWriteback, canonicalDefEvidenceHash, PBTResult(..), PBTRun(..), PBTStatus(..))
import LLMLL.Module (mergeCS)
import LLMLL.CodegenHs (generateHaskell, generateHaskellMulti, CodegenResult(..), sanitizePkgName)
import LLMLL.Diagnostic
  ( DiagnosticReport(..), Diagnostic(..), Severity(..)
  , formatDiagnostic, formatDiagnosticSExp, formatDiagnosticJson
  , formatReportJson, megaparsecToDiagnostic, mkSpecWeakness, mkCandidateUnvalidated)
-- D4: liquid-fixpoint verification backend
import LLMLL.FixpointEmit (emitFixpoint, emitFixpointWith, EmitResult(..), EmitOptions(..), defaultEmitOptions, buildAliasMap, augmentContractPost)
import LLMLL.DiagnosticFQ (parseFQResult, parseFQResultJSON, fqResultToReport, FQVerifyResult(..), ConstraintOrigin(..))
import LLMLL.Serve (ServeOptions(..), defaultServeOptions, runServe)
import LLMLL.Sketch (encodeSketchResult, inferredTypeLabel)
import LLMLL.InvariantRegistry (defaultPatterns)
import LLMLL.Checkout (checkoutHole, checkoutHoleWithContext, releaseHole, checkoutStatus, CheckoutToken(..), CheckoutContext(..), FuncEntry(..), buildScopeEntries, collectTypeDefinitions, normalizePointer)
import LLMLL.PatchApply (applyPatch, parsePatchRequest, PatchResult(..), hashFile)
import LLMLL.Contracts (ContractsMode(..), instrumentContracts, applyContractsMode)
import LLMLL.VerifiedCache (saveVerified, saveVerifiedWith, loadVerified, verifiedPath)
import LLMLL.Replay (parseEventLog, EventLogEntry(..), runReplay, ReplayResult(..), runCapturingExit)
import LLMLL.LeanTranslate (translateObligation, TranslateResult(..))
import LLMLL.MCPClient (MCPResult(..), callLeanstral, defaultMCPConfig, MCPConfig(..))
import LLMLL.ProofCache (loadProofCache, saveProofCache, lookupProof, insertProof, ProofEntry(..), computeObligationHash)
import LLMLL.TrustReport (buildTrustReport, buildTrustReportWithCDP, formatTrustReport, formatTrustReportJson, TrustReport(..), TrustEntry(..), CallerObligation(..), markRefuted, refutedClosure, downgradeStaleVerifiedSidecar, callerObligationJson)
import LLMLL.ProofArtifact
import qualified Crypto.Hash.SHA256 as PASHA
import qualified Data.ByteString as PABS
import Numeric (showHex)
import LLMLL.CDP
  ( CDPResult(..), CDPScope(..)
  , computeCDPFor
  , overAnnotationRatio, overAnnotationThreshold
  , cdpWarningLabel )
import LLMLL.AgentSpec (agentSpecJSON, agentSpecText)
import LLMLL.WeaknessCheck (generateWeaknessCandidates, WeaknessCandidate(..), wcSyntheticName)
import LLMLL.ObligationMining (mineObligations, formatObligations, formatObligationsJson)
import LLMLL.SpecCoverage (runCoverage, formatCoverageText, formatCoverageJson)
import LLMLL.ObligationAssembly (assembleReport, holeContractBrief, assembleConsumedGuarantees, trustLabel, recursiveNames, exprToSExpr)
import LLMLL.FixpointEmit (buildContractEnv)
import LLMLL.HoleAnalysis (enclosingFunc)
import System.Process (createProcess, proc, std_out, StdStream(..), waitForProcess, readCreateProcessWithExitCode, cwd)
import System.IO (hGetLine)

import qualified Data.Map.Strict as Map

-- ---------------------------------------------------------------------------
-- CLI Argument Parsing
-- ---------------------------------------------------------------------------

data Command
  = CmdCheck    FilePath Bool                                -- file, --strict
  | CmdHoles    FilePath Bool (Maybe FilePath)  -- file, --deps, --deps-out
  | CmdTest     FilePath Bool                               -- file, --emit-only
  | CmdBuild    FilePath (Maybe FilePath) Bool Bool Bool ContractsMode  -- file, outdir, --wasm, --emit-json-ast, --emit-only, --contracts
  | CmdBuildFromJson FilePath (Maybe FilePath) Bool ContractsMode  -- file, outdir, --emit-only, contracts mode
  | CmdRun      FilePath [String]                           -- file, extra args
  | CmdRepl
  | CmdHub      FilePath                                    -- Phase 2a: hub fetch --from-file <tarball>
  | CmdHubScaffold T.Text (Maybe FilePath)                  -- v0.3: hub scaffold <template> [--output DIR]
  | CmdHubQuery T.Text                                      -- v0.6.1: hub query --signature <sig>
  | CmdVerify   FilePath (Maybe FilePath) LeanstralOpts Bool Bool Bool Bool Bool Bool Bool (Maybe FilePath) -- D4: file, .fq output, leanstral, --trust-report, --weakness-check, --obligations, --spec-coverage, --strict-verified-core, --obligation-report, --cdp, --proof-artifact (PROOF-ARTIFACT)
  | CmdReplayArtifact FilePath  -- PROOF-ARTIFACT: re-derive + check a recorded artifact (fail-closed)
  | CmdTypecheck FilePath Bool                              -- Phase 2c: file, --sketch
  | CmdServe    ServeOptions                                -- D5: HTTP serve on localhost:7777
  | CmdCheckout       FilePath String                       -- v0.3: checkout <file.ast.json> <pointer>
  | CmdCheckoutRelease FilePath String                      -- v0.3: checkout --release <file> <token>
  | CmdCheckoutStatus  FilePath String                      -- v0.3: checkout --status <file> <token>
  | CmdPatch    FilePath FilePath                            -- v0.3: patch <source.ast.json> <patch-request.json>
  | CmdReplay   FilePath FilePath                            -- v0.3.1: replay <source.llmll> <event-log.jsonl>
  | CmdSpec     Bool                                         -- v0.3.4: spec [--json]
  | CmdVersion                                               -- v0.11: version
  deriving (Show)

-- | Leanstral MCP options for the verify command (v0.3.1).
data LeanstralOpts = LeanstralOpts
  { lsMock    :: Bool           -- ^ --leanstral-mock: use mock prover
  , lsCmd     :: Maybe FilePath -- ^ --leanstral-cmd: path to lean-lsp-mcp
  , lsTimeout :: Int            -- ^ --leanstral-timeout: seconds (default 30)
  } deriving (Show)

data Options = Options
  { optCommand     :: Command
  , optJson        :: Bool
  , optGrammarMode :: GrammarMode
  } deriving (Show)

optionsParser :: ParserInfo Options
optionsParser = info (helper <*> versionFlag <*> opts) $
  fullDesc
  <> progDesc ("LLMLL — Large Language Model Logical Language Compiler (v" ++ showVersion version ++ ")")
  <> header "llmll — AI-to-AI programming language compiler"
  where
    versionFlag = infoOption ("llmll " ++ showVersion version)
      (long "version" <> help "Print compiler version and exit")
    opts = Options
      <$> commandParser
      <*> switch (long "json" <> help "Output diagnostics as JSON")
      <*> option (eitherReader parseGrammarMode)
            (long "grammar" <> value GrammarCoreInversion <> metavar "MODE"
            <> help "LT-INV: grammar mode: core-inversion (default) or legacy (v0.10 compatibility)")

    commandParser = subparser
      ( command "check" (info (helper <*> (CmdCheck <$> fileArg <*> switch (long "strict" <> help "v0.6.3: Treat warnings (unbound vars, unknown fns) as hard errors")))
          (progDesc "Parse and type-check a .llmll or .ast.json file"))
      <> command "holes" (info (helper <*> holesCmd)
          (progDesc "List and classify all holes in a .llmll file"))
      <> command "test"  (info (helper <*> testCmd)
          (progDesc "Run property-based tests (check blocks)"))
      <> command "build" (info (helper <*> buildCmd)
          (progDesc "Compile .llmll to Haskell; use --emit json-ast to emit JSON-AST instead"))
      <> command "build-json" (info (helper <*> buildJsonCmd)
          (progDesc "Compile a .ast.json file (JSON-AST) — same as build but from JSON input"))
      <> command "run"   (info (helper <*> runCmd)
          (progDesc "Compile and immediately run an LLMLL program (requires def-main)"))
      <> command "repl"  (info (helper <*> pure CmdRepl)
          (progDesc "Start an interactive LLMLL REPL"))
      <> command "hub"   (info (helper <*> hubCmd)
          (progDesc "Manage llmll-hub local package cache (fetch, scaffold)"))
      <> command "verify" (info (helper <*> verifyCmd)
          (progDesc "D4: Emit .fq constraints and run liquid-fixpoint (if installed)"))
      <> command "typecheck" (info (helper <*> typecheckCmd)
          (progDesc "Parse and type-check; with --sketch infer hole types from context (Phase 2c)"))
      <> command "serve" (info (helper <*> serveCmd)
          (progDesc "D5: Start HTTP server on 127.0.0.1:7777 for AI agent integration"))
      <> command "checkout" (info (helper <*> checkoutCmd)
          (progDesc "v0.3: Lock a hole for exclusive editing (checkout/release/status)"))
      <> command "patch" (info (helper <*> patchCmd)
          (progDesc "v0.3: Apply an RFC 6902 JSON-Patch to a checked-out hole"))
      <> command "replay" (info (helper <*> replayCmd)
          (progDesc "v0.3.1: Replay an event log against a compiled program"))
      <> command "replay-artifact" (info (helper <*> (CmdReplayArtifact <$> strArgument (metavar "ARTIFACT" <> help "Path to a proof-artifact JSON file")))
          (progDesc "PROOF-ARTIFACT: re-derive and check a recorded verification artifact (fail-closed)"))
      <> command "spec" (info (helper <*> specCmd)
          (progDesc "v0.3.4: Emit agent specification from compiler builtins"))
      <> command "version" (info (helper <*> pure CmdVersion)
          (progDesc "Print compiler version and exit"))
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
      <*> contractsOpt

    contractsOpt = option (eitherReader parseContractsMode)
        (  long "contracts" <> value ContractsFull <> metavar "MODE"
        <> help "v0.3: runtime assertion mode: full (default), unproven, none")

    parseContractsMode :: String -> Either String ContractsMode
    parseContractsMode "full"     = Right ContractsFull
    parseContractsMode "unproven" = Right ContractsUnproven
    parseContractsMode "none"     = Right ContractsNone
    parseContractsMode s          = Left $ "unknown --contracts mode: " ++ s ++ " (expected: full, unproven, none)"

    parseGrammarMode :: String -> Either String GrammarMode
    parseGrammarMode "core-inversion"  = Right GrammarCoreInversion
    parseGrammarMode "legacy"          = Right GrammarLegacy
    parseGrammarMode s                 = Left $ "unknown --grammar mode: " ++ s ++ " (expected: core-inversion, legacy)"

    buildJsonCmd = CmdBuildFromJson
      <$> fileArg
      <*> optional (strOption
            (short 'o' <> long "output" <> metavar "DIR"
            <> help "Output directory (default: generated/<name>)"))
      <*> switch (long "emit-only" <> help "Write Haskell files but skip the internal stack build")
      <*> contractsOpt

    testCmd = CmdTest
      <$> fileArg
      <*> switch (long "emit-only" <> help "Generate QuickCheck Haskell but skip running stack test (avoids Stack lock deadlock)")

    runCmd = CmdRun
      <$> fileArg
      <*> many (strArgument (metavar "..." <> help "Arguments passed through to the program"))

    hubCmd = hsubparser
      (  command "fetch" (info (helper <*> hubFetchCmd)
           (progDesc "Install a .tar.gz package into the local hub cache"))
      <> command "scaffold" (info (helper <*> hubScaffoldCmd)
           (progDesc "v0.3: Copy a scaffold template to the current directory"))
      <> command "query" (info (helper <*> hubQueryCmd)
           (progDesc "v0.6.1: Query hub for functions matching a type signature"))
      )

    hubFetchCmd = CmdHub
      <$> strOption
            (long "from-file" <> metavar "TARBALL"
            <> help "Install a .tar.gz package into the local hub cache (~/.llmll/modules/)")

    hubScaffoldCmd = CmdHubScaffold
      <$> (T.pack <$> strArgument (metavar "TEMPLATE" <> help "Template name (e.g. todo-app, rest-api)"))
      <*> optional (strOption
            (short 'o' <> long "output" <> metavar "DIR"
            <> help "Output directory (default: ./<template>/)"))

    hubQueryCmd = CmdHubQuery
      <$> (T.pack <$> strOption
            (long "signature" <> short 's' <> metavar "SIG"
            <> help "Type signature to search for (e.g. 'int -> int -> int')"))

    verifyCmd = CmdVerify
      <$> fileArg
      <*> optional (strOption
            (short 'o' <> long "fq-out" <> metavar "FILE"
            <> help "Write .fq constraint file to FILE (default: <name>.fq in /tmp)"))
      <*> leanstralOpts
      <*> switch (long "trust-report"
            <> help "v0.3.2: Print transitive trust summary instead of running fixpoint")
      <*> switch (long "weakness-check"
            <> help "v0.3.5: After SAFE, check if trivial implementations also satisfy contracts")
      <*> switch (long "obligations"
            <> help "v0.4: On UNSAFE, suggest postcondition strengthenings on callees")
      <*> switch (long "spec-coverage"
            <> help "v0.6: Print specification coverage report")
      <*> switch (long "strict-verified-core"
            <> help "v0.9.0 + INT-1 v0.10.8: Hard-error if any function falls back from body-faithful verification or carries overflow-tainted verified evidence")
      <*> switch (long "obligation-report"
            <> help "v0.10: Emit structured obligation report (JSON, OBLIG-0 spec §2.1)")
      <*> switch (long "cdp"
            <> help "LT-CDP (v0.11): Compute contract discriminative power per function; emits discriminative_axis block in --trust-report --json")
      <*> optional (strOption
            (long "proof-artifact" <> metavar "FILE"
            <> help "PROOF-ARTIFACT: write a unified, replayable verification record to FILE"))

    leanstralOpts = LeanstralOpts
      <$> switch (long "leanstral-mock"
            <> help "Use mock Leanstral prover (returns 'by sorry')")
      <*> optional (strOption
            (long "leanstral-cmd" <> metavar "PATH"
            <> help "Path to lean-lsp-mcp binary"))
      <*> option auto
            (long "leanstral-timeout" <> value 30 <> metavar "SECS"
            <> help "Leanstral timeout in seconds (default: 30)")

    typecheckCmd = CmdTypecheck
      <$> fileArg
      <*> switch (long "sketch" <> help "Run bidirectional sketch inference — report inferred hole types")

    serveCmd = CmdServe <$> (ServeOptions
      <$> option auto
            (long "port" <> value 7777 <> metavar "PORT"
             <> help "Port to listen on (default: 7777)")
      <*> strOption
            (long "host" <> value "127.0.0.1" <> metavar "HOST"
             <> help "Host to bind (default: 127.0.0.1; TLS via reverse proxy)")
      <*> optional (strOption
            (long "token" <> metavar "TOKEN"
             <> help "Bearer token (default: auto-generated); use \"\" to disable auth")))

    checkoutCmd = mkCheckout
      <$> strArgument (metavar "FILE" <> help "Path to .ast.json file")
      <*> optional (strOption (long "release" <> metavar "TOKEN" <> help "Release a checkout lock"))
      <*> optional (strOption (long "status" <> metavar "TOKEN" <> help "Query remaining TTL for a token"))
      <*> optional (strArgument (metavar "POINTER" <> help "RFC 6901 pointer to hole (e.g. /statements/2/body)"))

    mkCheckout fp (Just tok) _ _          = CmdCheckoutRelease fp tok
    mkCheckout fp _ (Just tok) _          = CmdCheckoutStatus fp tok
    mkCheckout fp _ _ (Just ptr)          = CmdCheckout fp ptr
    mkCheckout fp _ _ Nothing             = CmdCheckout fp ""  -- will error in handler

    patchCmd = CmdPatch
      <$> strArgument (metavar "FILE" <> help "Path to .ast.json source file")
      <*> strArgument (metavar "PATCH" <> help "Path to patch-request.json")

    replayCmd = CmdReplay
      <$> strArgument (metavar "FILE" <> help "Path to .llmll source file")
      <*> strArgument (metavar "LOG" <> help "Path to .event-log.jsonl file")

    holesCmd = CmdHoles
      <$> fileArg
      <*> switch (long "deps" <> help "v0.3.3: Include dependency graph in --json output")
      <*> optional (strOption
            (long "deps-out" <> metavar "FILE"
            <> help "v0.3.3: Write dependency graph to FILE (implies --deps)"))

    specCmd = CmdSpec
      <$> switch (long "json" <> help "Output as JSON (default: formatted text for LLM prompts)")


-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  opts <- execParser optionsParser
  let json = optJson opts
      gm   = optGrammarMode opts
  case optCommand opts of
    CmdCheck fp strict            -> doCheck  json gm fp strict
    CmdHoles fp deps mDepsOut     -> doHoles  json gm fp deps mDepsOut
    CmdTest  fp emitOnly          -> doTest   json gm fp emitOnly
    CmdBuild fp mOut wasm emitJson emitOnly contracts -> doBuild json gm fp mOut wasm emitJson emitOnly contracts
    CmdBuildFromJson fp mOut emitOnly contracts -> doBuildFromJson json gm fp mOut emitOnly contracts
    CmdRun   fp args              -> doRun    json gm fp args
    CmdRepl                       -> doRepl gm
    CmdHub   tarball              -> doHubFetch json tarball
    CmdHubScaffold tmpl mOut      -> doHubScaffold json gm tmpl mOut
    CmdHubQuery sig               -> doHubQuery json GrammarLegacy sig
    CmdVerify fp mFqOut lsOpts trustRpt weakCheck obligs specCov strictCore obligReport cdpFlag mPa -> doVerify json gm fp mFqOut lsOpts trustRpt weakCheck obligs specCov strictCore obligReport cdpFlag mPa
    CmdReplayArtifact af -> doReplayArtifact json af
    CmdTypecheck fp sketch        -> doTypecheck json gm fp sketch
    CmdServe serveOpts            -> runServe serveOpts
    CmdCheckout fp ptr            -> doCheckout json gm fp (T.pack ptr)
    CmdCheckoutRelease fp tok     -> doCheckoutRelease json fp (T.pack tok)
    CmdCheckoutStatus fp tok      -> doCheckoutStatusCmd json fp (T.pack tok)
    CmdPatch fp patchFp           -> doPatch json gm fp patchFp
    CmdReplay fp logFp            -> doReplay json gm fp logFp
    CmdSpec jsonOut               -> doSpec jsonOut
    CmdVersion                    -> doVersion json

-- ---------------------------------------------------------------------------
-- Shared source loader
-- ---------------------------------------------------------------------------

-- | Parse source (S-expression or JSON-AST). Dispatches on file extension.
-- .ast.json / .json files are read as ByteString and routed to ParserJSON;
-- all other files go through the S-expression parser.
parseSrc :: GrammarMode -> FilePath -> T.Text -> Either Diagnostic [Statement]
parseSrc gm fp src =
  -- JSON path is handled by loadStatements (reads as BS); this path is S-expr only.
  case parseTopLevel gm fp src of
    Right stmts -> Right stmts
    Left  err   -> Left (megaparsecToDiagnostic fp err)

-- | Parse source from a lazy ByteString (used for .ast.json files).
parseSrcBS :: GrammarMode -> FilePath -> BL.ByteString -> Either Diagnostic [Statement]
parseSrcBS mode fp bs = parseJSONAST mode fp bs

-- | Unified file loader: reads the file and dispatches to the right parser.
-- Returns Left () if an error was already emitted to stdout/stderr.
loadStatements :: Bool -> GrammarMode -> FilePath -> IO (Either () [Statement])
loadStatements json gm fp
  | takeExtension fp == ".json" = do
      bs <- BL.readFile fp
      case parseSrcBS gm fp bs of
        Left diag -> do { emitParseDiag json fp diag; return (Left ()) }
        Right ss  -> return (Right ss)
  | otherwise = do
      src <- TIO.readFile fp
      case parseSrc gm fp src of
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
loadStatementsMulti :: Bool -> GrammarMode -> FilePath -> IO (Either () ([Statement], ModuleCache, [ModulePath]))
loadStatementsMulti json gm fp = do
  mStmts <- loadStatements json gm fp
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
          res <- loadModule gm j srcRoot [] c [] path
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

doCheck :: Bool -> GrammarMode -> FilePath -> Bool -> IO ()
doCheck json gm fp strict = do
  mResult <- loadStatementsMulti json gm fp
  case mResult of
    Left ()                      -> exitFailure
    Right (ss, cache, _loadOrder) -> do
      let report = if strict
                     then typeCheckStrictWithCache gm cache emptyEnv ss
                     else typeCheckWithCache gm cache emptyEnv ss
      if json
        then TIO.putStrLn (formatReportJson report)
        else if reportSuccess report
          then do
            let warns = [d | d <- reportDiagnostics report, diagSeverity d == SevWarning]
            if null warns
              then TIO.putStrLn $
                "\x2705 " <> T.pack fp <> " \8212 OK (" <> tshow (length ss) <> " statements)"
              else do
                TIO.putStrLn $
                  "\x2705 " <> T.pack fp <> " \8212 OK (" <> tshow (length ss) <> " statements, "
                  <> tshow (length warns) <> " warning" <> (if length warns == 1 then "" else "s") <> ")"
                mapM_ (TIO.putStrLn . formatDiagnostic) warns
          else mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics report)
      if reportSuccess report then exitSuccess else exitFailure

-- ---------------------------------------------------------------------------
-- holes
-- ---------------------------------------------------------------------------

doHoles :: Bool -> GrammarMode -> FilePath -> Bool -> Maybe FilePath -> IO ()
doHoles json gm fp deps mDepsOut = do
  stmts <- loadStatements json gm fp
  case stmts of
    Left () -> exitFailure
    Right ss -> do
      let includeDeps = deps || isJust mDepsOut
          report = if includeDeps
                   then analyzeHolesWithDeps ss
                   else analyzeHoles ss
          warnings = holeDensityWarnings ss
      -- Emit density warnings to stderr (informational, not blocking)
      forM_ warnings $ \w ->
        hPutStrLn stderr (T.unpack ("WARNING: " <> diagMessage w))
      if json
        then do
          let jsonOut = formatHoleReportJson fp includeDeps report
          TIO.putStrLn jsonOut
          -- v0.3.3: optionally write deps to file
          case mDepsOut of
            Just outFile -> TIO.writeFile outFile jsonOut
            Nothing      -> pure ()
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

doTest :: Bool -> GrammarMode -> FilePath -> Bool -> IO ()
doTest json gm fp emitOnly = do
  -- MOD-PBT-1: use loadStatementsMulti so PBT FuncEnv can see imported
  -- def-logic via assembleTestStatements (F-018 closure).
  mResult <- loadStatementsMulti json gm fp
  case mResult of
    Left ()    -> exitFailure
    Right (stmts, cache, _loadOrder) -> do
      let mergedStmts = assembleTestStatements stmts cache
      -- --emit-only: generate the QuickCheck Haskell source and print it,
      -- but skip running stack test (avoids Stack project lock deadlock when
      -- called from inside a running `stack exec llmll` session).
      if emitOnly
        then do
          let modName = T.pack $ takeBaseName fp
              result  = generateHaskell modName mergedStmts
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
          result <- runPropertyTests mergedStmts
          -- OBLIG-PBT-3: write back PBTPassed evidence to .verified.json.
          -- Singleton head-position contracted callee lifts to DLTested n;
          -- multi-subject / skipped / failed produce diagnostics, no lift.
          let (pbtCS, pbtDiags) = pbtTrustWriteback stmts cache result
          unless (Map.null pbtCS) $ do
            existing <- loadVerified fp
            -- pbtCS on the sidecar side so DLTested upgrades any DLAsserted;
            -- existing DLVerified / DLContractChecked are preserved by
            -- evidenceCovers (Syntax.hs:363) — DLTested does not cover them.
            saveVerified fp (Map.unionWith mergeCS pbtCS existing)
          if json
            then TIO.putStrLn (pbtResultJson fp result pbtDiags)
            else do
              printPbtResult fp result
              unless (null pbtDiags) $ do
                TIO.putStrLn "   .verified.json write-back diagnostics:"
                mapM_ (\d -> TIO.putStrLn ("     ⚠ " <> d)) pbtDiags
              unless (Map.null pbtCS) $
                TIO.putStrLn $ "   .verified.json updated: "
                            <> tshow (Map.size pbtCS) <> " PBT witness(es) recorded"
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

pbtResultJson :: FilePath -> PBTResult -> [T.Text] -> T.Text
pbtResultJson fp r writebackDiags =
  T.pack . BLC.unpack . encode $ object
    [ "file"    .= fp
    , "total"   .= pbtTotal r
    , "passed"  .= pbtPassed r
    , "failed"  .= pbtFailed r
    , "skipped" .= pbtSkipped r
    , "results" .= map runJson (pbtResults r)
    -- OBLIG-PBT-3: additive — pre-existing v0.10.5 consumers ignore the key.
    , "writeback_diagnostics" .= writebackDiags
    ]
  where
    runJson run = object
      [ "description"   .= pbtDescription run
      , "status"        .= (show (pbtStatus run) :: String)
      , "samples_run"   .= pbtSamplesRun run
      , "counterexample".= pbtCounterexample run
      ]
-- ---------------------------------------------------------------------------
-- build (Haskell codegen + optional WASM)
-- ---------------------------------------------------------------------------

doBuild :: Bool -> GrammarMode -> FilePath -> Maybe FilePath -> Bool -> Bool -> Bool -> ContractsMode -> IO ()
doBuild json gm fp mOutDir doWasm emitJson emitOnly contractsMode = do
  unless (json || contractsMode == ContractsFull) $
    TIO.putStrLn $ "   --contracts=" <> T.pack (show contractsMode)
  -- Auto-detect JSON-AST files and delegate to the JSON build path.
  if takeExtension fp == ".json"
    then doBuildFromJson json gm fp mOutDir emitOnly contractsMode
    else do
      -- --emit json-ast: parse the file directly to round-trip to JSON (no module merge needed)
      when emitJson $ do
        src <- TIO.readFile fp
        case parseSrc gm fp src of
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
      mResult <- loadStatementsMulti json gm fp
      case mResult of
        Left () -> exitFailure
        Right (stmts, cache, loadOrder) -> do
          let modName      = T.pack $ takeBaseName fp
              importedEnvs = topoSortedEnvs cache loadOrder
          -- v0.6.3: typecheck gate (BUG-4) — hard error before codegen
          let tcReport = typeCheckStrictWithCache gm cache emptyEnv stmts
          unless (reportSuccess tcReport) $ do
            mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics tcReport)
            exitFailure
          let -- v0.6.3: collect contract statuses and instrument contracts per mode (BUG-2)
              allCS = Map.foldl' (\acc menv -> Map.union (meContractStatus menv) acc)
                                Map.empty cache
              instrumentedStmts = instrumentContracts contractsMode allCS stmts
              result       = generateHaskellMulti modName importedEnvs instrumentedStmts
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

doBuildFromJson :: Bool -> GrammarMode -> FilePath -> Maybe FilePath -> Bool -> ContractsMode -> IO ()
doBuildFromJson json gm fp mOutDir emitOnly contractsMode = do
  -- P3: use loadStatementsMulti to resolve imports and get load-order
  mResult <- loadStatementsMulti json gm fp
  case mResult of
    Left () -> exitFailure
    Right (stmts, cache, loadOrder) -> do
      let rawName = T.pack $ takeBaseName fp
          modName = T.replace ".ast" "" rawName
          -- P3: collect imported envs in topo order and call generateHaskellMulti
          importedEnvs = topoSortedEnvs cache loadOrder
      -- v0.6.3: typecheck gate (BUG-4)
      let tcReport = typeCheckStrictWithCache gm cache emptyEnv stmts
      unless (reportSuccess tcReport) $ do
        mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics tcReport)
        exitFailure
      let -- v0.6.3: instrument contracts (BUG-2)
          allCS = Map.foldl' (\acc menv -> Map.union (meContractStatus menv) acc)
                            Map.empty cache
          instrumentedStmts = instrumentContracts contractsMode allCS stmts
          result  = generateHaskellMulti modName importedEnvs instrumentedStmts
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

doRun :: Bool -> GrammarMode -> FilePath -> [String] -> IO ()
doRun json gm fp extraArgs = do
  let modName = T.unpack . T.pack $ takeBaseName fp
      tmpDir  = "/tmp/llmll-run-" <> modName
  -- Build into tmp dir (reuses doBuild logic via shared helpers)
  src <- TIO.readFile fp
  case parseSrc gm fp src of
    Left diag -> do
      emitParseDiag json fp diag
      exitFailure
    Right stmts -> do
      -- v0.6.3: typecheck gate (BUG-4)
      let tcReport = typeCheckStrict gm emptyEnv stmts
      unless (reportSuccess tcReport) $ do
        mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics tcReport)
        exitFailure
      let modNameT = T.pack modName
          -- v0.6.3: instrument contracts (BUG-2) — full mode for run
          instrumentedStmts = instrumentContracts ContractsFull Map.empty stmts
          result   = generateHaskell modNameT instrumentedStmts
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
      (code, _out, stderr_) <- readCreateProcessWithExitCode
        (proc stackBin ["build", "--no-terminal"]) { cwd = Just outDir } ""
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
          (code, _out, stderr_) <- readCreateProcessWithExitCode
            (proc ghcBin ["--make", "-isrc", "src/Lib.hs"]) { cwd = Just outDir } ""
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

doRepl :: GrammarMode -> IO ()
doRepl gm = do
  TIO.putStrLn "LLMLL REPL v0.1 — type :help for commands, :quit to exit"
  TIO.putStrLn "Parse expressions and see their AST representation."
  TIO.putStrLn ""
  replLoop gm Map.empty

replLoop :: GrammarMode -> Map.Map T.Text T.Text -> IO ()
replLoop gm _env = do
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
      replLoop gm _env
    _ | T.isPrefixOf ":check " trimmed -> do
        let fp = T.unpack (T.drop 7 trimmed)
        doCheck False gm fp False
        replLoop gm _env
      | T.isPrefixOf ":holes " trimmed -> do
        let fp = T.unpack (T.drop 7 trimmed)
        doHoles False gm fp False Nothing
        replLoop gm _env
      | T.null trimmed -> replLoop gm _env
      | otherwise -> do
          -- Try to parse as a statement or expression
          case parseTopLevel gm "<repl>" trimmed of
            Left err ->
              TIO.putStrLn $ formatDiagnosticSExp (megaparsecToDiagnostic "<repl>" err)
            Right stmts -> do
              mapM_ (\stmt -> TIO.putStrLn $ T.pack (show stmt)) stmts
              let report = typeCheck gm emptyEnv stmts
              mapM_ (TIO.putStrLn . ("  type: " <>) . formatDiagnostic)
                    (reportDiagnostics report)
          replLoop gm _env

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

-- ---------------------------------------------------------------------------
-- v0.3: hub scaffold
-- ---------------------------------------------------------------------------

doHubScaffold :: Bool -> GrammarMode -> T.Text -> Maybe FilePath -> IO ()
doHubScaffold json gm template mOutDir = do
  mPath <- resolveScaffold template
  case mPath of
    Nothing -> do
      let msg = "Template '" <> T.unpack template <> "' not found in ~/.llmll/templates/."
      if json
        then TIO.putStrLn . T.pack . BLC.unpack . encode $
               object ["success" .= False, "error" .= msg]
        else do
          hPutStrLn stderr msg
          hPutStrLn stderr "Install with: llmll hub fetch --from-file <tarball>"
      exitFailure
    Just srcPath -> do
      let outDir = fromMaybe (T.unpack template) mOutDir
      createDirectoryIfMissing True outDir
      -- Copy scaffold file
      srcBytes <- BL.readFile srcPath
      let outFile = outDir </> takeFileName srcPath
      BL.writeFile outFile srcBytes
      -- Parse and report holes
      mStmts <- loadStatements json gm outFile
      case mStmts of
        Left () -> do
          unless json $ TIO.putStrLn $ "   Scaffolded to " <> T.pack outDir <> " (parse errors — holes not analyzed)"
          exitSuccess
        Right stmts -> do
          let report = analyzeHoles stmts
          if json
            then TIO.putStrLn (formatHoleReportJson outFile False report)
            else do
              TIO.putStrLn $ "\x2705 Scaffolded '" <> template <> "' \8594 " <> T.pack outDir
              TIO.putStrLn $ "   " <> tshow (totalHoles report) <> " holes ("
                <> tshow (blockingHoles report) <> " blocking)"
          exitSuccess

-- ---------------------------------------------------------------------------
-- v0.6.1: hub query
-- ---------------------------------------------------------------------------

doHubQuery :: Bool -> GrammarMode -> T.Text -> IO ()
doHubQuery json _gm sigText = do
  -- Parse the signature text into a Type for matching.
  -- Simple format: "int -> int -> int" for a 2-arg function returning int.
  let queryType = parseSigText sigText
  results <- queryBySignature queryType
  if json
    then TIO.putStrLn . T.pack . BLC.unpack . encode $
           object
             [ "query"   .= sigText
             , "results" .= map resultToJson results
             ]
    else do
      if null results
        then TIO.putStrLn $ "No hub modules match signature: " <> sigText
        else do
          TIO.putStrLn $ "Hub query: " <> sigText
          TIO.putStrLn $ T.replicate 50 "─"
          mapM_ printResult results
          TIO.putStrLn $ T.replicate 50 "─"
          TIO.putStrLn $ tshow (length results) <> " match(es) found"
  where
    resultToJson r = object
      [ "module"      .= qrModulePath r
      , "function"    .= qrFuncName r
      , "signature"   .= qrSignature r
      , "has_contract" .= qrHasContract r
      ]
    printResult r = do
      let contractMark = if qrHasContract r then " ✅" else ""
      TIO.putStrLn $ "  " <> qrModulePath r <> "." <> qrFuncName r
        <> " : " <> qrSignature r <> contractMark

-- | Parse a simplified type signature string into a Type.
-- Supports: "int", "string", "bool", "bytes[N]", "a -> b -> c" (function),
-- and "list[T]", "Result[T, E]".
-- TVars: any single lowercase letter is treated as a wildcard TVar.
parseSigText :: T.Text -> Type
parseSigText sig =
  let parts = map T.strip (T.splitOn "->" sig)
  in case parts of
    []  -> TVar "?"
    [t] -> parseOneType t
    _   -> let args = map parseOneType (init parts)
               ret  = parseOneType (last parts)
           in TFn args ret

parseOneType :: T.Text -> Type
parseOneType t
  | t == "int"    = TInt
  | t == "float"  = TFloat
  | t == "string" = TString
  | t == "bool"   = TBool
  | t == "unit"   = TUnit
  | "bytes[" `T.isPrefixOf` t && "]" `T.isSuffixOf` t =
      let nText = T.drop 6 (T.dropEnd 1 t)
      in case reads (T.unpack nText) of
           [(n, "")] -> TBytes n
           _         -> TCustom t
  | "list[" `T.isPrefixOf` t && "]" `T.isSuffixOf` t =
      TList (parseOneType (T.drop 5 (T.dropEnd 1 t)))
  | T.length t == 1 && T.all (\c -> c >= 'a' && c <= 'z') t = TVar t
  | otherwise = TCustom t

-- ---------------------------------------------------------------------------
-- D4: verify (liquid-fixpoint)
-- ---------------------------------------------------------------------------

-- | VERIFY-RPT-1 (Commit 4): map a solver verdict to a process exit code.
-- SAFE succeeds; UNSAFE (refuted) and solver ERROR fail closed. Used by the
-- report-flag early-exit paths so they agree with the final verdict routing
-- and never exit 0 on a disproved file.
fqExitCode :: FQVerifyResult -> ExitCode
fqExitCode FQSafe        = ExitSuccess
fqExitCode (FQUnsafe _)  = ExitFailure 1
fqExitCode (FQError _)   = ExitFailure 1

doVerify :: Bool -> GrammarMode -> FilePath -> Maybe FilePath -> LeanstralOpts -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Maybe FilePath -> IO ()
doVerify json gm fp mFqOut lsOpts trustReport weaknessCheck obligations specCoverage strictCore obligationReport cdpFlag mProofArtifact = do
  -- 1. Parse + type-check
  mResult <- loadStatementsMulti json gm fp
  case mResult of
    Left () -> exitFailure
    Right (stmts, _cache, _) -> do
      -- ADMIT-VERIFIED (Option 2, seam 6): load the entry file's OWN
      -- '.verified.json' BEFORE the strict-core type-check gate and validate it
      -- against the live def bodies+contracts ('downgradeStaleVerifiedSidecar'),
      -- so a same-file 'def'→'def' callee verified in a prior pass is admitted.
      -- Validation (the staleness guard) runs here so an absent/stale hash is
      -- demoted before the admission leg sees it (soundness (iii)+(iv)). The
      -- COLD first-ever-verify case still rejects (no prior sidecar) — the
      -- accepted LT-INV §3.5 "verify-then-build" cost; not fixed here.
      entrySidecarRaw <- loadVerified fp
      let (entrySidecar, _staleDiags) = downgradeStaleVerifiedSidecar stmts entrySidecarRaw
      -- v0.6.3: typecheck gate (BUG-4)
      let tcReport = typeCheckStrictWithCacheAndStatus gm _cache entrySidecar emptyEnv stmts
      unless (reportSuccess tcReport) $ do
        mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics tcReport)
        exitFailure
      -- v0.3.2: --trust-report mode — print trust summary and exit
      -- LT-CDP (v0.11): when '--cdp' is also requested, defer the trust-report
      -- emit to the post-solver path so 'discriminative_axis' can be
      -- populated from the CDP measurement.
      -- VERIFY-RPT-1 (Commit 4): also defer when '--strict-verified-core' is
      -- set, so the solver runs and the post-solver gate can both render
      -- 'refuted' and fail the build closed. A solver-less '--trust-report'
      -- render shows 'asserted' (no refuted info) by design — see the refuted
      -- proposal edge case 3.
      when (trustReport && not cdpFlag && not strictCore) $ do
        -- v0.9.0: the .verified.json sidecar makes the trust report reflect solver
        -- results. Use the staleness-GATED 'entrySidecar' (line ~1108), not a fresh
        -- raw reload — otherwise a stale verdict (e.g. a return-annotation or post
        -- edit leaving body/pre identical) renders as live 'verified'. DEF-RET Unit 2
        -- surfaced this pre-existing solver-less-display staleness bypass.
        let report = buildTrustReport _cache stmts entrySidecar
        if json
          then TIO.putStrLn (formatTrustReportJson report)
          else TIO.putStr (formatTrustReport report)
        exitSuccess
      -- v0.6: --spec-coverage mode — print coverage report and exit
      when specCoverage $ do
        let coverageReport = runCoverage stmts Map.empty  -- TODO: load sidecar in Sprint 3
        if json
          then TIO.putStrLn (formatCoverageJson coverageReport)
          else TIO.putStr (formatCoverageText coverageReport)
        exitSuccess
      -- 2. Emit .fq constraints + build ConstraintTable (v0.8.0: body VCs enabled)
      let emitOpts = defaultEmitOptions { emitBodyVCs = True }
      emitR <- emitFixpointWith emitOpts fp stmts
      let fqText = erFQText emitR
          table  = erConstraintTable emitR
          skipped = erSkipped emitR

      -- 3. Write .fq file
      let baseName = takeBaseName fp
          fqPath   = case mFqOut of
                       Just p  -> p
                       Nothing -> "/tmp/" <> baseName <> ".fq"
      TIO.writeFile fqPath fqText
      unless json $ do
        TIO.putStrLn $ "   .fq written to " <> T.pack fqPath
        unless (null skipped) $
          TIO.putStrLn $ "   skipped (non-linear): " <> T.intercalate ", " skipped
        -- v0.8.0: report body-faithful and fallback functions
        unless (null (erBodyFaithfulFns emitR)) $
          TIO.putStrLn $ "   body-faithful: " <> T.intercalate ", " (erBodyFaithfulFns emitR)
        unless (null (erBodyFallback emitR)) $
          TIO.putStrLn $ "   body-fallback: " <> T.intercalate ", " (erBodyFallback emitR)
        -- v0.8.0: surface diagnostics (path-limit warnings etc.)
        mapM_ (\d -> TIO.putStrLn $ "   ⚠️  " <> diagMessage d) (erDiagnostics emitR)
        -- v0.9.0: report call-pre obligations
        unless (null (erCallPreFns emitR)) $
          TIO.putStrLn $ "   call-pre obligations: " <> T.intercalate ", " (erCallPreFns emitR)
        -- INT-1 (v0.10.8): report overflow-tainted body-faithful functions.
        unless (null (erOverflowTaintedFns emitR)) $
          TIO.putStrLn $ "   overflow-tainted: " <> T.intercalate ", " (erOverflowTaintedFns emitR)

      -- v0.9.0 COMP-6 + INT-1 (v0.10.8): --strict-verified-core enforcement.
      -- Refuses both (a) functions that fell back from body-faithful verification
      -- and (b) body-faithful functions whose verified evidence is overflow-tainted
      -- (sound modulo the Int64 overflow gap at LLMLL.md §5.3.5). The two
      -- categories are mutually exclusive — overflow-taint is gated on
      -- body-faithful success — so a function appears in at most one list.
      when strictCore $ do
        let fallbacks = erBodyFallback emitR
            tainted   = erOverflowTaintedFns emitR
            errs :: [(T.Text, [T.Text], T.Text)]
            errs = [ ("fallback", fallbacks
                    , T.pack (show (length fallbacks))
                      <> " function(s) fell back from body-faithful verification: "
                      <> T.intercalate ", " fallbacks)
                   | not (null fallbacks)
                   ]
                ++ [ ("overflow_tainted", tainted
                    , T.pack (show (length tainted))
                      <> " function(s) carry overflow-tainted verified evidence "
                      <> "(unbounded-Int arithmetic; clear via ?proof-required + Leanstral or wait for INT-2 unbounded `int`): "
                      <> T.intercalate ", " tainted)
                   | not (null tainted)
                   ]
        unless (null errs) $ do
          if json
            then TIO.putStrLn . T.pack . BLC.unpack . encode $
                   object $ ["file" .= fp]
                         ++ [ "strict_errors" .= [ object [ "cause" .= cause
                                                         , "fns"   .= fns
                                                         , "msg"   .= msg
                                                         ]
                                                | (cause, fns, msg) <- errs ]
                            ]
            else mapM_ (\(_cause, _fns, msg) ->
                          TIO.putStrLn $ "ERROR: --strict-verified-core: " <> msg) errs
          exitFailure

      -- 4. Find liquid-fixpoint binary (installs as "fixpoint" or "liquid-fixpoint")
      mLF <- do
        a <- findExecutable "liquid-fixpoint"
        case a of
          Just _ -> return a
          Nothing -> findExecutable "fixpoint"
      case mLF of
        Nothing -> do
          -- No SMT backend on PATH: the proof did NOT run. Make this
          -- unmistakable -- a first-timer must not read silence as success
          -- -- and exit with a distinct non-zero code (3 = solver unavailable,
          -- distinct from 1 = refuted / strict-core). The .fq stub is still
          -- written so an expert can run fixpoint by hand.
          let reason = "liquid-fixpoint / z3 not found on PATH -- the proof did NOT run"
          if json
            then TIO.putStrLn . T.pack . BLC.unpack . encode $
                   object [ "file" .= fp, "fq_file" .= fqPath
                           , "verified" .= False
                           , "solver_available" .= False
                           , "reason" .= (reason <> "; .fq written to " <> T.pack fqPath) ]
            else mapM_ TIO.putStrLn
                   [ ""
                   , "  ============================================================"
                   , "  !!  SOLVER NOT FOUND -- NOTHING WAS PROVEN"
                   , "  ============================================================"
                   , "  'llmll verify' needs liquid-fixpoint + z3 to discharge proofs."
                   , "  Neither was found on PATH, so the contract was NOT checked."
                   , "  (This is not a pass -- no proof ran.)"
                   , ""
                   , "  Install the backend locally:"
                   , "    stack install liquid-fixpoint   # provides the 'fixpoint' binary"
                   , "    brew install z3                 # (or apt-get install z3)"
                   , ""
                   , "  (.fq constraints written to " <> T.pack fqPath <> " for manual runs.)"
                   , "  ============================================================"
                   ]
          -- v0.10 F8: obligation-report degradation (no solver → all status="open")
          when obligationReport $ do
            sidecar <- loadVerified fp
            let trustRpt = buildTrustReport _cache stmts sidecar
                reportText = assembleReport fp stmts _cache emitR Nothing trustRpt
            TIO.putStrLn reportText
          exitWith (ExitFailure 3)   -- distinct: solver unavailable (proof did not run)

        Just lfBin -> do
          -- 5. Run liquid-fixpoint
          unless json $ TIO.putStrLn "   Running liquid-fixpoint ..."
          -- VERIFY-RPT-1 (Commit 2): invoke with '-q --json' so the verdict
          -- carries resolvable constraint ids. '-q' suppresses the human banner
          -- (otherwise the JSON line is ANSI-prefixed and banner-wrapped), and
          -- '--json' selects the structured envelope. Fall back to the text
          -- scrape when the JSON envelope does not parse (a differently-built
          -- fixpoint, or a crash with no envelope).
          (_code, out, err) <- readProcessWithExitCode lfBin ["-q", "--json", fqPath] ""
          let outT     = T.pack out
              merged   = outT <> T.pack err
              fqResult = fromMaybe (parseFQResult merged) (parseFQResultJSON merged)
              -- VERIFY-RPT-1 (Commit 4): refuted functions = body-faithful fns
              -- named by the constraint-table origin of each unsafe id.
              bodyFaithfulSet = Set.fromList (erBodyFaithfulFns emitR)
              refutedSet = case fqResult of
                FQUnsafe ids -> Set.fromList
                  [ coFunction o
                  | i <- ids, Just o <- [Map.lookup i table]
                  , Set.member (coFunction o) bodyFaithfulSet ]
                _ -> Set.empty

          -- v0.10: --obligation-report (runs regardless of SAFE/UNSAFE). The
          -- embedded trust report is refuted-marked. Under
          -- '--strict-verified-core' do not exit here — fall through to the
          -- post-solver gate so a refuted result fails closed.
          when obligationReport $ do
            oblSidecar <- loadVerified fp
            let trustRpt = markRefuted refutedSet (buildTrustReport _cache stmts oblSidecar)
                reportText = assembleReport fp stmts _cache emitR (Just fqResult) trustRpt
            TIO.putStrLn reportText
            -- VERIFY-RPT-1 (Commit 4): exit on the solver verdict, not
            -- unconditionally — a refuted file must fail closed even via the
            -- obligation-report view. Under '--strict-verified-core' fall through
            -- to the post-solver gate instead.
            unless strictCore (exitWith (fqExitCode fqResult))

          let report = fqResultToReport fp table fqResult

          -- PROOF-ARTIFACT: emit the unified, replayable record (additive, informational).
          case mProofArtifact of
            Nothing -> pure ()
            Just paPath -> do
              paSidecar <- loadVerified fp
              meta      <- captureSolverMeta lfBin
              srcHash   <- sourceHashOf fp
              let paTrust = markRefuted refutedSet (buildTrustReport _cache stmts paSidecar)
              case buildProofArtifact fp srcHash meta fqResult emitR paTrust of
                Left e   -> unless json $ TIO.putStrLn ("   proof-artifact NOT written (internal inconsistency): " <> renderLaunderError e)
                Right pa -> do
                  BL.writeFile paPath (encode pa)
                  unless json $ TIO.putStrLn ("   proof-artifact written to " <> T.pack paPath)

          -- 6. Report
          if json
            then do
              -- v0.8.0: augment JSON with body-faithful metadata
              let reportJson = formatReportJson report
                  bodyMeta = T.pack . BLC.unpack . encode $ object
                    [ "body_faithful" .= erBodyFaithfulFns emitR
                    , "body_fallback" .= erBodyFallback emitR
                    ]
              -- Merge by stripping closing } from report and appending body_meta fields
              let augmented = case (T.stripSuffix "}" reportJson, T.stripPrefix "{" bodyMeta) of
                    (Just base, Just extra) -> base <> "," <> extra
                    _ -> reportJson  -- fallback: just emit original
              TIO.putStrLn augmented
            else case fqResult of
              FQSafe ->
                TIO.putStrLn $ "\x2705 " <> T.pack fp <> " \8212 SAFE (liquid-fixpoint)"
              FQUnsafe _ -> do
                mapM_ (TIO.putStrLn . formatDiagnostic) (reportDiagnostics report)
                -- v0.4: --obligations mode
                when obligations $ do
                  oblSidecar <- loadVerified fp
                  let trustRpt = buildTrustReport _cache stmts oblSidecar
                      oblSugs  = mineObligations table fqResult trustRpt stmts
                  if json
                    then TIO.putStrLn (formatObligationsJson oblSugs)
                    else TIO.putStr (formatObligations oblSugs)
              FQError e ->
                TIO.putStrLn $ "ERROR: liquid-fixpoint: " <> e

          -- v0.3: write .verified.json sidecar on SAFE; return provenCS so the
          -- CDP block below can derive the verifMap oracle without a disk re-read.
          provenCS <- case fqResult of
            FQSafe -> do
              let bodyFaithfulSet     = Set.fromList (erBodyFaithfulFns emitR)
                  -- INT-1 (v0.10.8): functions whose body-faithful evidence carries
                  -- unbounded-Int arithmetic. Strict-verified-core refuses these;
                  -- non-strict consumers see the flag on the per-clause record.
                  overflowTaintedSet  = Set.fromList (erOverflowTaintedFns emitR)
                  -- v0.8.1b: Post gets DLVerified only when body-faithful VC
                  -- was emitted and solver returned SAFE. This means the solver
                  -- checked: P ∧ (result = ⟦body⟧) ⇒ Q.
                  -- Pre remains DLAsserted: preconditions are caller assumptions,
                  -- not function-side proof obligations. Call-site VCs are a v0.9 item.
                  provenCS = Map.fromList
                    [ (n, ContractStatus
                        { csPre  = fmap (const (EvidenceRecord DLAsserted False (contractPreSource c) [] False Nothing Nothing False Nothing))
                                       (contractPre c)
                            -- Pre remains asserted: no call-site VCs in v0.8.1b
                        , csPost = if Set.member n bodyFaithfulSet
                                   then let tainted = Set.member n overflowTaintedSet
                                            -- ADMIT-VERIFIED (Option 2, §6, soundness (iii)):
                                            -- stamp a hash over canonical (body, pre, post) +
                                            -- semantics tag on body-faithful SAFE post evidence.
                                            -- Untainted only — a tainted verdict is never
                                            -- admissible, so it carries no admission hash.
                                            hash = if tainted
                                                   then Nothing
                                                   else Just (canonicalDefEvidenceHash body (contractPre c) (contractPost cAug))
                                        in fmap (const (EvidenceRecord (DLVerified "liquid-fixpoint") True (contractPostSource c) [] tainted Nothing Nothing False hash))
                                                (contractPost cAug)
                                   else fmap (const (EvidenceRecord DLAsserted False (contractPostSource c) [] False Nothing Nothing False Nothing))
                                             (contractPost cAug)
                            -- Post verified only when body-faithful VC succeeded
                        , csAssumptions = []  -- v0.8.1b: deferred to v0.9
                        })
                    | s <- stmts
                    , Just (n, _, mRet, c, body) <- [normalizeDefStmt s]
                    -- DEF-RET Unit 2: fold the return refinement into the effective
                    -- post so it is credited (csPost) and covered by the staleness
                    -- hash. Post-only (the pre-side NIW hole is a separate ticket).
                    , let cAug = augmentContractPost (buildAliasMap stmts) mRet c
                    , contractPre c /= Nothing || contractPost cAug /= Nothing
                    ]
              -- TRUST-PRE (Part 2): persist the caller-obligation axis alongside
              -- the verified evidence. A 'requires' is a static contract
              -- property (it cannot go stale like the solver verdict), so unlike
              -- 'refuted' it IS persisted. The axis is computed by the trust
              -- report over the live source + the just-proven sidecar, then
              -- flattened to the shared '{fn, requires}' JSON shape.
              let obReport      = buildTrustReport _cache stmts provenCS
                  obligationJson = concatMap (map callerObligationJson . teCallerObligations)
                                             (trEntries obReport)
              saveVerifiedWith fp provenCS obligationJson
              unless json $ TIO.putStrLn $ "   .verified.json written to " <> T.pack (verifiedPath fp)
              pure provenCS
            _ -> pure Map.empty

          -- v0.3.5: Weakness check — only runs on SAFE results
          case fqResult of
            FQSafe | weaknessCheck -> do
              unless json $ TIO.putStrLn "   Running weakness check ..."
              let candidates = generateWeaknessCandidates gm stmts
                  typeDefs   = [s | s@STypeDef{} <- stmts]
              weakDiags <- fmap concat $ mapM (checkWeaknessCandidate lfBin json typeDefs) candidates
              if null weakDiags
                then unless json $ TIO.putStrLn "   No spec weaknesses detected."
                else do
                  unless json $ do
                    TIO.putStrLn $ "   ⚠ " <> tshow (length weakDiags) <> " spec weakness(es) detected:"
                    mapM_ (TIO.putStrLn . ("   " <>) . formatDiagnostic) weakDiags
                  when json $ do
                    let weakJson = object
                          [ "file" .= fp
                          , "weakness_check" .= True
                          , "weaknesses" .= map (\d -> object
                              [ "kind" .= diagKind d
                              , "message" .= diagMessage d
                              , "suggestion" .= diagSuggestion d
                              ]) weakDiags
                          ]
                    TIO.putStrLn . T.pack . BLC.unpack $ encode weakJson
            _ -> pure ()

          -- LT-CDP (v0.11): contract discriminative power — runs on SAFE results.
          -- CDPScopeCoreOnly: §8 gate PASSED (Outcome 0, 2026-05-28, postmortem-004);
          -- only def (strict-core) form is measured. def-shell and legacy def-logic
          -- forms emit WarnDefShellOutOfScope entries.  Per
          -- 'v0.11-cross-proposal-rollback-discipline.md' §2.1.
          -- The CDP result map is threaded into the trust report via
          -- 'buildTrustReportWithCDP' when '--trust-report --json' is also requested;
          -- otherwise it surfaces as a stdout summary block.
          cdpResults <- case (fqResult, cdpFlag) of
            (FQSafe, True) -> do
              unless json $ TIO.putStrLn "   Running CDP measurement (LT-CDP v0.11) ..."
              let cdpTypeDefs = [s | s@STypeDef{} <- stmts]
                  runOneCandidate wc = checkCDPCandidate lfBin cdpTypeDefs wc
                  verifMap = if trustReport
                        then Map.map (\cs ->
                                case csPost cs of
                                  Just er -> case erDisplayLevel er of
                                    DLVerified _        -> True
                                    DLContractChecked _ -> True
                                    _                   -> False
                                  Nothing -> False)
                              provenCS
                        else Map.empty
              unless trustReport $
                hPutStrLn stderr
                  "Note: --cdp without --trust-report: WarnSpecInconsistentOrUnproven used conservatively \
                  \for all zero-satisfying functions; pass --trust-report to enable \
                  \WarnSpecTooTightForOmega disambiguation."
              results <- computeCDPFor gm CDPScopeCoreOnly runOneCandidate verifMap stmts
              -- Module-level over-annotation diagnostic (proposal Risk #3).
              let intentRatio = overAnnotationRatio stmts
              when (intentRatio > overAnnotationThreshold) $
                unless json $ TIO.putStrLn $
                  "   ⚠ over-annotation-warning: "
                  <> T.pack (showFFloat (Just 1) (intentRatio * 100) "")
                  <> "% of contracted functions carry (spec-entropy :intentional); threshold is "
                  <> T.pack (showFFloat (Just 0) (overAnnotationThreshold * 100) "") <> "%"
              -- Non-JSON human summary: one line per measured function.
              unless json $ do
                let scored = Map.toAscList results
                if null scored
                  then TIO.putStrLn "   No contracted functions in scope for CDP."
                  else do
                    TIO.putStrLn $ "   CDP measured " <> tshow (length scored) <> " function(s):"
                    -- CDP deep-dive Rev 5 (item 2): the typed flag is the
                    -- headline (per the professor's flag-not-score
                    -- recommendation), the graded score is parenthetical and
                    -- shown only when it exists — no more "score=undefined"
                    -- leading a line that a warning already fully explains.
                    mapM_ (\(n, r) -> TIO.putStrLn $
                            "   " <> n <> ": "
                            <> (if null (cdpWarnings r)
                                  then ""
                                  else "[" <> T.intercalate ", " (map cdpWarningLabel (cdpWarnings r)) <> "] ")
                            <> maybe
                                 (tshow (cdpSatisfyingCount r) <> "/" <> tshow (cdpCandidateCount r) <> " reliable candidates")
                                 (\s -> "score=" <> T.pack (showFFloat (Just 3) s "")
                                        <> " (" <> tshow (cdpSatisfyingCount r) <> "/" <> tshow (cdpCandidateCount r) <> " candidates satisfy)")
                                 (cdpScore r)
                         ) scored
              pure results
            _ -> pure Map.empty

          -- LT-CDP (v0.11): when '--trust-report' was deferred (because '--cdp'
          -- was set), emit the trust report here so 'discriminative_axis' can
          -- be populated from the CDP map. The non-CDP early-exit at line ~1078
          -- already handled the trust-report-only path.
          -- VERIFY-RPT-1 (Commit 4): defer the CDP trust emit under
          -- '--strict-verified-core' too, so the gate below can fail closed.
          when (trustReport && cdpFlag && not strictCore) $ do
            sidecar <- loadVerified fp
            -- VERIFY-RPT-1 (Commit 4): mark refuted on the post-solver CDP path
            -- so 'refuted_fns' / per-entry 'refuted' are populated (the field
            -- emitters already exist; they were being fed an unmarked report).
            let report = markRefuted refutedSet
                           (buildTrustReportWithCDP _cache stmts sidecar cdpResults)
            if json
              then TIO.putStrLn (formatTrustReportJson report)
              else TIO.putStr (formatTrustReport report)
            -- VERIFY-RPT-1 (Commit 4): fail closed on a refuted/UNSAFE verdict
            -- instead of the prior unconditional exitSuccess (which re-opened the
            -- Defect-1 fail-open on '--trust-report --cdp'). Keyed identically to
            -- the final verdict routing below.
            exitWith (fqExitCode fqResult)

          -- VERIFY-RPT-1 (Commit 4): post-solver '--strict-verified-core'
          -- conjunct (c). The pre-solver gate (fallback/overflow-tainted) runs
          -- before the solver and cannot see the verdict; this refuses a
          -- body-faithful function the solver disproved (refuted), transitively
          -- per assume-guarantee. The '--trust-report'/'--obligation-report'
          -- early exits were deferred under strict mode so this point is
          -- reached; emit a refuted-marked trust report here when requested
          -- (and not already emitted via the obligation report) before failing.
          when strictCore $ do
            stSidecar <- loadVerified fp
            -- CDP deep-dive Rev 5 (item 6): was 'buildTrustReport', which
            -- drops 'discriminative_axis' to a uniform "not-requested" for
            -- every function under '--strict-verified-core --cdp --json',
            -- even pre-existing/untouched functions. The sibling non-strict
            -- branch above (cdpFlag && not strictCore) already threads
            -- 'cdpResults' correctly; this branch just never did.
            let stReport = markRefuted refutedSet (buildTrustReportWithCDP _cache stmts stSidecar cdpResults)
                refusal  = refutedClosure refutedSet stReport
            when (trustReport && not obligationReport) $
              if json
                then TIO.putStrLn (formatTrustReportJson stReport)
                else TIO.putStr (formatTrustReport stReport)
            unless (Set.null refusal) $ do
              if json
                then TIO.putStrLn . T.pack . BLC.unpack . encode $
                       object [ "file" .= fp
                              , "strict_errors" .=
                                  [ object
                                      [ "cause" .= ("refuted" :: T.Text)
                                      , "fns"   .= Set.toList refusal
                                      , "msg"   .= ("body-faithful function(s) disproved by liquid-fixpoint, or transitively depending on one: "
                                                    <> T.intercalate ", " (Set.toList refusal))
                                      ]
                                  ]
                              ]
                else mapM_ (\n -> TIO.putStrLn $ "ERROR: --strict-verified-core: refuted: " <> n)
                           (Set.toList refusal)
              exitFailure

          -- VERIFY-RPT-1 (Defect 1a): route the verdict through the
          -- 'FQVerifyResult' constructor, not the lossy 'reportSuccess'
          -- projection. An UNSAFE result that resolved no constraint id used to
          -- project 'reportSuccess = True' and fail open here; keying on the
          -- constructor makes 'FQUnsafe'/'FQError' fail closed unconditionally.
          -- Placed after the SAFE sidecar write above so SAFE still persists.
          case fqResult of
            FQSafe -> do
              -- v0.3.1: Leanstral proof pipeline (after liquid-fixpoint)
              when (lsMock lsOpts || isJust (lsCmd lsOpts)) $
                runLeanstralPipeline json fp stmts lsOpts
              exitSuccess
            FQUnsafe _ -> exitFailure
            FQError _  -> exitFailure

-- | LT-CDP (v0.11): Run the solver on one CDP candidate; return True iff the
-- solver reports SAFE (the candidate's trivial body satisfies the contract).
-- Mirrors 'checkWeaknessCandidate' but threads the SAFE/UNSAFE outcome rather
-- than constructing a spec-weakness diagnostic.
-- | CDP deep-dive Rev 5 (routed finding): the isolated per-candidate emission
-- omitted the module's 'STypeDef' statements — unlike 'tryCandidate''s
-- independent re-typecheck (WeaknessCheck.hs), which correctly prepends them
-- (F-006). Without them, any candidate whose contract references a custom
-- sum-type constructor (e.g. a nullary error-payload type) spuriously falls
-- back to non-body-faithful VC emission, even when the same candidate proves
-- body-faithful with the type-defs present — confirmed empirically: an
-- '(ok 0)' candidate against a 'Result[int, Reason]' contract falls back
-- given only '[wcSyntheticStmt wc]', but does not once 'Reason'\'s STypeDef
-- is included. Every caller now threads the module's type-defs through.
--
-- | CDP deep-dive Rev 5 (item 5): 'Nothing' means the candidate's own
-- synthetic body fell outside the QF-LIA-translatable fragment
-- ('erBodyFallback') — a solver verdict on that emission is not evidence the
-- candidate satisfies the contract, so the solver is never invoked for it.
checkCDPCandidate :: FilePath -> [Statement] -> WeaknessCandidate -> IO (Maybe Bool)
checkCDPCandidate lfBin typeDefs wc = do
  let weakOpts = defaultEmitOptions { emitBodyVCs = True }
      syntheticName = wcSyntheticName wc
  emitR <- emitFixpointWith weakOpts "<cdp-candidate>" (typeDefs ++ [wcSyntheticStmt wc])
  if syntheticName `elem` erBodyFallback emitR
    then pure Nothing
    else do
      let fqText = erFQText emitR
          fqPath = "/tmp/llmll-cdp-" <> T.unpack (wcFunctionName wc) <> ".fq"
      TIO.writeFile fqPath fqText
      (_, out, err) <- readProcessWithExitCode lfBin [fqPath] ""
      case parseFQResult (T.pack out <> T.pack err) of
        FQSafe -> pure (Just True)
        _      -> pure (Just False)

-- | Check a single weakness candidate: emit .fq, run solver, return diagnostic if SAFE.
checkWeaknessCandidate :: FilePath -> Bool -> [Statement] -> WeaknessCandidate -> IO [Diagnostic]
checkWeaknessCandidate lfBin _json typeDefs wc = do
  -- Emit .fq for the synthetic trivial statement (v0.8.0: body-aware)
  let weakOpts = defaultEmitOptions { emitBodyVCs = True }
      syntheticName = wcSyntheticName wc
  emitR <- emitFixpointWith weakOpts "<weakness-check>" (typeDefs ++ [wcSyntheticStmt wc])
  -- CDP deep-dive Rev 5 (item 5): if the candidate's own body fell outside
  -- the QF-LIA-translatable fragment, a solver verdict on it would be
  -- meaningless. Do not run the solver, and do not silently return [] either
  -- (that would regress --weakness-check's diagnostic surface for a
  -- function whose only weak candidate happens to be excluded) — report it
  -- as unvalidated instead.
  if syntheticName `elem` erBodyFallback emitR
    then pure [mkCandidateUnvalidated (wcFunctionName wc) (wcTrivialLabel wc)]
    else do
      let fqText = erFQText emitR
          fqPath = "/tmp/llmll-weakness-" <> T.unpack (wcFunctionName wc) <> ".fq"
      TIO.writeFile fqPath fqText
      -- Run the solver
      (_, out, err) <- readProcessWithExitCode lfBin [fqPath] ""
      let fqResult = parseFQResult (T.pack out <> T.pack err)
      case fqResult of
        FQSafe -> do
          -- The trivial body satisfies the contracts → spec is weak
          let preText  = fmap (T.pack . show) (wcPrecondition wc)
              postText = fmap (T.pack . show) (wcPostcondition wc)
              diag     = mkSpecWeakness (wcFunctionName wc) (wcTrivialLabel wc) preText postText
          pure [diag]
        _ -> pure []  -- UNSAFE or error → spec is not weak for this body

-- ---------------------------------------------------------------------------
-- v0.3.1: Leanstral proof pipeline
-- ---------------------------------------------------------------------------

-- | Scan statements for ?proof-required holes and run the Leanstral pipeline.
--   Professor flag E1: scan [Statement] directly, not HoleReport.
runLeanstralPipeline :: Bool -> FilePath -> [Statement] -> LeanstralOpts -> IO ()
runLeanstralPipeline json fp stmts lsOpts = do
  let proofHoles = [ (n, c)
                   | SDefLogic n _ _ c (EHole (HProofRequired _ _)) <- stmts
                   ] ++ [ (n, c)
                   | SLetrec n _ _ c _ (EHole (HProofRequired _ _)) <- stmts
                   ] ++ [ (n, c)
                   | SDef n _ _ c (EHole (HProofRequired _ _)) <- stmts
                   ] ++ [ (n, c)
                   | SDefShell n _ _ c (EHole (HProofRequired _ _)) <- stmts
                   ]
  if null proofHoles
    then unless json $ putStrLn "   No proof-required holes found."
    else do
      unless json $ putStrLn $ "   " ++ show (length proofHoles) ++ " proof-required hole(s) found."
      cache <- loadProofCache fp
      let config = if lsMock lsOpts
                     then defaultMCPConfig { mcpMock = True }
                     else defaultMCPConfig
                            { mcpMock = False
                            , mcpCommand = T.pack (fromMaybe "lean-lsp-mcp" (lsCmd lsOpts))
                            , mcpTimeout = lsTimeout lsOpts
                            }
      updatedCache <- foldM (processPH config json) cache proofHoles
      saveProofCache fp updatedCache
      unless json $ putStrLn $ "   .proof-cache.json written to " ++ fp ++ ".proof-cache.json"
  where
    processPH config isJson cache (name, contract) = do
      case translateObligation name contract of
        LeanTheorem thm -> do
          let hash = computeObligationHash thm  -- v0.3.1 Phase F: real SHA-256
          case lookupProof ("/post/" <> name) hash cache of
            Just _ -> do
              unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": cached proof (skip)"
              pure cache
            Nothing -> do
              result <- callLeanstral config thm
              case result of
                ProofFound proof -> do
                  unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": proof found"
                  -- v0.6.3: tag mock proofs correctly (BUG-7)
                  let proverName = if lsMock lsOpts then "mock" else "leanstral"
                      entry = ProofEntry hash proof proverName ""
                  pure (insertProof ("/post/" <> name) entry cache)
                ProofTimeout -> do
                  unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": timeout"
                  pure cache
                ProofError e -> do
                  unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": error: " ++ T.unpack e
                  pure cache
                LeanstralUnavailable e -> do
                  unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": unavailable: " ++ T.unpack e
                  pure cache
        Unsupported reason -> do
          unless isJson $ putStrLn $ "   " ++ T.unpack name ++ ": unsupported (" ++ T.unpack reason ++ ")"
          pure cache

-- ---------------------------------------------------------------------------
-- Phase 2c: typecheck [--sketch]
-- ---------------------------------------------------------------------------

doTypecheck :: Bool -> GrammarMode -> FilePath -> Bool -> IO ()
doTypecheck json gm fp False = doCheck json gm fp False   -- non-sketch: identical to check
doTypecheck json gm fp True  = do
  -- Sketch mode: propagate types into holes
  mResult <- loadStatementsMulti json gm fp
  case mResult of
    Left () -> exitFailure
    Right (ss, cache, _) -> do
      -- Seed env with cross-module names then run sketch inference
      let seededEnv = Map.foldlWithKey' seedModule emptyEnv cache
          result    = runSketch gm seededEnv ss defaultPatterns
      -- encodeSketchResult produces schemaVersion + sorted errors + structured fields
      BLC.putStrLn (encodeSketchResult result)
      exitSuccess
  where
    seedModule acc path menv =
      let prefix    = T.intercalate "." path <> "."
          qualified = Map.mapKeys (prefix <>) (meExports menv)
      in Map.union qualified acc

-- ---------------------------------------------------------------------------
-- v0.3: Checkout handlers
-- ---------------------------------------------------------------------------

-- | Guard: only allow .ast.json / .json files for checkout operations.
guardJsonFile :: FilePath -> IO Bool
guardJsonFile fp = do
  let ext = takeExtension fp
  if ext == ".json"
    then pure True
    else do
      hPutStrLn stderr $ "Error: checkout requires .ast.json input; run 'llmll build --emit json-ast' first"
      hPutStrLn stderr $ "  Got: " ++ fp
      pure False

doCheckout :: Bool -> GrammarMode -> FilePath -> T.Text -> IO ()
doCheckout json gm fp pointer = do
  ok <- guardJsonFile fp
  unless ok exitFailure
  -- Load JSON-AST as raw Value
  raw <- BL.readFile fp
  case A.decode raw of
    Nothing -> do
      hPutStrLn stderr $ "Error: cannot parse " ++ fp ++ " as JSON"
      exitFailure
    Just astVal -> do
      -- v0.10 OBLIG-1: Compute staleness hashes
      sourceHash <- hashFile fp
      let verifiedFp = verifiedPath fp
      verifiedExists <- doesFileExist verifiedFp
      mVerifiedHash <- if verifiedExists
        then Just <$> hashFile verifiedFp
        else pure Nothing
      -- OBLIG-1 (population): assemble the per-hole brief from parse + sketch
      -- type-check. No constraint emission, no solver — checkout stays at
      -- typecheck cost. On parse/load failure we proceed with an empty brief;
      -- checkout still acquires the lock.
      let normPtr = normalizePointer pointer
      (mScope, mTypeDefs, mPre, mPost, mPath, mFuncs, mConsumed, mExpRet) <- do
        mStmts <- loadStatementsMulti json gm fp
        case mStmts of
          Left () -> pure (Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing)
          Right (stmts, _cache, _) -> do
            let sketch = runSketch gm builtinEnv stmts defaultPatterns
                mHole  = case [ h | h <- sketchHoles sketch
                                  , normalizePointer (shPointer h) == normPtr ] of
                           (h:_) -> Just h
                           []    -> Nothing
                scope  = fmap (buildScopeEntries . shEnv) mHole
                -- DEF-RET / OBLIG-1-FOLLOWON: the hole's inferred type (now carrying
                -- the declared return for a bare body hole) → expected_return_type.
                expRet = mHole >>= (inferredTypeLabel . shStatus)
                holeNm = maybe "" shName mHole
                (pre, post, path) = holeContractBrief stmts normPtr holeNm
                tdefs  = case mHole of
                  Nothing -> Nothing
                  Just h  ->
                    let scopeTypes = Map.map sbType (shEnv h)
                        defs = collectTypeDefinitions scopeTypes Nothing
                                 (buildAliasMap stmts)
                    in if null defs then Nothing else Just defs
                -- DEMO-COMP (seam 5): wire the two previously-deferred Nothings.
                -- Checkout stays at typecheck cost (no solver): the trust report
                -- here carries default tiers, sourced honestly via trustLabel.
                trustRpt = buildTrustReport _cache stmts Map.empty
                trustMap = Map.fromList [(teName e, e) | e <- trEntries trustRpt]
                cenv     = buildContractEnv stmts
                recNames = recursiveNames stmts
                -- ccFunctions: contracted user vocabulary with pre/post/tier (§3.2).
                funcs = [ FuncEntry
                            { feName   = fname
                            , feParams = map (\(n,t) -> (n, typeLabel t)) ps
                            , feReturn = maybe "?" typeLabel mRet
                            , feStatus = "filled"
                            , fePre    = fmap exprToSExpr (contractPre c)
                            , fePost   = fmap exprToSExpr (contractPost c)
                            , feTier   = Just (trustLabel trustMap fname)
                            }
                        | stmt <- stmts
                        , Just (fname, ps, mRet, c, _) <- [normalizeDefStmt stmt]
                        , contractPre c /= Nothing || contractPost c /= Nothing
                        ]
                -- ccConsumedGuarantees: discharged callee posts the hole's
                -- enclosing function consumes (§3.1, §5 edge 3 sourcing).
                mEnclosing = enclosingFunc normPtr stmts
                consumed = case mEnclosing of
                  Just fn -> assembleConsumedGuarantees stmts cenv trustMap recNames fn
                  Nothing -> []
            pure ( scope
                 , tdefs
                 , pre
                 , post
                 , if null path then Nothing else Just path
                 , if null funcs then Nothing else Just funcs
                 , if null consumed then Nothing else Just consumed
                 , expRet
                 )
      let ctx = CheckoutContext
            { ccScope          = mScope
            , ccExpectedReturn = mExpRet  -- DEF-RET: hole's inferred/declared return type
            -- DEMO-COMP (seam 5): contracted-user vocabulary with pre/post/tier.
            , ccFunctions      = mFuncs
            , ccTypeDefs       = mTypeDefs
            -- OBLIG-1 (population): contract context now filled (was deferred to OBLIG-2)
            , ccContractPre    = mPre
            , ccPostGoal       = mPost
            , ccPathCondition  = mPath
            , ccAssumptions    = Nothing  -- deferred (follow-on: trust-entry labels)
            , ccObligationId   = Nothing
            -- v0.10: staleness hashes
            , ccSourceHash     = Just sourceHash
            , ccVerifiedHash   = mVerifiedHash
            -- DEMO-COMP (seam 5): consumed callee guarantees.
            , ccConsumedGuarantees = mConsumed
            }
      result <- checkoutHoleWithContext fp astVal pointer ctx
      case result of
        Left diag -> do
          hPutStrLn stderr $ T.unpack (diagMessage diag)
          exitFailure
        Right ct -> do
          BLC.putStrLn (encode ct)
          exitSuccess

doCheckoutRelease :: Bool -> FilePath -> T.Text -> IO ()
doCheckoutRelease _json fp token = do
  ok <- guardJsonFile fp
  unless ok exitFailure
  result <- releaseHole fp token
  case result of
    Left diag -> do
      hPutStrLn stderr $ T.unpack (diagMessage diag)
      exitFailure
    Right () -> do
      BLC.putStrLn (encode (object ["released" .= True]))
      exitSuccess

doCheckoutStatusCmd :: Bool -> FilePath -> T.Text -> IO ()
doCheckoutStatusCmd _json fp token = do
  ok <- guardJsonFile fp
  unless ok exitFailure
  result <- checkoutStatus fp token
  case result of
    Left diag -> do
      hPutStrLn stderr $ T.unpack (diagMessage diag)
      exitFailure
    Right remaining -> do
      BLC.putStrLn (encode (object ["remaining_ttl" .= (round remaining :: Int)]))
      exitSuccess

-- ---------------------------------------------------------------------------
-- v0.3: Patch handler
-- ---------------------------------------------------------------------------

doPatch :: Bool -> GrammarMode -> FilePath -> FilePath -> IO ()
doPatch _json gm fp patchFp = do
  ok <- guardJsonFile fp
  unless ok exitFailure
  -- Read and parse patch request
  patchRaw <- BL.readFile patchFp
  case A.decode patchRaw of
    Nothing -> do
      hPutStrLn stderr $ "Error: cannot parse " ++ patchFp ++ " as JSON"
      exitFailure
    Just patchVal ->
      case parsePatchRequest patchVal of
        Left err -> do
          hPutStrLn stderr $ "Error parsing patch request: " ++ T.unpack err
          exitFailure
        Right pr -> do
          result <- applyPatch gm fp pr
          BLC.putStrLn (encode result)
          case result of
            PatchSuccess _ -> exitSuccess
            _              -> exitFailure

-- ---------------------------------------------------------------------------
-- v0.3: contract extraction helper (used by doVerify)
-- ---------------------------------------------------------------------------

-- | Extract (name, contract) from a statement, if it has one.
extractContract :: Statement -> Maybe (Name, Contract)
extractContract (SDefLogic name _ _ c _)  = Just (name, c)
extractContract (SLetrec name _ _ c _ _)  = Just (name, c)
extractContract (SDef      name _ _ c _)  = Just (name, c)
extractContract (SDefShell name _ _ c _)  = Just (name, c)
extractContract _                         = Nothing

-- ---------------------------------------------------------------------------
-- v0.3.1: event log replay
-- ---------------------------------------------------------------------------

doReplay :: Bool -> GrammarMode -> FilePath -> FilePath -> IO ()
doReplay json gm srcFp logFp = do
  logContents <- TIO.readFile logFp
  let entries = parseEventLog logContents
  if null entries
    then do
      hPutStrLn stderr $ "No events found in " ++ logFp
      exitFailure
    else do
      unless json $
        putStrLn $ "Event log: " ++ show (length entries) ++ " events found in " ++ logFp

      -- Build the program to get an executable
      let modName  = takeBaseName srcFp
          -- BUG-2 (v0.14.3): the executable's on-disk name is the
          -- hpack/Cabal-sanitized name (underscores -> hyphens; see
          -- CodegenHs.sanitizePkgName / emitPackageYaml), not the raw
          -- filename-derived modName. Both must agree or `which` below
          -- looks for a binary that was never built under that name.
          execName = T.unpack (sanitizePkgName (T.pack modName))
          outDir   = "generated/" ++ modName
      unless json $ putStrLn $ "Building " ++ srcFp ++ " ..."
      -- BUG-1 (v0.14.3): doBuild/doBuildFromJson always terminate the whole
      -- process via exitSuccess/exitFailure on every path (see doBuild and
      -- doBuildFromJson below), which previously killed `llmll replay`
      -- outright before it ever reached runReplay. runCapturingExit
      -- (LLMLL.Replay) intercepts that ExitCode instead of letting it
      -- propagate to the RTS, so a successful build lets replay continue
      -- and a failed build still exits with the build's own failure code
      -- (no silent swallow).
      buildCode <- runCapturingExit (doBuild json gm srcFp Nothing False False False ContractsFull)
      case buildCode of
        ExitSuccess       -> pure ()
        code@(ExitFailure _) -> exitWith code

      -- Find the executable (stack build puts it in .stack-work). `cwd` must
      -- point at the generated package's own directory so `stack exec`
      -- resolves the project whose .stack-work actually has the binary.
      let execFinder = (proc "stack" ["exec", "which", execName])
                        { std_out = CreatePipe, cwd = Just outDir }
      (_, Just hexec, _, ph) <- createProcess execFinder
      execPath <- hGetLine hexec
      _ <- waitForProcess ph

      if null execPath
        then do
          hPutStrLn stderr $ "Could not find executable for " ++ execName
          exitFailure
        else do
          unless json $ putStrLn $ "Running replay against " ++ execPath ++ " ..."
          result <- runReplay execPath entries
          putStrLn $ show (replayMatched result) ++ "/" ++ show (replayTotal result) ++ " events matched"
          forM_ (replayDiverged result) $ \(sq, expected, actual) ->
            putStrLn $ "  DIVERGE seq " ++ show sq
                    ++ ": expected=\"" ++ T.unpack expected
                    ++ "\" actual=\"" ++ T.unpack actual ++ "\""
          when (replayMatched result /= replayTotal result) exitFailure

-- ---------------------------------------------------------------------------
-- spec (v0.3.4)
-- ---------------------------------------------------------------------------

doSpec :: Bool -> IO ()
doSpec jsonOut =
  if jsonOut
    then TIO.putStr agentSpecJSON
    else TIO.putStr agentSpecText

-- ---------------------------------------------------------------------------
-- version
-- ---------------------------------------------------------------------------

doVersion :: Bool -> IO ()
doVersion json =
  if json
    then TIO.putStrLn . T.pack . BLC.unpack . encode $
           object ["version" .= showVersion version]
    else TIO.putStrLn $ T.pack ("llmll " ++ showVersion version)

-- ===========================================================================
-- PROOF-ARTIFACT (staged MVP) — assembly, solver-meta capture, fail-closed replay
-- ===========================================================================

-- | "sha256:" hash of the source file bytes (recomputable at replay).
sourceHashOf :: FilePath -> IO T.Text
sourceHashOf fpath = do
  bytes <- PABS.readFile fpath
  let hex = T.pack $ concatMap (\b -> let h = showHex b "" in if length h == 1 then '0':h else h)
                               (PABS.unpack (PASHA.hash bytes))
  pure ("sha256:" <> hex)

-- | Pin the determinism inputs (§4.3): fixpoint + z3 versions and the option set.
captureSolverMeta :: FilePath -> IO SolverMeta
captureSolverMeta lfBin = do
  fpv <- probe lfBin ["--numeric-version"]
  z3v <- do mz3 <- findExecutable "z3"
            maybe (pure "unavailable") (\z3 -> probe z3 ["--version"]) mz3
  pure SolverMeta { smFixpointVersion = fpv, smZ3Version = z3v
                  , smOptions = ["-q", "--json"], smResourceLimits = Nothing }
  where
    probe bin args = do (_c, o, _e) <- readProcessWithExitCode bin args ""
                        pure (T.strip (T.pack o))

fqToSolverResult :: FQVerifyResult -> SolverResult
fqToSolverResult FQSafe       = RSafe
fqToSolverResult (FQUnsafe _) = RUnsafeRefuted
fqToSolverResult (FQError _)  = RNoVC

-- | Re-project the trust report into the artifact, minting every per-function
-- record through the §4.1 kernel. A refuted body VC is pre-demoted off the positive
-- axis (it did not verify); the kernel still guards the deserialization path.
buildProofArtifact :: FilePath -> T.Text -> SolverMeta -> FQVerifyResult -> EmitResult -> TrustReport
                   -> Either LaunderError ProofArtifact
buildProofArtifact srcPath srcHash meta fqResult emitR trust = do
  fns <- mapM (mkFnRecord . entryToInputs) (trEntries trust)
  pure ProofArtifact
    { paVersion       = proofArtifactVersion
    , paComposed      = ComposedVersions { cvTrustReport = "1.4.0", cvSchema = "0.7.0" }
    , paSourcePath    = T.pack srcPath
    , paSourceHash    = Just srcHash
    , paSolver        = meta
    , paCodegenSemVer = codegenSemanticsVersion
    , paSolverResult  = fqToSolverResult fqResult
    , paVc            = erFQText emitR
    , paUnsatCore     = Nothing
    , paFunctions     = fns
    , paCertificate   = Nothing
    }
  where
    fallbackSet     = Set.fromList (erBodyFallback emitR)
    bodyFaithfulSet = Set.fromList (erBodyFaithfulFns emitR)
    -- This run's evidence drives the tier (the sidecar may be stale/absent on a
    -- first verify): a body-faithful fn whose VC was not refuted IS verified
    -- (refutedSet = body-faithful fns the solver reported UNSAFE), so
    -- body-faithful \ refuted = body-faithful fns proven SAFE.
    entryToInputs te =
      let refuted = teName te `Set.member` trRefutedFns trust
          tier | refuted                                = TAsserted
               | teName te `Set.member` bodyFaithfulSet = TVerified
               | otherwise                              = tierOf (teEffectivePostLevel te)
      in FnInputs
           { fiName           = teName te
           , fiTier           = tier
           , fiCallerObligs   = map coObRequires (teCallerObligations te)
           , fiFallbackReason = if teName te `Set.member` fallbackSet
                                  then Just "left the body-faithful fragment (§5.3.3 firewall)"
                                  else Nothing
           , fiRefuted        = refuted
           , fiDiscrim        = Nothing
           }
    tierOf Nothing                      = TNoContract
    tierOf (Just (DLVerified _))        = TVerified
    tierOf (Just (DLContractChecked _)) = TContractChecked
    tierOf (Just (DLTested _))          = TTested
    tierOf (Just DLAsserted)            = TAsserted

-- | Re-derive + check a recorded artifact, fail-closed (§4.3).
doReplayArtifact :: Bool -> FilePath -> IO ()
doReplayArtifact _json artFp = do
  exists <- doesFileExist artFp
  if not exists
    then TIO.putStrLn ("ERROR: artifact not found: " <> T.pack artFp) >> exitWith (ExitFailure 2)
    else do
      raw <- BL.readFile artFp
      case A.eitherDecode raw :: Either String ProofArtifact of
        Left e -> do
          TIO.putStrLn ("ERROR: proof-artifact rejected (parse / §4.1 invariant): " <> T.pack e)
          exitWith (ExitFailure 2)
        Right art -> do
          srcExists  <- doesFileExist (T.unpack (paSourcePath art))
          recomputed <- if srcExists then Just <$> sourceHashOf (T.unpack (paSourcePath art)) else pure Nothing
          mLF <- do a <- findExecutable "liquid-fixpoint"
                    maybe (findExecutable "fixpoint") (pure . Just) a
          case mLF of
            Nothing -> TIO.putStrLn "ERROR: liquid-fixpoint not on PATH — cannot replay" >> exitWith (ExitFailure 3)
            Just lfBin -> do
              meta <- captureSolverMeta lfBin
              let tmp = "/tmp/llmll-replay-artifact.fq"
              TIO.writeFile tmp (paVc art)
              (_c, o, err) <- readProcessWithExitCode lfBin ["-q", "--json", tmp] ""
              let merged = T.pack o <> T.pack err
                  rerun  = fqToSolverResult (fromMaybe (parseFQResult merged) (parseFQResultJSON merged))
              case classifyReplay recomputed meta rerun art of
                ReplayReproduced r ->
                  TIO.putStrLn ("\x2705 replay reproduced verdict: " <> T.pack (show r)) >> exitSuccess
                ReplayFailClosed reason ->
                  TIO.putStrLn ("\x26d4 replay FAILED CLOSED: " <> reason) >> exitWith (ExitFailure 1)
