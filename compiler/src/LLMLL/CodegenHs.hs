{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.CodegenHs
-- Description : Transpile LLMLL AST to Haskell source code (v0.1.2+).
--
-- Replaces the v0.1.1 Rust/LlmllVal emitter in 'LLMLL.Codegen'.
--
-- Generated layout (v0.1.2 — single-module):
--
-- @
--   \<outDir\>/
--     src/
--       Lib.hs       ← all def-logic, types, interfaces, §13 stdlib preamble
--       Main.hs      ← def-main harness (only if SDefMain present)
--       FFI/\<X\>.hs  ← foreign import ccall stubs for c.* imports
--     package.yaml   ← hpack descriptor
-- @
--
-- The multi-module split (Logic.hs, Types.hs, Interfaces.hs, Capabilities.hs)
-- is deferred to v0.2 alongside the module system. See docs/compiler-team-roadmap.md.
module LLMLL.CodegenHs
  ( -- * Entry point
    generateHaskell
  , generateHaskellMulti   -- ^ P3: multi-file entry point
    -- * Result
  , CodegenResult(..)
    -- * Import classification (re-exported for Main.hs)
  , ImportKind(..)
  , classifyImport
    -- * Internals (exported for test coverage)
  , emitExpr
  , emitLit
  , emitApp
  , toHsType
  , mapLlmllPrimType
  , runtimePreamble
  , emitHole
    -- * Event Log (v0.3.1)
  , emitEventLogPreamble
    -- * Package-name sanitization (BUG-2, v0.14.3 — shared with Main.hs so the
    -- generated executable's on-disk name always matches package.yaml)
  , sanitizePkgName
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (nub, intercalate)
import Data.Maybe (catMaybes, isJust)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------------

data CodegenResult = CodegenResult
  { cgHsSource    :: Text            -- ^ src/Lib.hs
  , cgMainHs      :: Maybe Text      -- ^ src/Main.hs (if SDefMain present)
  , cgPackageYaml :: Text            -- ^ package.yaml
  , cgStackYaml   :: Text            -- ^ stack.yaml (resolver pin)
  , cgFfiModHs    :: Maybe Text      -- ^ src/FFI.hs re-export hub (if c.* present)
  , cgFfiFiles    :: [(Text, Text)]  -- ^ [(ModuleName, src/FFI/Name.hs)]
  , cgModuleName  :: Text
  , cgWarnings    :: [Text]
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Import classification
-- ---------------------------------------------------------------------------

data ImportKind
  = HackageImport Text   -- ^ haskell.<pkg> → import Data.<Pkg>
  | CLibImport    Text   -- ^ c.<lib>       → foreign import ccall stubs
  | WasiImport           -- ^ wasi.*        → stdlib preamble handles it
  | UnknownImport
  deriving (Show, Eq)

classifyImport :: Import -> ImportKind
classifyImport imp
  | "haskell." `T.isPrefixOf` path = HackageImport (T.drop 8 path)
  | "c."       `T.isPrefixOf` path = CLibImport    (T.drop 2 path)
  | "wasi."    `T.isPrefixOf` path = WasiImport
  | otherwise                      = UnknownImport
  where path = importPath imp

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

generateHaskell :: Text -> [Statement] -> CodegenResult
generateHaskell modName stmts =
  let imports   = [imp | SImport imp <- stmts]
      hackageMs = nub [pkg | imp <- imports, HackageImport pkg <- [classifyImport imp]]
      cLibs     = nub [lib | imp <- imports, CLibImport lib   <- [classifyImport imp]]
      hasFfi    = not (null cLibs)
      hasMain   = any isDefMain stmts

      libHs     = emitLibHs modName hackageMs stmts
      mainHs    = if hasMain then Just (emitMainHs modName stmts) else Nothing
      pkgYaml   = emitPackageYaml modName hasMain hackageMs
      ffiMod    = if hasFfi then Just (emitFfiModHs cLibs) else Nothing
      ffiFiles  = [(toHsModName lib, emitFfiStub lib imports) | lib <- cLibs]
      warnings  = concatMap stmtWarnings stmts
  in CodegenResult
       { cgHsSource    = libHs
       , cgMainHs      = mainHs
       , cgPackageYaml = pkgYaml
       , cgStackYaml   = emitStackYaml
       , cgFfiModHs    = ffiMod
       , cgFfiFiles    = ffiFiles
       , cgModuleName  = modName
       , cgWarnings    = warnings
       }

-- | P3: Multi-file entry point.
-- Takes the topologically-ordered list of imported ModuleEnvs (dependencies first,
-- produced by topoSortedEnvs in Module.hs) and the entry-point statement list.
-- Concatenates all imported module statements before the entry-point statements
-- so the generated Lib.hs contains the full transitive closure of definitions.
generateHaskellMulti :: Text -> [ModuleEnv] -> [Statement] -> CodegenResult
generateHaskellMulti modName importedEnvs entryStmts =
  -- importedEnvs are already in post-order (deps before dependents).
  -- De-duplicate SImport nodes: the consolidated stmts list needs imports
  -- from all modules for hackage/c-lib header generation, but duplicate
  -- SImport nodes are harmless since emitStmt produces "" for them.
  let allStmts = concatMap meStatements importedEnvs ++ entryStmts
  in generateHaskell modName allStmts


isDefMain :: Statement -> Bool
isDefMain SDefMain{} = True
isDefMain _          = False

-- ---------------------------------------------------------------------------
-- src/Lib.hs
-- ---------------------------------------------------------------------------


-- | Compute a Prelude hiding clause for any LLMLL type names that clash with Prelude exports.
preludeClashes :: [Text]
preludeClashes = ["Word", "Map"]  -- extend if needed

preludeHiding :: Text
preludeHiding
  | null preludeClashes = "import Prelude"
  | otherwise = "import Prelude hiding (" <> T.intercalate ", " preludeClashes <> ")"

emitLibHs :: Text -> [Text] -> [Statement] -> Text
emitLibHs _modName hackagePkgs stmts = T.unlines $
  [ "{-# LANGUAGE ScopedTypeVariables #-}"
  , "{-# OPTIONS_GHC -Wno-overlapping-patterns #-}"  -- suppress spurious warnings from generated catch-all arms
  , "-- Generated by LLMLL compiler v0.1.3 (Haskell backend)"
  , "-- DO NOT EDIT — regenerate with `llmll build`"
  , "module Lib where"
  , ""
  , preludeHiding
  ] ++
  -- Hackage imports from haskell.* declarations
  map hackageImportLine hackagePkgs ++
  -- `sort` normalises wasi_fs_list's output. listDirectory's order is
  -- filesystem-dependent, so without it the same program on the same inputs
  -- produces a different event log on a different machine and `llmll replay`
  -- reports divergence the program did not cause.
  [ "import Data.List (isPrefixOf, intercalate, nub, sort)"
  , "import Data.Char (ord, chr)"
  , "import qualified Data.Map.Strict as Map"
  -- FS-ENCODING-1: hSetEncoding + utf8 + hGetContents pin the fs text bodies to
  -- UTF-8 instead of the ambient locale. Measured: under a POSIX locale a READ
  -- of a valid UTF-8 file fails on the lead byte (0xC2 for U+00A7) and a WRITE
  -- of any non-ASCII string fails to encode, both surfacing as a spurious RErr
  -- on input the program was right about.
  , "import System.IO (hPutStr, hPutStrLn, stderr, openFile, hClose, IOMode(..)"
  , "                 , hSetEncoding, utf8, hGetContents)"
  , "import Test.QuickCheck (quickCheck, property)"
  , "import qualified Control.Concurrent.Async as Async"
  , "import Control.Exception (try, evaluate, onException, SomeException, IOException, bracket)"
  -- EFFECT-RESP: the response slot is an IORef built once at load time with
  -- unsafePerformIO (already imported below for regex-match).
  , "import Data.IORef (IORef, newIORef, readIORef, writeIORef)"
  -- WASI-RT: wasi_fs_delete's totality guard needs doesFileExist/removeFile,
  -- and `when` to make the guard a no-op rather than an exception on a
  -- missing path. `evaluate` (above) is what keeps wasi_fs_read from being
  -- a lazy no-op; it was already in scope.
  -- listDirectory, not getDirectoryContents: it already omits "." and "..",
  -- so the exclusion is a property of the primitive rather than a filter that
  -- would need its own test.
  , "import System.Directory (doesFileExist, removeFile, listDirectory, createDirectoryIfMissing, copyFile)"
  , "import Control.Monad (when)"
  , "import Data.Bits (xor)"
  , "import Data.Word (Word8)"
  , "import Text.Regex.TDFA ((=~))"
  , "import System.IO.Unsafe (unsafePerformIO)"
  -- CAP-PROC Phase 2. All four bodies are unconditional, so runtimePreamble
  -- stays a top-level CAF and the WASI-RT completeness guard in Spec.hs can
  -- keep folding over it without knowing the program's import set. The cost is
  -- three package.yaml entries (process, cryptohash-sha256, bytestring), all
  -- three already compiler dependencies, so the LTS snapshot is cached and the
  -- generated-project closure moves 31 -> 33 packages (measured, lts-22.43).
  , "import qualified System.Process as P"
  , "import System.Exit (ExitCode(..))"
  -- PROC-BOUNDARY-1: wasi_proc_args's body. Unconditional like the CAP-PROC
  -- Phase 2 bodies above, so runtimePreamble stays a top-level CAF the WASI-RT
  -- completeness fold can walk without knowing the program's import set. base
  -- only; no package.yaml entry is owed and the generated closure does not move.
  , "import System.Environment (getArgs)"
  , "import System.Timeout (timeout)"
  , "import GHC.Clock (getMonotonicTimeNSec)"
  , "import qualified Data.ByteString as BS"
  , "import qualified Crypto.Hash.SHA256 as SHA256"
  , "import Numeric (showHex)"
  , ""
  , "-- ---------------------------------------------------------------------------"
  , "-- §13 Runtime Preamble — always in scope"
  , "-- ---------------------------------------------------------------------------"
  , ""
  ] ++
  runtimePreamble ++
  [ ""
  , "-- ---------------------------------------------------------------------------"
  , "-- Program"
  , "-- ---------------------------------------------------------------------------"
  , ""
  ] ++
  map emitStmt (filter (not . isDefMain) stmts)

-- | Map haskell.<pkg> short names to their actual Haskell module paths.
-- Unknown packages fall back to capitalize-and-join.
hackageModuleMap :: Map Text Text
hackageModuleMap = Map.fromList
  [ ("aeson",       "Data.Aeson")
  , ("text",        "Data.Text")
  , ("bytestring",  "Data.ByteString")
  , ("containers",  "Data.Map.Strict")
  , ("vector",      "Data.Vector")
  , ("time",        "Data.Time")
  , ("directory",   "System.Directory")
  , ("filepath",    "System.FilePath")
  , ("process",     "System.Process")
  ]

hackageImportLine :: Text -> Text
hackageImportLine pkg =
  case Map.lookup pkg hackageModuleMap of
    Just modPath -> "import " <> modPath
    Nothing      -> "import " <> pkgToModule pkg  -- fallback: capitalize segments
  where
    pkgToModule p = T.intercalate "." (map capitalise (T.splitOn "." p))
    capitalise t  = case T.uncons t of
      Nothing     -> t
      Just (c,rest) -> T.singleton (toUpper c) <> rest
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise             = c

-- ---------------------------------------------------------------------------
-- §13 Runtime Preamble
-- ---------------------------------------------------------------------------

runtimePreamble :: [Text]
runtimePreamble =
  [ "-- §13.4 Pair"
  , "llmll_pair :: a -> b -> (a, b)"
  , "llmll_pair a b = (a, b)"
  , ""
  , "-- §13.5 List"
  , "list_empty :: [a]"
  , "list_empty = []"
  , ""
  , "list_append :: [a] -> a -> [a]"
  , "list_append xs x = xs ++ [x]"
  , ""
  , "list_prepend :: a -> [a] -> [a]"
  , "list_prepend = (:)"
  , ""
  , "list_contains :: Eq a => [a] -> a -> Bool"
  , "list_contains = flip elem"
  , ""
  , "list_length :: [a] -> Int"
  , "list_length = length"
  , ""
  , "list_head :: [a] -> Either String a"
  , "list_head []    = Left \"list_head: empty list\""
  , "list_head (x:_) = Right x"
  , ""
  , "list_tail :: [a] -> Either String [a]"
  , "list_tail []     = Left \"list_tail: empty list\""
  , "list_tail (_:xs) = Right xs"
  , ""
  , "list_map :: [a] -> (a -> b) -> [b]"
  , "list_map = flip map"
  , ""
  , "list_filter :: [a] -> (a -> Bool) -> [a]"
  , "list_filter = flip filter"
  , ""
  , "list_fold :: [a] -> b -> (b -> a -> b) -> b"
  , "list_fold xs acc f = foldl f acc xs"
  , ""
  , "list_nth :: [a] -> Int -> Either String a"
  , "list_nth xs i"
  , "  | i < 0 || i >= length xs = Left (\"list_nth: index \" ++ show i ++ \" out of range\")"
  , "  | otherwise               = Right (xs !! i)"
  , ""
  , "range :: Integer -> Integer -> [Integer]"  -- LT-INT (v0.11): Class B value-shape
  , "range from to = [from .. to - 1]"
  , ""
  , "-- §13.12 Bytes / map operations (Lever A stage A0)."
  , "-- Builtin contracts fire here as runtime assertions (the §5.3.4 backstop);"
  , "-- verify-time discharge of the same obligations is stage A1/A2."
  , "bytes_length :: [Word8] -> Int"
  , "bytes_length = length"
  , ""
  , "bytes_get :: [Word8] -> Int -> Integer"
  , "bytes_get b i"
  , "  | i < 0 || i >= length b = error (\"bytes-get: pre-condition failed: index \" ++ show i ++ \" out of bounds for bytes[\" ++ show (length b) ++ \"]\")"
  , "  | otherwise              = fromIntegral (b !! i)"
  , ""
  , "bytes_set :: [Word8] -> Int -> Integer -> [Word8]"
  , "bytes_set b i v"
  , "  | i < 0 || i >= length b = error (\"bytes-set: pre-condition failed: index \" ++ show i ++ \" out of bounds for bytes[\" ++ show (length b) ++ \"]\")"
  , "  | v < 0 || v > 255       = error (\"bytes-set: pre-condition failed: value \" ++ show v ++ \" outside byte range 0..255\")"
  , "  | otherwise              = take i b ++ [fromIntegral v] ++ drop (i + 1) b"
  , ""
  , "bytes_zero :: Int -> [Word8]"
  , "bytes_zero n = replicate n 0"
  , ""
  , "map_has :: Ord k => Map.Map k v -> k -> Bool"
  , "map_has m k = Map.member k m"
  , ""
  , "map_get :: (Ord k, Show k) => Map.Map k v -> k -> v"
  , "map_get m k = case Map.lookup k m of"
  , "  Just v  -> v"
  , "  Nothing -> error (\"map-get: pre-condition failed: key \" ++ show k ++ \" not present (map-has is the required pre)\")"
  , ""
  , "map_put :: Ord k => Map.Map k v -> k -> v -> Map.Map k v"
  , "map_put m k v = Map.insert k v m"
  , ""
  , "map_empty :: Map.Map k v"
  , "map_empty = Map.empty"
  , ""
  , "-- §13.6 String"
  , "string_length :: String -> Int"
  , "string_length = length"
  , ""
  , "string_contains :: String -> String -> Bool"
  , "string_contains haystack needle = any (needle `isPrefixOf`) (tails haystack)"
  , "  where tails [] = [[]]; tails s@(_:xs) = s : tails xs"
  , ""
  , "string_concat :: String -> String -> String"
  , "string_concat = (++)"
  , ""
  , "string_slice :: String -> Int -> Int -> String"
  , "string_slice s from to = take (to - from) (drop from s)"
  , ""
  , "string_char_at :: String -> Int -> String"
  , "string_char_at s i = if i >= 0 && i < length s then [s !! i] else \"\""
  , ""
  , "string_split :: String -> String -> [String]"
  , "string_split _   []  = [\"\"]"
  , "string_split sep str = go str"
  , "  where"
  , "    go [] = [\"\"]"
  , "    go s"
  , "      | sep `isPrefixOf` s = \"\" : go (drop (length sep) s)"
  , "      | otherwise          = let (w:ws) = go (tail s) in (head s : w) : ws"
  , ""
  , "string_trim :: String -> String"
  , "string_trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace"
  , "  where isSpace c = c `elem` (\" \\t\\n\\r\" :: String)"
  , ""
  , "string_concat_many :: [String] -> String"
  , "string_concat_many = concat"
  , ""
  , "string_empty' :: String -> Bool"
  , "string_empty' s = null s"
  , ""
  , "-- | PREAMBLE COMPROMISE (v0.7): unsafePerformIO preserves the pure type"
  , "-- String -> String -> Bool while catching invalid regex patterns at runtime."
  , "-- Do NOT remove the try/evaluate wrapper — it prevents partiality."
  , "regex_match :: String -> String -> Bool"
  , "regex_match pattern subject ="
  , "  case unsafePerformIO (try (evaluate (subject =~ pattern :: Bool)) :: IO (Either SomeException Bool)) of"
  , "    Right b -> b"
  , "    Left _  -> False"
  , ""
  , "-- §13.7 Numeric (LT-INT v0.11: Class B — mathematical-integer semantics)"
  , "int_to_string :: Integer -> String"
  , "int_to_string = show"
  , ""
  , "string_to_int :: String -> Either String Integer"
  , "string_to_int s = case reads s of"
  , "  [(n, \"\")] -> Right n"
  , "  _         -> Left (\"string_to_int: cannot parse '\" ++ s ++ \"'\")"
  , ""
  , "llmll_abs :: Integer -> Integer"
  , "llmll_abs = abs"
  , ""
  , "llmll_min :: Integer -> Integer -> Integer"
  , "llmll_min = min"
  , ""
  , "llmll_max :: Integer -> Integer -> Integer"
  , "llmll_max = max"
  , ""
  , "-- §13.8 Result helpers"
  , "llmll_ok :: a -> Either e a"
  , "llmll_ok = Right"
  , ""
  , "llmll_err :: e -> Either e a"
  , "llmll_err = Left"
  , ""
  , "-- Short aliases used by codegen"
  , "ok :: a -> Either e a"
  , "ok = Right"
  , ""
  , "err :: e -> Either e a"
  , "err = Left"
  , ""
  , "is_ok :: Either e a -> Bool"
  , "is_ok (Right _) = True"
  , "is_ok _         = False"
  , ""
  , "llmll_unwrap :: Either String a -> a"
  , "llmll_unwrap (Right v) = v"
  , "llmll_unwrap (Left e)  = error (\"unwrap: \" ++ e)"
  , ""
  , "-- B2 fix: codegen emits bare 'unwrap'; provide alias for call-site compatibility."
  , "unwrap :: Either String a -> a"
  , "unwrap = llmll_unwrap"
  , ""
  , "unwrap_or :: Either e a -> a -> a"
  , "unwrap_or (Right v) _ = v"
  , "unwrap_or _         d = d"
  , ""
  -- EFFECT-RESP (RC-1): the response channel.
  --
  -- Command is `IO ()` and carries no result, so `perform cmd` cannot return a
  -- payload through the type. The response travels in a slot the command
  -- writes and the harness reads.
  --
  -- The rejected alternative was to source the payload from the harness's
  -- existing stdout capture (captureStdout, emitEventLogPreamble below). That
  -- makes wasi.io.stdout and wasi.fs.read INDISTINGUISHABLE in the channel: a
  -- program receiving `RText s` could not tell whether s came from a file or
  -- from its own print, and the program's console output would be swallowed
  -- into the response value. The response must be produced by performing the
  -- command while knowing WHICH command was performed.
  --
  -- RC-2 (seq-commands is discard-left) needs no code: seq_commands a b = a >> b
  -- already leaves b's slot write as the last one, so the composite yields b's
  -- response and drops a's.
  --
  -- SINGLE-THREADED. One global slot is correct because the console harness is
  -- a straight-line loop (emitMainBody below) that performs one command at a
  -- time. It does not survive concurrency, and :mode http would need a
  -- per-request slot. That mode does not run today, so there is no witness;
  -- whoever wires warp needs to read this paragraph first.
  , "data Response"
  , "  = RNone"
  , "  | RText String"
  , "  | RCode Integer"
  , "  | RErr String"
  , "  | RList [String]"
  , "  deriving (Eq, Show)"
  , ""
  , "{-# NOINLINE llmll_response_slot #-}"
  , "llmll_response_slot :: IORef Response"
  , "llmll_response_slot = unsafePerformIO (newIORef RNone)"
  , ""
  -- Clears the slot BEFORE performing. Every Command bottoms out in a wasi.*
  -- builtin and every builtin below writes the slot, so no stale value can be
  -- re-delivered today; the clear is what keeps that from depending on the
  -- builtin set staying complete.
  , "llmll_reset_response :: IO ()"
  , "llmll_reset_response = writeIORef llmll_response_slot RNone"
  , ""
  , "llmll_perform :: IO () -> IO Response"
  , "llmll_perform cmd = do"
  , "  llmll_reset_response"
  , "  cmd"
  , "  readIORef llmll_response_slot"
  , ""
  -- An effect failure must arrive as a VALUE, not an exception: that is what
  -- preserves "logic functions cannot crash from IO" (LLMLL.md:1747) once a
  -- program can observe its own effects.
  , "llmll_publish :: Response -> IO ()"
  , "llmll_publish = writeIORef llmll_response_slot"
  , ""
  , "llmll_publish_io :: IO Response -> IO ()"
  , "llmll_publish_io act = do"
  , "  r <- try act"
  , "  llmll_publish (either (\\e -> RErr (show (e :: IOException))) id r)"
  , ""
  , "-- §13.9 WASI command constructors (IO actions for v0.1.2)"
  -- stdout/stderr publish RNone and do NOT catch. The console harness's own
  -- output channel failing is harness breakage, and turning it into a program-
  -- visible RErr would let a program read a broken harness as a failed effect
  -- of its own. Deliberate asymmetry with the fs/http bodies below.
  , "wasi_io_stdout :: String -> IO ()"
  , "wasi_io_stdout s = putStr s >> llmll_publish RNone"
  , ""
  , "wasi_io_stderr :: String -> IO ()"
  , "wasi_io_stderr s = hPutStr stderr s >> llmll_publish RNone"
  , ""
  , "{-# SPECIALIZE wasi_http_response :: Integer -> String -> IO () #-}"
  , "wasi_http_response :: Integral i => i -> String -> IO ()"
  , "wasi_http_response code body = do"
  , "  putStrLn (show (fromIntegral code :: Integer) ++ \" \" ++ body)"
  , "  llmll_publish (RCode (fromIntegral code))"
  , ""
  -- WASI-RT: builtinEnv (TypeCheck.hs:154-160) declares seven wasi.* names;
  -- only the three above had definitions, so a program calling any of the four
  -- below type-checked clean and died at GHC with "Variable not in scope".
  -- Keep this block in sync with the builtinEnv list: the Spec.hs describe
  -- block "codegen: wasi preamble completeness" iterates the wasi. prefix of
  -- builtinEnv and fails if any declared name has no definition here.
  -- FS-ENCODING-1. writeFile encodes through the ambient locale, so a string
  -- carrying any character outside it fails with "cannot encode character",
  -- caught by llmll_publish_io and surfaced as RErr. That is a spurious failure
  -- on a string the program constructed legitimately, and it makes the same
  -- program succeed or fail depending on the shell that launched it. UTF-8 is
  -- pinned so the byte image of a write is a property of the program.
  --
  -- This is a real behaviour change for a non-UTF-8 locale that could encode
  -- the string: those writes previously produced locale bytes and now produce
  -- UTF-8. Under a POSIX locale they failed outright, so nothing that worked
  -- stops working; what changes is which bytes land for latin1-style locales.
  , "wasi_fs_write :: String -> String -> IO ()"
  , "wasi_fs_write path contents = llmll_publish_io $"
  , "  bracket (openFile path WriteMode) hClose $ \\h -> do"
  , "    hSetEncoding h utf8"
  , "    hPutStr h contents"
  , "    return RNone"
  , ""
  -- FS-COPY-1. copyFile moves BYTES and never decodes, which is the whole
  -- point: read-then-write cannot express a copy of a binary artifact, because
  -- wasi.fs.read of one yields RErr under any encoding, UTF-8 included. Measured
  -- against a file carrying byte 0xFF. driver-spec section 8:336-337 requires
  -- that where an agent needs a copy of the subject to check its own work, the
  -- copy be the ORIGINAL, UNMODIFIED subject, so a lossy text round trip fails
  -- a MUST rather than merely being inconvenient.
  --
  -- Overwrites an existing destination and raises on a missing source
  -- directory, both inherited from copyFile and both surfacing as RErr through
  -- llmll_publish_io. The overwrite behaviour matches wasi_fs_write above
  -- rather than introducing a second convention.
  , "wasi_fs_copy :: String -> String -> IO ()"
  , "wasi_fs_copy src dst = llmll_publish_io (copyFile src dst >> return RNone)"
  , ""
  -- Idempotent by design. removeFile on a missing path throws, and an uncaught
  -- exception inside a Command breaks the no-crash property LLMLL.md:1747
  -- relies on. The doesFileExist guard is TOCTOU-racy under concurrency; the
  -- console harness is a single-threaded loop (see emitMainBody below), so no
  -- witness exists in this backend. Recorded, not paid for.
  , "wasi_fs_delete :: String -> IO ()"
  , "wasi_fs_delete path = llmll_publish_io $ do"
  , "  exists <- doesFileExist path"
  , "  when exists (removeFile path)"
  , "  return RNone"
  , ""
  -- EFFECT-RESP (RC-1): this is the command the response channel exists for.
  -- WASI-RT's stopgap body performed the read and discarded the contents,
  -- because Command is IO () and there was no channel to return them on. Now
  -- there is: the contents are published as RText and an IO failure as RErr.
  --
  -- `evaluate` is not decoration, and under FS-ENCODING-1 it guards TWO
  -- distinct failures rather than one.
  --
  -- (1) The original reason: hGetContents is lazy, so a body that does not
  -- force the string performs no read at all. It compiles, runs, raises nothing
  -- on an unreadable path, and passes every string-shape test. Unforced, the
  -- thunk escapes into the response slot and is forced later, OUTSIDE the try,
  -- where a decode failure becomes a crash instead of an RErr.
  --
  -- (2) New with the bracket: hClose runs on the way out. If the force moves
  -- outside the bracket the handle is already closed when the string is
  -- demanded, and the read yields TRUNCATED OR EMPTY contents with no error at
  -- all. That failure publishes a well-formed RText and is invisible to any
  -- test that only checks the arm, which is why Spec.hs pins a read larger than
  -- one buffer rather than only a short one.
  --
  -- FS-ENCODING-1: hSetEncoding pins UTF-8. Measured, a POSIX-locale read of a
  -- valid UTF-8 file fails on the lead byte (0xC2 for U+00A7). A file that is
  -- genuinely not UTF-8 still yields RErr, and that is correct: bytes that are
  -- not text do not belong on the text channel. wasi.fs.sha256 (below) and
  -- wasi.fs.copy are the byte-level paths.
  , "wasi_fs_read :: String -> IO ()"
  , "wasi_fs_read path = llmll_publish_io $"
  , "  bracket (openFile path ReadMode) hClose $ \\h -> do"
  , "    hSetEncoding h utf8"
  , "    contents <- hGetContents h"
  , "    _ <- evaluate (length contents)"
  , "    return (RText contents)"
  , ""
  -- CAP-PROC, first operation. The `sort` is not cosmetic: listDirectory's
  -- order is filesystem-dependent, and an unsorted listing makes the event log
  -- machine-dependent for identical inputs, which `llmll replay` reads as
  -- divergence. listDirectory already omits "." and "..".
  --
  -- An empty directory yields `RList []`, NOT RNone. The distinction matters:
  -- RNone is what llmll_reset_response leaves in the slot, so collapsing them
  -- would make a successful empty listing indistinguishable from a command that
  -- published nothing.
  , "wasi_fs_list :: String -> IO ()"
  , "wasi_fs_list path = llmll_publish_io $ do"
  , "  entries <- listDirectory path"
  , "  _ <- evaluate (length entries)"
  , "  return (RList (sort entries))"
  , ""
  -- CAP-PROC Phase 2 ------------------------------------------------------
  --
  -- `True` creates parents, and the operation is idempotent on an existing
  -- directory. Both matter: the driver calls mkdir on stage directories that
  -- may already exist from a resumed run, and an exception there would break
  -- the no-crash property LLMLL.md:1747 relies on.
  , "wasi_fs_mkdir :: String -> IO ()"
  , "wasi_fs_mkdir path ="
  , "  llmll_publish_io (createDirectoryIfMissing True path >> return RNone)"
  , ""
  -- PROC-BOUNDARY-1 half one. The argument vector, on the EXISTING RList arm.
  --
  -- getArgs, so argv[0] IS EXCLUDED. That is the vector a program reasons about
  -- -- its flags -- and it is what ModeCli's harness has always passed to :step
  -- (`args <- getArgs` in emitMainBody below). Publishing argv[0] here would
  -- make the two entry modes disagree about what "the arguments" means, and the
  -- executable's own path is a fact about how the process was launched rather
  -- than about what it was asked to do.
  --
  -- `evaluate (length as)` for the wasi_fs_list reason: forcing inside
  -- llmll_publish_io keeps any failure a VALUE (RErr) rather than a thunk the
  -- PROGRAM forces later, where the exception becomes a crash instead of the
  -- arm the channel promises. getArgs does not realistically throw; the force
  -- costs one traversal of a list that is empty in most runs and keeps the body
  -- structurally identical to its siblings rather than a special case a later
  -- edit can get wrong.
  --
  -- The empty vector publishes `RList []`, NOT RNone, on wasi_fs_list's rule:
  -- RNone is what llmll_reset_response leaves in the slot, so collapsing them
  -- would make "invoked with no arguments" indistinguishable from "no command
  -- published anything".
  , "wasi_proc_args :: IO ()"
  , "wasi_proc_args = llmll_publish_io $ do"
  , "  as <- getArgs"
  , "  _ <- evaluate (length as)"
  , "  return (RList as)"
  , ""
  -- Nanoseconds since an unspecified epoch, as RCode. The epoch is unspecified
  -- ON PURPOSE: only DIFFERENCES of two readings from the same process are
  -- meaningful, and nothing in the type system can enforce that, because a
  -- reading persisted with wasi.fs.write and re-read through wasi.fs.read comes
  -- back as a String and is re-parsed. Cross-run differencing is therefore a
  -- trust-channel assumption, not a checkable one; no phantom-origin type
  -- survives the round trip through the filesystem.
  , "wasi_clock_monotonic :: IO ()"
  , "wasi_clock_monotonic = llmll_publish_io $ do"
  , "  ns <- getMonotonicTimeNSec"
  , "  return (RCode (fromIntegral ns))"
  , ""
  -- BS.readFile is strict, so unlike wasi_fs_read there is no lazy-IO thunk to
  -- force; the `evaluate` below forces the hex rendering instead, keeping an
  -- encoding failure inside the try where it becomes RErr.
  --
  -- Hashing happens on BYTES, inside the builtin. Composing wasi.fs.read with a
  -- pure hash would hash DECODED TEXT: readFile is locale-decoded and throws on
  -- invalid UTF-8, so a binary artifact is not merely mis-hashed but unreadable.
  -- The driver uses this digest as a resume gate and a provenance pin, so a
  -- text round trip would silently disagree with the reference implementation.
  , "wasi_fs_sha256 :: String -> IO ()"
  , "wasi_fs_sha256 path = llmll_publish_io $ do"
  , "  bytes <- BS.readFile path"
  , "  let hex2 b = let s = showHex b \"\" in if length s == 1 then '0' : s else s"
  , "      digest = concatMap hex2 (BS.unpack (SHA256.hash bytes))"
  , "  _ <- evaluate (length digest)"
  , "  return (RText digest)"
  , ""
  -- exec + argv, never a shell string. `P.proc` does no shell interpretation,
  -- so metacharacters in argv are data. This does NOT bound authority: argv is
  -- unconstrained and a granted program that interprets its arguments as
  -- instructions delivers unbounded authority through them. primEffect gives
  -- this name ⊤ for that reason; see the note there.
  --
  -- Child output goes to FILES, not through the response channel: the channel
  -- carries a scalar (the exit code) and the payload stays on disk, which is
  -- the file-indirection property that keeps the Response arm set at five.
  --
  -- UseHandle: createProcess closes these handles after the fork, so the
  -- SUCCESS path must not close them again. The FAILURE path must, and the
  -- `onException` guards are not defensive decoration -- they were added after
  -- a measured defect. With a nonexistent executable, createProcess throws,
  -- llmll_publish_io turns it into RErr, and without these the two write
  -- handles leak still-open. GHC's handle lock then makes a LATER, unrelated
  -- wasi.fs.read of the same path fail with "resource busy (file is locked)",
  -- so one bad spawn corrupts a subsequent operation. hClose is idempotent, so
  -- closing on the error path cannot double-close what createProcess took.
  --
  -- A negative timeout means "no limit" (System.Timeout.timeout's own
  -- convention). On overrun the child is terminated and reaped under a bounded
  -- secondary wait, so a child ignoring SIGTERM costs 5s rather than a hang,
  -- and the overrun arrives as RErr — a budget overrun is a stage failure the
  -- program can branch on, not a crash.
  , "wasi_proc_run :: String -> [String] -> String -> String -> String -> Integer -> IO ()"
  , "wasi_proc_run exe args cwd outPath errPath secs = llmll_publish_io $ do"
  , "  outH <- openFile outPath WriteMode"
  , "  errH <- openFile errPath WriteMode `onException` hClose outH"
  , "  let closeBoth = hClose outH >> hClose errH"
  , "  (_, _, _, ph) <- P.createProcess (P.proc exe args)"
  , "                     { P.cwd     = Just cwd"
  , "                     , P.std_out = P.UseHandle outH"
  , "                     , P.std_err = P.UseHandle errH"
  , "                     } `onException` closeBoth"
  , "  finished <- timeout (fromIntegral (secs * 1000000)) (P.waitForProcess ph)"
  , "  case finished of"
  , "    Nothing -> do"
  , "      P.terminateProcess ph"
  , "      _ <- timeout 5000000 (P.waitForProcess ph)"
  , "      return (RErr (\"wasi.proc.run: \" ++ exe ++ \" exceeded \""
  , "                    ++ show secs ++ \"s\"))"
  , "    Just ExitSuccess     -> return (RCode 0)"
  , "    Just (ExitFailure c) -> return (RCode (fromIntegral c))"
  , ""
  -- No network runtime in this backend. A real body needs http-client plus TLS
  -- in every generated project's dependency set, which is a material expansion
  -- for a builtin with zero in-tree call sites. `error` would break the same
  -- no-crash property as above, and a silent no-op would let a program believe
  -- it posted. Diagnosed twice instead: a cgWarnings entry at codegen and this
  -- line at run time.
  -- Publishes RErr rather than RNone: RNone would read as "the post succeeded
  -- and returned nothing", which is the one thing this body cannot claim.
  , "wasi_http_post :: String -> String -> IO ()"
  , "wasi_http_post url _body = do"
  , "  hPutStrLn stderr (\"wasi.http.post: no runtime in this backend (url=\" ++ url ++ \")\")"
  , "  llmll_publish (RErr (\"wasi.http.post: no runtime in this backend (url=\" ++ url ++ \")\"))"
  , ""
  -- EFFECT-RESP RC-2 (seq-commands is discard-left) is delivered by this
  -- definition UNCHANGED: `a >> b` leaves b's slot write last, so the composite
  -- yields b's response and drops a's. Do not "implement" RC-2 here. A test
  -- pins this line for that reason.
  , "seq_commands :: IO () -> IO () -> IO ()"
  , "seq_commands a b = a >> b"
  , ""
  , "-- §13.11 Cryptographic operations (v0.6.1)"
  , "-- HMAC-SHA1: RFC 2104 + FIPS 180-4 (opaque; correctness is Asserted)"
  , "-- Uses Data.Bits for XOR; sha1_hash is a simplified implementation."
  , "-- In production, replace with crypton or cryptohash-sha1."
  , "hmac_sha1 :: [Word8] -> [Word8] -> [Word8]"
  , "hmac_sha1 key msg ="
  , "  let key' = if length key > 64 then sha1_hash key else key ++ replicate (64 - length key) 0"
  , "      opad = map (\\b -> xor b 0x5c) key'"
  , "      ipad = map (\\b -> xor b 0x36) key'"
  , "  in sha1_hash (opad ++ sha1_hash (ipad ++ msg))"
  , ""
  , "sha1_hash :: [Word8] -> [Word8]"
  , "sha1_hash input ="
  , "  -- NOT SHA-1. A polynomial rolling hash truncated to 20 bytes, with no"
  , "  -- preimage or collision resistance. Disclosed as a stub since CRYPTO-1"
  , "  -- (docs/design/critique-2026-07-19-triage.md:34); the sha1 -> sha1_stub"
  , "  -- rename was considered and retracted (critique-2026-05-23-triage.md:25)."
  , "  -- A prior line here asserted conformance to a published test-vector"
  , "  -- suite; that claim was false and is removed rather than weakened. A"
  , "  -- test pins that no such claim reappears in this preamble."
  , "  -- hmac_sha1 above is built entirely from this, so it is a stub too."
  , "  let h = foldl (\\acc b -> (acc * 31 + fromIntegral b) `mod` (2^160 :: Integer)) 0 input"
  , "      toBytes 0 _ = []"
  , "      toBytes n v = fromIntegral (v `mod` 256) : toBytes (n-1 :: Int) (v `div` 256)"
  , "  in take 20 (toBytes (20 :: Int) h ++ repeat 0)"
  ] ++ jsonPreamble

-- ---------------------------------------------------------------------------
-- §13.13 JSON (JSON-1)
-- ---------------------------------------------------------------------------

-- | JSON-1: the thirteen §13.13 builtins, hand-rolled.
--
-- Appended to 'runtimePreamble' rather than spliced conditionally at the call
-- site, for two reasons. It adds NO package dependency, so the closure argument
-- that would motivate conditional emission does not apply (aeson would have
-- added a measured 40 packages to a generated project; this adds zero). And
-- keeping it inside the single top-level CAF is what lets the WASI-RT
-- completeness fold in Spec.hs keep folding over one list without knowing the
-- program's import set — the property CodegenHs:189-191 deliberately preserves.
--
-- NUMBERS ARE STORED AS LEXEMES ('JNum String'). A parsed number's source text
-- is emitted back unchanged, so a round trip is byte-exact for numbers and the
-- serializer owes no float-formatting rule. Haskell's 'show' for Double and
-- CPython's 'repr' disagree across a wide band (1.0e-3 vs 0.001, 1.0e22 vs
-- 1e+22, 9.999999999999999e22 vs 1e+23), and storing the lexeme removes the
-- question rather than answering it.
--
-- OBJECTS ARE ASSOCIATION LISTS in parse order. Duplicate member names are
-- REJECTED at parse (RFC 7493 §2.3), compared after unescaping, which is what
-- makes 'json_set' replace-in-place total and the law
-- @json_get (json_set v k x) k == Right x@ unconditional.
--
-- Correctness tier is `asserted`, the sha1/hmac-sha1 precedent (LLMLL.md
-- §13.11). Unlike those stubs it carries a differential gate: Spec.hs runs this
-- parser against aeson (already a compiler dependency, free to the generated
-- closure) over the JSONTestSuite corpus.
jsonPreamble :: [Text]
jsonPreamble =
  [ ""
  , "-- §13.13 JSON — sealed opaque carrier (JSON-1)"
  , "data Json"
  , "  = JNull"
  , "  | JBool Bool"
  , "  | JNum String      -- source lexeme, never re-formatted"
  , "  | JStr String"
  , "  | JArr [Json]"
  , "  | JObj [(String, Json)]"
  , "  deriving (Eq, Show)"
  , ""
  , "jsonMaxDepth :: Int"
  , "jsonMaxDepth = 512"
  , ""
  , "jsonIsDigit :: Char -> Bool"
  , "jsonIsDigit c = c >= '0' && c <= '9'"
  , ""
  , "jsonIsHex :: Char -> Bool"
  , "jsonIsHex c = jsonIsDigit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')"
  , ""
  , "jsonHexVal :: Char -> Int"
  , "jsonHexVal c"
  , "  | jsonIsDigit c        = ord c - ord '0'"
  , "  | c >= 'a' && c <= 'f' = ord c - ord 'a' + 10"
  , "  | otherwise            = ord c - ord 'A' + 10"
  , ""
  , "jsonSkipWs :: String -> String"
  , "jsonSkipWs (c:cs) | c == ' ' || c == '\\t' || c == '\\n' || c == '\\r' = jsonSkipWs cs"
  , "jsonSkipWs s = s"
  , ""
  , "-- RFC 8259 §6 grammar: -? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE][+-]?[0-9]+)?"
  , "jsonNumOk :: String -> Bool"
  , "jsonNumOk t0 ="
  , "  let t1 = case t0 of { ('-':r) -> r ; _ -> t0 }"
  , "      (ip, t2) = span jsonIsDigit t1"
  , "      intOk = case ip of { [] -> False ; ('0':x) -> null x ; _ -> True }"
  , "      (fr, t3) = case t2 of"
  , "                   ('.':r) -> let (ds, r') = span jsonIsDigit r in (Just ds, r')"
  , "                   _       -> (Nothing, t2)"
  , "      fracOk = case fr of { Just ds -> not (null ds) ; Nothing -> True }"
  , "      exOk = case t3 of"
  , "               (e:r) | e == 'e' || e == 'E' ->"
  , "                 let r1 = case r of { (sg:rr) | sg == '+' || sg == '-' -> rr ; _ -> r }"
  , "                     (ds, r2) = span jsonIsDigit r1"
  , "                 in not (null ds) && null r2"
  , "               [] -> True"
  , "               _  -> False"
  , "  in intOk && fracOk && exOk"
  , ""
  , "jsonIsIntLexeme :: String -> Bool"
  , "jsonIsIntLexeme lx = jsonNumOk lx && not (any (\\c -> c == '.' || c == 'e' || c == 'E') lx)"
  , ""
  , "jsonPString :: String -> Either String (String, String)"
  , "jsonPString = go []"
  , "  where"
  , "    go _   []         = Left \"json-parse: unterminated string\""
  , "    go acc ('\"':r)    = Right (reverse acc, r)"
  , "    go _   ['\\\\']      = Left \"json-parse: dangling backslash\""
  , "    go acc ('\\\\':e:r) = case e of"
  , "      '\"'  -> go ('\"':acc) r"
  , "      '\\\\' -> go ('\\\\':acc) r"
  , "      '/'  -> go ('/':acc) r"
  , "      'b'  -> go ('\\b':acc) r"
  , "      'f'  -> go ('\\f':acc) r"
  , "      'n'  -> go ('\\n':acc) r"
  , "      'r'  -> go ('\\r':acc) r"
  , "      't'  -> go ('\\t':acc) r"
  , "      'u'  -> case r of"
  , "        (a:b:c:d:r')"
  , "          | all jsonIsHex [a,b,c,d] ->"
  , "              let hi = jsonHexVal a * 4096 + jsonHexVal b * 256"
  , "                       + jsonHexVal c * 16 + jsonHexVal d"
  , "              in if hi >= 0xD800 && hi <= 0xDBFF"
  , "                   then case r' of"
  , "                     ('\\\\':'u':a2:b2:c2:d2:r2)"
  , "                       | all jsonIsHex [a2,b2,c2,d2]"
  , "                       , let lo = jsonHexVal a2 * 4096 + jsonHexVal b2 * 256"
  , "                                  + jsonHexVal c2 * 16 + jsonHexVal d2"
  , "                       , lo >= 0xDC00 && lo <= 0xDFFF ->"
  , "                           let cp = 0x10000 + (hi - 0xD800) * 1024 + (lo - 0xDC00)"
  , "                           in go (chr cp : acc) r2"
  , "                     _ -> Left \"json-parse: unpaired high surrogate\""
  , "                   else if hi >= 0xDC00 && hi <= 0xDFFF"
  , "                     then Left \"json-parse: unpaired low surrogate\""
  , "                     else go (chr hi : acc) r'"
  , "        _ -> Left \"json-parse: invalid \\\\u escape\""
  , "      _    -> Left (\"json-parse: invalid escape '\\\\\" ++ [e] ++ \"'\")"
  , "    go acc (ch:r)"
  , "      | ch < ' '  = Left \"json-parse: unescaped control character in string\""
  , "      | otherwise = go (ch:acc) r"
  , ""
  , "jsonPNumber :: String -> Either String (String, String)"
  , "jsonPNumber s ="
  , "  let (lx, r) = span (\\c -> jsonIsDigit c || c == '-' || c == '+'"
  , "                            || c == '.' || c == 'e' || c == 'E') s"
  , "  in if null lx then Left \"json-parse: expected a number\""
  , "     else if jsonNumOk lx then Right (lx, r)"
  , "     else Left (\"json-parse: malformed number '\" ++ lx ++ \"'\")"
  , ""
  , "jsonLit :: String -> Json -> String -> Either String (Json, String)"
  , "jsonLit w v s ="
  , "  if w `isPrefixOf` s then Right (v, drop (length w) s)"
  , "  else Left (\"json-parse: invalid literal at '\" ++ take 8 s ++ \"'\")"
  , ""
  , "jsonPValue :: Int -> String -> Either String (Json, String)"
  , "jsonPValue d _ | d > jsonMaxDepth ="
  , "  Left \"json-parse: maximum nesting depth exceeded\""
  , "jsonPValue _ [] = Left \"json-parse: unexpected end of input\""
  , "jsonPValue d s@(c:cs)"
  , "  | c == '{' = jsonPObj (d+1) (jsonSkipWs cs) []"
  , "  | c == '[' = jsonPArr (d+1) (jsonSkipWs cs) []"
  , "  | c == '\"' = case jsonPString cs of"
  , "      Left e        -> Left e"
  , "      Right (t, r)  -> Right (JStr t, r)"
  , "  | c == 't' = jsonLit \"true\"  (JBool True)  s"
  , "  | c == 'f' = jsonLit \"false\" (JBool False) s"
  , "  | c == 'n' = jsonLit \"null\"  JNull         s"
  , "  | c == '-' || jsonIsDigit c = case jsonPNumber s of"
  , "      Left e        -> Left e"
  , "      Right (lx, r) -> Right (JNum lx, r)"
  , "  | otherwise = Left (\"json-parse: unexpected character '\" ++ [c] ++ \"'\")"
  , ""
  , "jsonPArr :: Int -> String -> [Json] -> Either String (Json, String)"
  , "jsonPArr _ [] _ = Left \"json-parse: unterminated array\""
  , "jsonPArr _ (']':r) [] = Right (JArr [], r)"
  , "jsonPArr d s acc = case jsonPValue d s of"
  , "  Left e -> Left e"
  , "  Right (v, r1) -> case jsonSkipWs r1 of"
  , "    (',':r2) -> jsonPArr d (jsonSkipWs r2) (v:acc)"
  , "    (']':r2) -> Right (JArr (reverse (v:acc)), r2)"
  , "    _        -> Left \"json-parse: expected ',' or ']' in array\""
  , ""
  , "jsonPObj :: Int -> String -> [(String, Json)] -> Either String (Json, String)"
  , "jsonPObj _ [] _ = Left \"json-parse: unterminated object\""
  , "jsonPObj _ ('}':r) [] = Right (JObj [], r)"
  , "jsonPObj d ('\"':cs) acc = case jsonPString cs of"
  , "  Left e -> Left e"
  , "  Right (k, r1) -> case jsonSkipWs r1 of"
  , "    (':':r2) -> case jsonPValue d (jsonSkipWs r2) of"
  , "      Left e -> Left e"
  , "      Right (v, r3) ->"
  , "        -- RFC 7493 §2.3: duplicates are rejected, compared AFTER unescaping"
  , "        -- (jsonPString has already unescaped both sides here). RFC 8259 §4"
  , "        -- leaves this 'unpredictable', and the inputs are agent-authored."
  , "        if any (\\kv -> fst kv == k) acc"
  , "          then Left (\"json-parse: duplicate object member '\" ++ k"
  , "                     ++ \"' (RFC 7493 §2.3)\")"
  , "          else case jsonSkipWs r3 of"
  , "            (',':r4) -> jsonPObj d (jsonSkipWs r4) ((k,v):acc)"
  , "            ('}':r4) -> Right (JObj (reverse ((k,v):acc)), r4)"
  , "            _        -> Left \"json-parse: expected ',' or '}' in object\""
  , "    _ -> Left \"json-parse: expected ':' after object member name\""
  , "jsonPObj _ _ _ = Left \"json-parse: expected a quoted member name in object\""
  , ""
  , "json_parse :: String -> Either String Json"
  , "json_parse s = case jsonPValue 0 (jsonSkipWs s) of"
  , "  Left e -> Left e"
  , "  Right (v, rest) -> case jsonSkipWs rest of"
  , "    [] -> Right v"
  , "    r  -> Left (\"json-parse: trailing input at '\" ++ take 20 r ++ \"'\")"
  , ""
  , "jsonU :: Int -> String"
  , "jsonU cp"
  , "  | cp > 0xFFFF ="
  , "      let n  = cp - 0x10000"
  , "          hi = 0xD800 + n `div` 1024"
  , "          lo = 0xDC00 + n `mod` 1024"
  , "      in jsonU4 hi ++ jsonU4 lo"
  , "  | otherwise = jsonU4 cp"
  , "  where"
  , "    jsonU4 v = \"\\\\u\" ++ [hexd (v `div` 4096), hexd ((v `div` 256) `mod` 16)"
  , "                        ,hexd ((v `div` 16) `mod` 16), hexd (v `mod` 16)]"
  , "    hexd k = if k < 10 then chr (ord '0' + k) else chr (ord 'a' + k - 10)"
  , ""
  , "jsonQuote :: String -> String"
  , "jsonQuote t = '\"' : concatMap esc t ++ \"\\\"\""
  , "  where"
  , "    esc ch = case ch of"
  , "      '\"'  -> \"\\\\\\\"\""
  , "      '\\\\' -> \"\\\\\\\\\""
  , "      '\\n' -> \"\\\\n\""
  , "      '\\r' -> \"\\\\r\""
  , "      '\\t' -> \"\\\\t\""
  , "      '\\b' -> \"\\\\b\""
  , "      '\\f' -> \"\\\\f\""
  , "      _ | ch < ' ' || ch > '~' -> jsonU (ord ch)"
  , "        | otherwise            -> [ch]"
  , ""
  , "-- Deterministic, one-space indent, members in stored order. NOT specified"
  , "-- against any external producer's bytes: the resume gate compares a digest"
  , "-- this run recorded against the file as it is now, so self-consistency is"
  , "-- the whole requirement and cross-implementation byte-identity is not."
  , "jsonRender :: Int -> Json -> String"
  , "jsonRender _ JNull     = \"null\""
  , "jsonRender _ (JBool b) = if b then \"true\" else \"false\""
  , "jsonRender _ (JNum lx) = lx"
  , "jsonRender _ (JStr t)  = jsonQuote t"
  , "jsonRender _ (JArr []) = \"[]\""
  , "jsonRender i (JArr vs) ="
  , "  \"[\\n\" ++ intercalate \",\\n\""
  , "       [ replicate (i+1) ' ' ++ jsonRender (i+1) v | v <- vs ]"
  , "  ++ \"\\n\" ++ replicate i ' ' ++ \"]\""
  , "jsonRender _ (JObj []) = \"{}\""
  , "jsonRender i (JObj kvs) ="
  , "  \"{\\n\" ++ intercalate \",\\n\""
  , "       [ replicate (i+1) ' ' ++ jsonQuote k ++ \": \" ++ jsonRender (i+1) v"
  , "       | (k,v) <- kvs ]"
  , "  ++ \"\\n\" ++ replicate i ' ' ++ \"}\""
  , ""
  , "json_serialize :: Json -> String"
  , "json_serialize = jsonRender 0"
  , ""
  , "json_get :: Json -> String -> Either String Json"
  , "json_get (JObj kvs) k = case lookup k kvs of"
  , "  Just v  -> Right v"
  , "  Nothing -> Left (\"json-get: no member '\" ++ k ++ \"'\")"
  , "json_get _ k = Left (\"json-get: not an object (looking for '\" ++ k ++ \"')\")"
  , ""
  , "json_get_string :: Json -> String -> Either String String"
  , "json_get_string o k = case json_get o k of"
  , "  Left e         -> Left e"
  , "  Right (JStr t) -> Right t"
  , "  Right _        -> Left (\"json-get-string: member '\" ++ k ++ \"' is not a string\")"
  , ""
  , "-- Strict on '1.0': it denotes an integral value but is not an integer"
  , "-- lexeme, and silent narrowing is the worse failure."
  , "json_get_int :: Json -> String -> Either String Integer"
  , "json_get_int o k = case json_get o k of"
  , "  Left e         -> Left e"
  , "  Right (JNum lx)"
  , "    | jsonIsIntLexeme lx -> Right (read lx)"
  , "    | otherwise -> Left (\"json-get-int: member '\" ++ k ++ \"' is '\" ++ lx"
  , "                         ++ \"', which is not an integer lexeme\")"
  , "  Right _ -> Left (\"json-get-int: member '\" ++ k ++ \"' is not a number\")"
  , ""
  , "-- The source lexeme, unparsed. A caller comparing it to a literal gets"
  , "-- STRLIT string equality, which is inside Sigma_auto; a float comparison"
  , "-- would not be."
  , "json_get_number :: Json -> String -> Either String String"
  , "json_get_number o k = case json_get o k of"
  , "  Left e          -> Left e"
  , "  Right (JNum lx) -> Right lx"
  , "  Right _         -> Left (\"json-get-number: member '\" ++ k ++ \"' is not a number\")"
  , ""
  , "json_get_bool :: Json -> String -> Either String Bool"
  , "json_get_bool o k = case json_get o k of"
  , "  Left e          -> Left e"
  , "  Right (JBool b) -> Right b"
  , "  Right _         -> Left (\"json-get-bool: member '\" ++ k ++ \"' is not a bool\")"
  , ""
  , "json_array :: Json -> Either String [Json]"
  , "json_array (JArr vs) = Right vs"
  , "json_array _         = Left \"json-array: not an array\""
  , ""
  , "json_object :: Json"
  , "json_object = JObj []"
  , ""
  , "-- Replace-in-place, append when absent. Total on an object because the"
  , "-- parser rejects duplicates, which is what makes"
  , "-- json_get (json_set v k x) k == Right x hold unconditionally."
  , "jsonUpsert :: String -> Json -> [(String, Json)] -> [(String, Json)]"
  , "jsonUpsert k v [] = [(k, v)]"
  , "jsonUpsert k v ((k0,v0):r)"
  , "  | k0 == k   = (k, v) : r"
  , "  | otherwise = (k0, v0) : jsonUpsert k v r"
  , ""
  , "json_set :: Json -> String -> Json -> Either String Json"
  , "json_set (JObj kvs) k v = Right (JObj (jsonUpsert k v kvs))"
  , "json_set _ k _ = Left (\"json-set: not an object (setting '\" ++ k ++ \"')\")"
  , ""
  , "json_of_string :: String -> Json"
  , "json_of_string = JStr"
  , ""
  , "json_of_int :: Integer -> Json"
  , "json_of_int n = JNum (show n)"
  , ""
  , "json_of_bool :: Bool -> Json"
  , "json_of_bool = JBool"
  , ""
  , "json_of_list :: [Json] -> Json"
  , "json_of_list = JArr"
  ]

-- ---------------------------------------------------------------------------
-- Statement emitter
-- ---------------------------------------------------------------------------

emitStmt :: Statement -> Text
emitStmt (STypeDef name body)             = emitTypeDef name body
emitStmt (SDefInterface name fns laws)      = emitInterface name fns laws
emitStmt (SDefLogic name params mRet c b) = emitDefLogic name params mRet c b
-- LT-INV (v0.11): SDef and SDefShell emit identically to SDefLogic.
emitStmt (SDef      name params mRet c b) = emitDefLogic name params mRet c b
emitStmt (SDefShell name params mRet c b _) = emitDefLogic name params mRet c b
-- v0.12.1: def-invariant codegen unchanged from its prior SDefLogic form.
emitStmt (SDefInvariant name params mRet c b) = emitDefLogic name params mRet c b
-- D2: SLetrec emits as a regular Haskell function.
-- The {- letrec :decreases ... -} marker is a breadcrumb for the D4 LH annotation pass.
emitStmt (SLetrec name params mRet c dec b) =
  "{- letrec :decreases " <> emitExpr dec <> " -}\n"
  <> emitDefLogic name params mRet c b
emitStmt (SCheck prop)                    = emitCheck prop
emitStmt (SImport _)                      = ""  -- handled in header
emitStmt (SExpr _)                        = ""  -- top-level exprs not representable
emitStmt SDefMain{}                       = ""  -- goes to Main.hs
emitStmt (SOpen _ _)                      = ""  -- compile-time namespace annotation
emitStmt (SExport _)                      = ""  -- compile-time export annotation
emitStmt (STrust _ _)                     = ""  -- trust declaration (compile-time)
emitStmt (SWeaknessOk _ _)                = ""  -- weakness suppression (compile-time)

-- | Emit a type declaration as newtype / data / type alias.
emitTypeDef :: Name -> Type -> Text
emitTypeDef name (TSumType ctors) =
  let fmtCtor (c, Nothing) = toHsIdent c
      fmtCtor (c, Just t)  = toHsIdent c <> " " <> toHsType t
      ctorStr = T.intercalate "\n  | " (map fmtCtor ctors)
  in "data " <> toHsIdent name <> "\n  = " <> ctorStr
     <> "\n  deriving (Eq, Show)\n"
emitTypeDef name (TCustom body)
  -- Sum type from ParserJSON (legacy path — should not reach here after refactor,
  -- kept as fallback for any TCustom that still contains a pipe-separated list).
  | " | " `T.isInfixOf` body =
      let parts = map T.strip (T.splitOn " | " body)
          ctors  = T.intercalate "\n  | " (map emitCtorDecl parts)
      in "data " <> toHsIdent name <> "\n  = " <> ctors
         <> "\n  deriving (Eq, Show)\n"
  -- Plain type alias
  | otherwise = "type " <> toHsIdent name <> " = " <> toHsType (TCustom body) <> "\n"
emitTypeDef name (TDependent _ base _) =
  -- Emit as type alias so QuickCheck can generate values via the base Arbitrary instance.
  "type " <> toHsIdent name <> " = " <> toHsType base <> "\n"
emitTypeDef name body =
  "type " <> toHsIdent name <> " = " <> toHsType body <> "\n"

-- | Map LLMLL primitive type name to the correct Haskell type.
-- Used in constructor payload position where TCustom would otherwise emit the name verbatim.
mapLlmllPrimType :: Text -> Text
mapLlmllPrimType "unit"   = "()"
mapLlmllPrimType "string" = "String"
mapLlmllPrimType "int"    = "Integer"  -- LT-INT (v0.11): mathematical-integer semantics
mapLlmllPrimType "bool"   = "Bool"
mapLlmllPrimType "float"  = "Double"
mapLlmllPrimType other    = toHsIdent other  -- user-defined types: pascal-case

-- | Emit one data constructor from "CtorName" or "CtorName:PayloadType".
emitCtorDecl :: Text -> Text
emitCtorDecl t =
  case T.splitOn ":" t of
    [ctor]          -> toHsIdent ctor
    [ctor, payload] -> toHsIdent ctor <> " " <> mapLlmllPrimType (T.strip payload)
    (ctor:rest)     -> toHsIdent ctor <> " " <> mapLlmllPrimType (T.strip (T.intercalate ":" rest))
    []              -> "_Unknown"

-- | Emit a single data constructor (legacy helper; kept for completeness).
emitDataCtor :: Text -> Text
emitDataCtor t =
  let ws = T.words t
  in case ws of
    []     -> "_Unknown"
    [c]    -> toHsIdent c
    (c:ts) -> toHsIdent c <> " " <> T.unwords (map (toHsType . TCustom) ts)

-- | Emit a def-interface as a Haskell typeclass + law properties.
emitInterface :: Name -> [(Name, Type)] -> [Property] -> Text
emitInterface name fns laws = T.unlines $
  [ "class " <> toHsIdent name <> " t where" ]
  ++ map emitMethod fns
  ++ [ "" ]
  ++ concatMap (emitLaw name) (zip [1..] laws)
  where
    emitMethod (fname, ftype) =
      "  " <> toHsIdent fname <> " :: t -> " <> emitFnType ftype

-- | Emit a single interface law as a QuickCheck property.
-- Naming convention: prop_InterfaceName_law_N (auto-numbered).
emitLaw :: Name -> (Int, Property) -> [Text]
emitLaw ifaceName (idx, Property _desc bindings body _subjects) =
  let propName = "prop_" <> toHsIdent ifaceName <> "_law_" <> tshow idx
      paramNames = T.unwords (map (toHsIdent . fst) bindings)
      paramTypes = map (toHsType . snd) bindings
      sig = propName <> " :: " <> T.intercalate " -> " (paramTypes ++ ["Bool"])
      def = propName <> " " <> paramNames <> " = " <> emitExpr body
  in [ "-- " <> toHsIdent ifaceName <> " law " <> tshow idx
     , sig
     , def
     , ""
     ]
  where
    tshow :: Show a => a -> Text
    tshow = T.pack . show

emitFnType :: Type -> Text
emitFnType (TFn args ret) =
  T.intercalate " -> " (map toHsType args ++ [toHsType ret])
emitFnType t = toHsType t

-- | Emit a def-logic as a Haskell function.
emitDefLogic :: Name -> [(Name, Type)] -> Maybe Type -> Contract -> Expr -> Text
emitDefLogic name params mRet contract body = T.unlines $
  sigLines ++
  [ toHsIdent name <> paramNames <> " ="
  , "  " <> bodyWithPre
  , ""
  ]
  where
    -- Only emit a type signature when we have an explicit return type.
    -- Omitting the sig lets GHC infer the most general type without conflicts.
    sigLines
      | Just retT <- mRet, not (isPolyType retT) =
        [ toHsIdent name <> " :: "
          <> T.intercalate " -> " (map (toHsType . snd) params ++ [toHsType retT])
        ]
      | otherwise = []  -- omit sig; GHC infers
    paramNames = if null params then ""
                 else " " <> T.unwords (map (toHsIdent . fst) params)
    -- Wrap body in a pre-condition assertion using seq (purely functional).
    -- LT-PPR (v0.11): predicate-carrying ?proof-required in pre-position emits
    -- the predicate directly as the assertion; the error stub is elided since
    -- the predicate IS the runnable check. Post-position wraps result in a let
    -- so the assertion sees the computed value before it is returned.
    bodyWithPre = case contractPre contract of
      Just (EHole (HProofRequired _ (Just pred))) ->
        let preExpr = "if " <> emitExpr pred <> " then () else error \"pre-condition (proof-required predicate) failed\""
        in "(let { _pre_ = " <> preExpr <> " } in _pre_ `seq` " <> bodyWithPost <> ")"
      Nothing -> bodyWithPost
      Just e  ->
        let preExpr = "if " <> emitExpr e <> " then () else error \"pre-condition failed\""
        in "(let { _pre_ = " <> preExpr <> " } in _pre_ `seq` " <> bodyWithPost <> ")"
    bodyWithPost = case contractPost contract of
      Just (EHole (HProofRequired _ (Just pred))) ->
        "(let { _result_ = " <> emitBodyExpr <> "; _ppost_ = if " <> emitExpr pred
        <> " then () else error \"post-condition (proof-required predicate) failed\" } in _ppost_ `seq` _result_)"
      _ -> emitBodyExpr
    -- LEVER-A0: bytes-zero's length comes from the declared return type — the
    -- typechecker admits (bytes-zero) as a body only under a literal
    -- '-> bytes[n]' (the v1 determining context), so mRet is authoritative here.
    emitBodyExpr = case (mRet, body) of
      (Just (TBytes n), EApp "bytes-zero" []) -> "(bytes_zero " <> T.pack (show n) <> ")"
      _                                       -> emitExpr body

-- | Emit a check block as a QuickCheck property.
emitCheck :: Property -> Text
emitCheck prop = T.unlines
  [ "-- check: " <> propDescription prop
  , "prop_" <> sanitizeCheckLabel (propDescription prop)
    <> " :: " <> T.intercalate " -> " (map (toHsType . snd) (propBindings prop) ++ ["Bool"])
  , "prop_" <> sanitizeCheckLabel (propDescription prop)
    <> " " <> T.unwords (map (toHsIdent . fst) (propBindings prop))
    <> " = " <> emitExpr (propBody prop)
  , ""
  ]

-- | Sanitize a check-block label for use as a Haskell 'prop_*' function name.
-- Replaces any character outside [a-zA-Z0-9] with '_', then collapses runs of
-- underscores, and strips a leading/trailing underscore.
sanitizeCheckLabel :: Text -> Text
sanitizeCheckLabel lbl =
  let replaced  = T.map (\c -> if isAsciiAlphaNum c then c else '_') lbl
      collapsed = T.intercalate "_" . filter (not . T.null) $ T.splitOn "__" replaced
  in T.dropWhile (== '_') . T.dropWhileEnd (== '_') $ collapsed
  where
    isAsciiAlphaNum c = (c >= 'a' && c <= 'z')
                     || (c >= 'A' && c <= 'Z')
                     || (c >= '0' && c <= '9')

-- ---------------------------------------------------------------------------
-- Expression emitter
-- ---------------------------------------------------------------------------

emitExpr :: Expr -> Text
emitExpr (ELit lit)        = emitLit lit
emitExpr (EVar name)       = toHsIdent name
emitExpr (EPair a b)       = "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
emitExpr (EIf c t f)       =
  "(if " <> emitExpr c <> " then " <> emitExpr t <> " else " <> emitExpr f <> ")"
emitExpr (ELet bs body)    = emitLet bs body
emitExpr (EApp "runtime-error" [msg])  = "(error " <> emitExpr msg <> ")"  -- v0.6.3: contract assertion (BUG-2)
emitExpr (EApp func args)  = emitApp func args
emitExpr (EOp op args)     = emitOp op args
emitExpr (EMatch scrut cs) = emitMatch scrut cs
emitExpr (ELambda ps body) =
  "(\\" <> T.unwords (map (toHsIdent . fst) ps) <> " -> " <> emitExpr body <> ")"
emitExpr (EAwait e)        =
  -- v0.3 §3.2: exception-safe await returning Result[t, DelegationError]
  "(do { r_ <- try (Async.wait " <> emitExpr e <> "); "
  <> "case r_ of { Left (e_ :: SomeException) -> pure (Left (show e_)); "
  <> "Right v_ -> pure (Right v_) } })"
emitExpr (EDo steps)       = emitDo steps
emitExpr (EHole hk)        = emitHole hk

emitLet :: [(Pattern, Maybe Type, Expr)] -> Expr -> Text
emitLet bs body =
  "(let { "
  <> T.intercalate "; " (map (\(pat,_,e) -> emitPat pat <> " = " <> emitExpr e) bs)
  <> " } in " <> emitExpr body <> ")"

emitApp :: Name -> [Expr] -> Text
emitApp "first"  [a] = "(fst " <> emitExpr a <> ")"
emitApp "second" [a] = "(snd " <> emitExpr a <> ")"
emitApp "pair"   [a,b] = "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
-- B3 fix: operators used as app fn names (kind:app, fn:"/") must be routed to
-- emitOp, otherwise we emit `(/ (i) (width))` which GHC parses as a section.
emitApp op args
  | op `elem` ["/", "mod", "%", "+", "-", "*", "=", "!=",
               "<", ">", "<=", ">=", "and", "or", "not", "=>", "<=>"]
  = emitOp op args
-- LT-INT (v0.11): Class A indexing primitives keep concrete `Int` Haskell
-- signatures per int-2-boundary-shims.md §3.1; codegen wraps `int`-typed
-- arguments (now `Integer` post-INT-2) in `fromIntegral` at the LLMLL-to-Haskell
-- call seam, and lifts `Int`-returning primitives back to `Integer`.
emitApp "list-length"   [xs]     = "(fromIntegral (list_length " <> wrap xs <> ") :: Integer)"
emitApp "string-length" [s]      = "(fromIntegral (string_length " <> wrap s <> ") :: Integer)"
-- LEVER-A0: bytes ops take the same Class-A seam (Int indices at the Haskell
-- boundary, Integer at the LLMLL surface). Map ops need no seam cases — keys
-- and values are already Integer-typed, so the generic fallback emits
-- (map_has (m) (k)) etc. via toHsIdent.
emitApp "bytes-length"  [b]      = "(fromIntegral (bytes_length " <> wrap b <> ") :: Integer)"
emitApp "bytes-get"     [b,i]    = "(bytes_get " <> wrap b <> " (fromIntegral " <> wrap i <> " :: Int))"
emitApp "bytes-set"     [b,i,v]  = "(bytes_set " <> wrap b <> " (fromIntegral " <> wrap i <> " :: Int) " <> wrap v <> ")"
emitApp "list-nth"      [xs,i]   = "(list_nth " <> wrap xs <> " (fromIntegral " <> wrap i <> " :: Int))"
emitApp "string-slice"  [s,f,t]  = "(string_slice " <> wrap s <> " (fromIntegral " <> wrap f <> " :: Int) (fromIntegral " <> wrap t <> " :: Int))"
emitApp "string-char-at" [s,i]   = "(string_char_at " <> wrap s <> " (fromIntegral " <> wrap i <> " :: Int))"
emitApp func args =
  "(" <> toHsIdent func <> " " <> T.unwords (map wrap args) <> ")"

-- | Wrap an argument expression in parentheses for safe Haskell emission.
-- LT-INT (v0.11): used by `emitApp` Class A clauses to insert `fromIntegral`
-- conversions cleanly without re-parenthesising the original expression.
wrap :: Expr -> Text
wrap e = "(" <> emitExpr e <> ")"


emitOp :: Name -> [Expr] -> Text
emitOp "="   [a,b] = "(" <> emitExpr a <> " == " <> emitExpr b <> ")"
emitOp "!="  [a,b] = "(" <> emitExpr a <> " /= " <> emitExpr b <> ")"
emitOp "and" [a,b] = "(" <> emitExpr a <> " && " <> emitExpr b <> ")"
emitOp "or"  [a,b] = "(" <> emitExpr a <> " || " <> emitExpr b <> ")"
emitOp "not" [a]   = "(not " <> emitExpr a <> ")"
-- IMPL-SUGAR: implication (not a || b) and biconditional (Bool ==)
emitOp "=>"  [a,b] = "(not " <> emitExpr a <> " || " <> emitExpr b <> ")"
emitOp "<=>" [a,b] = "(" <> emitExpr a <> " == " <> emitExpr b <> ")"
-- P4 fix: LLMLL `/` is integer division (spec §13.1); emit `div`, not `/`.
-- `/` as a bare Haskell infix requires Fractional, which Int does not satisfy.
emitOp "/"   [a,b] = "(" <> emitExpr a <> " `div` " <> emitExpr b <> ")"
-- `mod` already correct; `%` is not valid Haskell infix — guard both spellings.
emitOp "%"   [a,b] = "(" <> emitExpr a <> " `mod` " <> emitExpr b <> ")"
emitOp "mod" [a,b] = "(" <> emitExpr a <> " `mod` " <> emitExpr b <> ")"
emitOp op    args  =
  "(" <> T.intercalate (" " <> op <> " ") (map emitExpr args) <> ")"

emitMatch :: Expr -> [(Pattern, Expr)] -> Text
emitMatch scrut cs =
  "(case " <> emitExpr scrut <> " of { "
  <> T.intercalate "; " (map emitArm cs)
  <> catchAll
  <> "})"
  where
    emitArm (pat, body) = emitPat pat <> " -> " <> emitExpr body
    -- Only add a catch-all if the last pattern is not already exhaustive
    lastIsWild = case cs of
      [] -> False
      _  -> case fst (last cs) of
              PWildcard -> True
              PVar _    -> True   -- variable patterns are exhaustive
              _         -> False
    -- Any arm with a variable/wildcard pattern is exhaustive (it catches everything)
    anyArmIsExhaustive = any (\(p,_) -> case p of { PVar _ -> True; PWildcard -> True; _ -> False }) cs
    -- Suppress if Left+Right both appear (exhaustive Either match)
    ctorNames = [c | (PConstructor c _, _) <- cs]
    isEitherExhaustive = "Left" `elem` ctorNames && "Right" `elem` ctorNames
    -- Suppress if True+False both appear (exhaustive Bool match)
    isBoolExhaustive   = "True" `elem` ctorNames && "False" `elem` ctorNames
    -- Suppress if Success+Error both appear (exhaustive Result match)
    isResultExhaustive = "Success" `elem` ctorNames && "Error" `elem` ctorNames
    -- Suppress for TSumType: type-checker already verified exhaustiveness statically;
    -- if running, all constructors are covered (or there's a wildcard — also caught above).
    isAdtExhaustive = not (null ctorNames)  -- any ctor patterns = ADT match, trust type-checker
    catchAll = if lastIsWild || anyArmIsExhaustive || isEitherExhaustive
                             || isBoolExhaustive || isResultExhaustive
                             || isAdtExhaustive
               then " "
               else "; _ -> error \"non-exhaustive match\" "

-- PR 3: pure let-chain emitter for do-blocks.
-- Each step desugars to a let-binding that destructures the (State, Command) pair.
-- Intermediate commands are bound to _cmdN (discarded but named to avoid
-- GHC -Wunused-binds). The final step's pair is returned as the block result.
--
-- Example:
--   (do [s1 <- e0] [s2 <- e1] e2)
-- emits:
--   (let { (s1, _cmd0) = e0; (s2, _cmd1) = e1; (_s_2, _cmd2) = e2 } in (_s_2, _cmd2))
emitDo :: [DoStep] -> Text
emitDo [] = "((), ())"  -- empty do: unit state, unit command
emitDo steps =
  let ishow     = T.pack . show   -- local alias: tshow not in scope here
      indexed   = zip [0 :: Int ..] steps
      bindings  = map mkBinding indexed
      (finalIdx, _) = last indexed
      finalState = stateVar ishow finalIdx (last steps)
      finalCmd   = "_cmd" <> ishow finalIdx
  in "(let { " <> T.intercalate "; " bindings <> " } in ("
     <> finalState <> ", " <> finalCmd <> "))"
  where
    stateVar _     _ (DoStep (Just n) _ _) = toHsIdent n
    stateVar ishow i (DoStep Nothing  _ _) = "_s_" <> ishow i

    mkBinding (i, step@(DoStep _ e _)) =
      let ishow = T.pack . show
      in "(" <> stateVar ishow i step <> ", _cmd" <> ishow i <> ") = " <> emitExpr e

emitHole :: HoleKind -> Text
emitHole (HNamed n)        = "( error (\"hole: \" ++ " <> T.pack (show (T.unpack n)) <> ") {- HOLE -} )"
emitHole (HDelegate spec)  = case delegateOnFailure spec of
  Nothing -> "( error (\"delegate: \" ++ " <> T.pack (show (T.unpack (delegateAgent spec))) <> ") )"
  Just fb -> emitExpr fb
emitHole (HDelegateAsync s)= "( error (\"delegate-async: \" ++ " <> T.pack (show (T.unpack (delegateAgent s))) <> ") )"
emitHole (HDelegatePending _) = "( error \"delegate-pending: blocking hole\" )"
-- D3: proof-required holes in body position compile to an error stub — the LH pipeline validates this site.
-- LT-PPR (v0.11): predicate-carrying form in pre/post is handled by emitDefLogic; body position ignores the predicate.
emitHole (HProofRequired r _) = "( error \"PROOF REQUIRED [" <> r <> "]: add LiquidHaskell annotation\" )"
emitHole (HScaffold spec)  = "( error (\"scaffold: \" ++ " <> T.pack (show (T.unpack (scaffoldTemplate spec))) <> ") )"
emitHole _                 = "( error \"unresolved hole\" )"

-- ---------------------------------------------------------------------------
-- Pattern emitter
-- ---------------------------------------------------------------------------

emitPat :: Pattern -> Text
emitPat PWildcard             = "_"
emitPat (PVar n)              = toHsIdent n
emitPat (PLiteral lit)        = emitLit lit
emitPat (PConstructor "pair" [p1, p2]) = "(" <> emitPat p1 <> ", " <> emitPat p2 <> ")"
emitPat (PConstructor c [])   = rewriteCtor c
emitPat (PConstructor c subs) = "(" <> rewriteCtor c <> " " <> T.unwords (map emitPat subs) <> ")"

-- | Rewrite LLMLL constructor names to their Haskell codegen equivalents.
-- Result[t,e] is emitted as Either e t, so Success -> Right, Error -> Left.
rewriteCtor :: Name -> Text
rewriteCtor "Success" = "Right"
rewriteCtor "Error"   = "Left"
rewriteCtor other     = toHsIdent other

-- ---------------------------------------------------------------------------
-- Literal emitter
-- ---------------------------------------------------------------------------

emitLit :: Literal -> Text
emitLit (LitInt n)    = "(" <> T.pack (show n) <> " :: Integer)"  -- LT-INT (v0.11): unbounded
emitLit (LitFloat d)  = T.pack (show d)
emitLit (LitString s) = T.pack (show (T.unpack s))  -- uses Haskell show for quoting
emitLit (LitBool b)   = if b then "True" else "False"
emitLit LitUnit       = "()"

-- ---------------------------------------------------------------------------
-- Type emitter (for signatures)
-- ---------------------------------------------------------------------------

-- | True when a type is a polymorphic variable (GHC cannot unify with concrete types).
isPolyType :: Type -> Bool
isPolyType (TVar _)     = True
isPolyType (TCustom "_") = True
isPolyType _            = False

toHsType :: Type -> Text
toHsType TInt              = "Integer"  -- LT-INT (v0.11): mathematical-integer semantics
toHsType TFloat            = "Double"
toHsType TString           = "String"
toHsType TBool             = "Bool"
toHsType TUnit             = "()"
toHsType (TBytes _)        = "[Word8]"
toHsType (TList t)         = "[" <> toHsType t <> "]"
toHsType (TMap k v)        = "(Map.Map " <> toHsType k <> " " <> toHsType v <> ")"
toHsType (TResult t e)     = "(Either " <> toHsType e <> " " <> toHsType t <> ")"
toHsType (TPair a b)       = "(" <> toHsType a <> ", " <> toHsType b <> ")"  -- PR 1: pair tuple
toHsType (TPromise t)      = "(Async.Async " <> toHsType t <> ")"
toHsType (TFn args ret)    =
  T.intercalate " -> " (map toHsType args ++ [toHsType ret])
toHsType (TDependent _ b _)  = toHsType b
toHsType TDelegationError  = "String"
toHsType (TVar n)          = T.toLower n
toHsType (TCustom "Command") = "IO ()"
toHsType (TCustom "_")     = "a"
toHsType (TCustom n)       = toHsIdent n
-- TSumType is only valid in STypeDef body position; if it appears inline
-- (e.g. as a constructor payload referencing an anonymous sum) emit the
-- constructor names joined as a type variable (should not arise in practice).
toHsType (TSumType ctors)  = T.intercalate "_or_" (map (toHsIdent . fst) ctors)

-- ---------------------------------------------------------------------------
-- Event Log helpers emitted into generated Main.hs (v0.3.1)
-- ---------------------------------------------------------------------------

-- | Preamble functions emitted into the generated Main.hs for event logging.
--   Provides: headerJsonL, eventJsonL (with escape), captureStdout.
emitEventLogPreamble :: [Text]
emitEventLogPreamble =
  [ "-- Event Log (v0.3.1 §10a)"
  , "headerJsonL :: String -> String"
  , "headerJsonL m = \"{\\\"type\\\":\\\"header\\\",\\\"version\\\":\\\"0.3.1\\\",\\\"module\\\":\\\"\" ++ m ++ \"\\\"}\""
  , ""
  , "eventJsonL :: Int -> String -> String -> String -> String -> String"
  , "eventJsonL sq ik iv rk rv ="
  , "  \"{\\\"type\\\":\\\"event\\\",\\\"seq\\\":\" ++ show sq"
  , "  ++ \",\\\"input\\\":{\\\"kind\\\":\\\"\" ++ ik ++ \"\\\",\\\"value\\\":\\\"\" ++ esc iv"
  , "  ++ \"\\\"},\\\"result\\\":{\\\"kind\\\":\\\"\" ++ rk ++ \"\\\",\\\"value\\\":\\\"\" ++ esc rv"
  , "  ++ \"\\\"},\\\"captures\\\":[]}\""
  , "  where esc = concatMap (\\c -> if c == '\"' then \"\\\\\\\"\" else if c == '\\n' then \"\\\\n\" else [c])"
  , ""
  , "captureStdout :: IO () -> IO String"
  , "captureStdout action = do"
  , "  oldStdout <- hDuplicate stdout"
  , "  (readFd, writeFd) <- createPipe"
  , "  writeEnd <- fdToHandle writeFd"
  , "  hDuplicateTo writeEnd stdout"
  , "  action"
  , "  hFlush stdout"
  , "  hDuplicateTo oldStdout stdout"
  -- BUG-1 follow-on (v0.14.3): hDuplicateTo does not reliably preserve the
  -- NoBuffering mode set at program start (`stdout` picks up writeEnd's
  -- default BlockBuffering across the redirect/restore round trip, verified
  -- empirically -- omitting this line reproduces a hang on interactive
  -- step-by-step stdin/stdout, e.g. under `llmll replay`, because the
  -- restored stdout's write below sits in an unflushed block buffer that
  -- the reader blocks on forever). Re-assert NoBuffering after every
  -- restore rather than relying on inherited Handle state.
  , "  hSetBuffering stdout NoBuffering"
  , "  hClose writeEnd"
  , "  readEnd <- fdToHandle readFd"
  , "  output <- hGetContents readEnd"
  , "  length output `seq` pure ()   -- force lazy I/O (professor flag #1)"
  -- BUG-1 follow-on (v0.14.3): must be putStrLn, not putStr. Each step's
  -- captured output is echoed back to the real stdout with no delimiter
  -- between steps when `output` itself has no trailing newline (e.g.
  -- wasi.io.stdout does not append one) -- consecutive steps' output runs
  -- together on the wire ("helloworld" for inputs "hello","world"). `llmll
  -- replay`'s runReplay/replayOne (LLMLL.Replay) synchronizes step-by-step
  -- via hGetLine on this same stream, so with no newline it doesn't just
  -- look wrong -- it deadlocks: hGetLine blocks forever waiting for a line
  -- terminator that never arrives, since the child won't reach EOF until it
  -- gets more stdin, which the parent won't send until hGetLine returns.
  -- The event log's own recorded value is captured into `output` above,
  -- before this line, so this only affects the echoed real-stdout framing,
  -- not what gets logged/compared.
  , "  putStrLn output"
  , "  pure output"
  , ""
  -- EFFECT-RESP (RC-1): perform one command and return BOTH channels, the
  -- event log's stdout capture and the program's response. They are separate on
  -- purpose. Sourcing the response from `output` would make wasi.io.stdout and
  -- wasi.fs.read indistinguishable in the channel and would swallow the
  -- program's own console output into the response value.
  , "performStep :: IO () -> IO (String, Response)"
  , "performStep cmd = do"
  , "  llmll_reset_response"
  , "  output <- captureStdout cmd"
  , "  resp <- readIORef llmll_response_slot"
  , "  pure (output, resp)"
  ]

-- ---------------------------------------------------------------------------
-- src/Main.hs harness
-- ---------------------------------------------------------------------------

emitMainHs :: Text -> [Statement] -> Text
emitMainHs modName stmts =
  case [s | s@SDefMain{} <- stmts] of
    []     -> ""
    (dm:_) -> T.unlines $
      [ "module Main where"
      , "import Lib"
      , "import System.Environment (getArgs)"
      -- PROC-BOUNDARY-1: the console harness's terminal paths. Imported
      -- unconditionally rather than per-mode because emitMainHs emits ONE
      -- import block for all three harnesses; the generated project sets no
      -- -Wall (emitPackageYaml below ships no ghc-options), so an import the
      -- cli/http bodies do not use costs a name in scope and nothing else.
      , "import System.Exit (exitWith, exitSuccess, ExitCode(..))"
      , "import System.IO (hSetBuffering, hFlush, hClose, hIsEOF, hPutStrLn, hGetContents, openFile, IOMode(..), BufferMode(..), stdin, stdout, stderr, hSetEncoding, utf8)"
      -- FS-ENCODING-1, second half. See the note on emitMainBody below: the fs
      -- bodies pin their OWN handles, but every other text handle in a generated
      -- program -- the three standard ones, the event log, and the pipe
      -- captureStdout builds -- still resolved the AMBIENT locale.
      , "import GHC.IO.Encoding (setLocaleEncoding)"
      , "import Data.IORef (newIORef, readIORef, modifyIORef')"
      , "import GHC.IO.Handle (hDuplicate, hDuplicateTo)"
      , "import System.Posix.IO (createPipe, fdToHandle)"
      , ""
      ] ++ emitEventLogPreamble ++ [""] ++ emitMainBody modName dm

-- | EFFECT-RESP: the console harness is a Mealy loop over the response channel.
--
--   r0        = perform initCmd        -- RNone when :init has no command (RC-3)
--   loop s r  = let (s', cmd) = step s line r
--               in if done? s' then on-done s'   -- cmd is NOT performed (RC-4)
--                             else loop s' (perform cmd)
--
-- Three things this shape gets right that the pseudocode leaves implicit.
--
-- The stdin channel and the response channel are SEPARATE parameters. The step
-- signature is (S, string, Response) -> (S, Command). Collapsing stdin into
-- RText would make console input indistinguishable from a wasi.fs.read payload
-- and would change every existing program's meaning, not just its arity.
--
-- done? moved from the top of the loop to AFTER the step call, and is applied
-- to s' rather than s. That is RC-4: done? is evaluated only on a state that has
-- received a response. The consequence is visible and is the design's, not an
-- accident: the terminating step's command is dropped, so a program whose final
-- effect matters must issue it from a non-terminating step and terminate on the
-- response. Programs with :on-done are unaffected there, since on-done still
-- runs and its command is still performed.
--
-- The terminating turn still CONSUMES a stdin line, so it is still logged, with
-- an empty output value. Skipping the entry would leave `llmll replay` driving
-- one fewer input than the recorded run consumed, which is a divergence the
-- harness manufactured rather than one the program produced.
-- PROC-BOUNDARY-1 §4: the two terminal paths, and their asymmetry is the whole
-- design content.
--
--   :done? DECLARED, and it holds   -> apply :status to the final state, exit
--                                      with it. No :status means exit 0.
--   :done? DECLARED, stdin exhausts -> exit a fixed 70. :status is NOT
--                                      consulted. This is the case the whole
--                                      guarantee exists for.
--   :done? NOT DECLARED             -> exit 0 on exhaustion.
--
-- THE DISCRIMINATOR IS DECLARATION, NOT FIRING, and Rev 3 corrects Rev 2 here.
-- Under the Rev 2 rule the exhaustion status was unconditional, which made every
-- run of a program with no :done? exit 70. That is a false alarm on a SUCCESSFUL
-- run: a program that declares no completion predicate has no notion of
-- completion, so reaching EOF is not starvation, it is the normal end of input.
-- Rev 2's rule could only ever fire on such a program, never distinguish
-- anything about it, and it broke three shipped programs to say nothing.
--
-- The guarantee survives intact WHERE "starved" IS MEANINGFUL: no program that
-- declares a completion predicate can exit 0 without reaching it. That is still
-- unconditional on the caller's state modelling, which is what §4.3 was
-- protecting; it is now also conditional on the caller having asked the question
-- at all, which is not a weakening because a program with no :done? has no
-- starvation to be protected from.
--
-- The mechanism: `loop` now returns `Maybe Integer` instead of `()`. Nothing is
-- exhaustion, `Just n` is a settled run carrying the status. Threading the
-- outcome back to `main` rather than calling exitWith from inside the branches
-- is what keeps `hClose logHandle` on both paths. It is not tidiness: the
-- header line written before the loop is the ONLY log write with no following
-- hFlush, so a program that reaches EOF before its first step would lose the
-- header entirely if the exit jumped over the close.
--
-- WHY EOF DOES NOT CONSULT :status, since the code cannot say it. A projection
-- from state alone cannot see the difference. A run that completed every stage
-- and a run whose input ran out sit in the SAME state; what separates them is
-- :done?, a predicate OUTSIDE the state. Applying :status at both paths would
-- make protection from the silent-success bug conditional on the caller having
-- modelled a terminal phase, and a flat state type would keep the bug. Fixing
-- 70 at the harness makes "no program exits 0 on a starved stdin" hold whatever
-- the state type is.
--
-- 70 is NOT reserved from the program: a :status may return 70 deliberately, so
-- a shell can distinguish neither-is-success from success but not exhaustion
-- from a chosen 70. Stated rather than left to inference; making 70
-- unavailable buys a distinction nothing needs at the cost of a hole in an
-- otherwise total 0..255 range.
--
-- NO SHIPPED PROGRAM CHANGES BEHAVIOUR. The three console programs in the tree
-- that declare no :done? (examples/replay-demo, examples/proof_required_test,
-- compiler/test/fixtures/pair_type_test) keep exiting 0, MEASURED, and the ones
-- that do declare it were already unable to exit 0 by exhaustion because they
-- did not terminate that way in any gate. :status is additive on top.
-- FS-ENCODING-1, SECOND HALF. The first half pinned UTF-8 on the two fs bodies'
-- own handles (wasi_fs_read / wasi_fs_write in runtimePreamble). That left the
-- generated program's OTHER text handles resolving the ambient locale, and the
-- gap is not theoretical: MEASURED under LC_ALL=C on Linux, fs_encoding.llmll
-- wrote "section § marker" to disk as correct UTF-8, read it back correctly, and
-- then DIED printing it -- `<stdout>: hPutChar: invalid argument (cannot encode
-- character '\167')`. Every later step (sha256, wasi.fs.copy, the multi-buffer
-- round trip) never ran, so ONE encode failure on stdout reported as four
-- independent gate failures and implicated wasi.fs.copy, which was innocent.
-- CI run 31035476326; the same binary passes every assertion under C.UTF-8.
--
-- setLocaleEncoding is the mechanism rather than a per-site hSetEncoding sweep,
-- because per-site pinning does not actually hold here. GHC's dupHandle_ builds
-- the new Handle's codec from getLocaleEncoding, so hDuplicate/hDuplicateTo --
-- which captureStdout calls three times per step -- RESET the encoding to the
-- locale's no matter what the source handle carried. Moving the locale itself is
-- what makes those duplicates UTF-8; it also covers the event-log handle and the
-- createPipe/fdToHandle pair without naming them. It is the same reason the
-- existing NoBuffering line in captureStdout has to be re-asserted after a
-- restore rather than inherited.
--
-- The three standard handles still need explicit pins: the RTS creates them
-- before main runs, so setLocaleEncoding cannot reach them retroactively.
--
-- This does NOT weaken the fs bodies' own hSetEncoding calls, which stay: they
-- state the fs contract locally and independently of which harness runs them.
emitMainBody :: Text -> Statement -> [Text]
emitMainBody modName SDefMain{defMainMode = ModeConsole, defMainStep = step, defMainInit = mInit, defMainDone = mDone, defMainOnDone = mOnDone, defMainStatus = mStatus} =
  [ "main :: IO ()"
  , "main = do"
  , "  setLocaleEncoding utf8"
  , "  hSetEncoding stdin utf8"
  , "  hSetEncoding stdout utf8"
  , "  hSetEncoding stderr utf8"
  , "  hSetBuffering stdin LineBuffering"
  , "  hSetBuffering stdout NoBuffering"
  , "  logHandle <- openFile \"" <> modName <> ".event-log.jsonl\" WriteMode"
  , "  hPutStrLn logHandle (headerJsonL \"" <> modName <> "\")"
  , "  seqRef <- newIORef (0 :: Int)"
  ] ++ initBlock ++
  [ "  outcome <- loop state0 r0 logHandle seqRef"
  , "  hClose logHandle"
  , "  llmll_terminate outcome"
  , "  where"
  -- ExitFailure 0 is an error in GHC ("ExitFailure 0 makes no sense"), so the
  -- zero case must branch to exitSuccess rather than be folded in.
  , "    llmll_terminate :: Maybe Integer -> IO ()"
  , exhaustionClause
  , "    llmll_terminate (Just 0) = exitSuccess"
  , "    llmll_terminate (Just n) = exitWith (ExitFailure (fromIntegral n))"
  , "    loop s r logHandle seqRef = do"
  , "      eof <- hIsEOF stdin"
  , "      if eof then return Nothing else do"
  , "        line <- getLine"
  , "        seqN <- readIORef seqRef"
  , "        let (s', cmd) = " <> stepCall step <> " s line r"
  ] ++ doneLines ++ settleDef
  where
    -- RC-3: :init's command supplies the FIRST response, so there is no special
    -- initial case. It is performed through llmll_perform (not captureStdout),
    -- which keeps init's own output going straight to the real stdout as it did
    -- before, and it is not logged, as it was not before.
    initBlock = case mInit of
      Nothing -> [ "  let state0 = ()"
                 , "  let r0 = RNone" ]
      Just e  -> [ "  let (state0, initCmd) = " <> emitExpr e
                 , "  r0 <- llmll_perform initCmd" ]
    stepCall (EVar n) = toHsIdent n
    stepCall e        = "(\\ s l r -> " <> emitExpr e <> " s l r)"
    -- The exhaustion status, gated on whether :done? is DECLARED. mDone is the
    -- discriminator and it is the only one available: whether :done? FIRED is a
    -- run-time fact, and `Nothing` reaching this clause already says it did not.
    --
    -- With no :done? the (Just _) clauses below are unreachable -- settleDef is
    -- empty, so nothing in the emitted loop constructs a Just. They are kept
    -- rather than dropped so llmll_terminate stays total under its signature; a
    -- one-clause definition would be a partial function whose fall-through is a
    -- pattern-match failure rather than an exit.
    exhaustionClause = case mDone of
      Just _  -> "    llmll_terminate Nothing  = exitWith (ExitFailure 70)"
      Nothing -> "    llmll_terminate Nothing  = exitSuccess"
    -- The non-terminating branch: perform, capture, log, recurse on the
    -- response. performStep clears the slot before performing and reads it
    -- after, so the delivered response is this command's and not a stale one.
    continueLines ind =
      [ ind <> "(output, resp) <- performStep cmd"
      , ind <> "hPutStrLn logHandle (eventJsonL seqN \"stdin\" line \"stdout\" output)"
      , ind <> "hFlush logHandle"
      , ind <> "modifyIORef' seqRef (+1)"
      , ind <> "loop s' resp logHandle seqRef"
      ]
    doneLines = case mDone of
      Nothing -> continueLines "        "
      Just e  ->
          ("        if " <> emitExpr e <> " s' then settle s' seqN line logHandle else do")
        : continueLines "          "
    -- RC-4's settle step. `cmd` is deliberately absent from this branch: it is
    -- constructed and not performed. It stays a plain (not _-prefixed) binding
    -- because the else branch below uses it, so there is no unused-binding
    -- warning to suppress.
    --
    -- The result kind is "none", NOT "stdout". This turn performs no command,
    -- so the program writes no line, and a "stdout" entry carrying "" claimed
    -- an output that was never produced. Measured at v0.14.82, that claim made
    -- the entry unmatchable for essentially every program: `llmll replay`
    -- wrote the input, called hGetLine, hit EOF because the process had
    -- exited, and reported a divergence on the one entry that exists to keep
    -- replay ALIGNED. It could match only by accident -- a program whose
    -- :on-done printed exactly a bare newline replayed 2/2, comparing "" from
    -- the log against "" read off the wire, two facts that are unrelated and
    -- happened to be equal. "none" says what is true (no command ran), keeps
    -- the entry so the input count still matches the recorded run, and lets
    -- Replay.replayOne skip the read instead of guessing.
    --
    -- THE LIMIT THIS LEAVES, stated because a passing count will not state it
    -- (A2): :on-done's command runs HERE, outside performStep, so its output
    -- reaches the real stdout and is recorded nowhere. The settle entry can
    -- match while carrying no information about it. A green `llmll replay` is
    -- therefore not evidence that :on-done ran, or ran correctly. Bringing it
    -- inside the oracle needs its output newline-framed like every other
    -- turn's, which would change the stdout bytes of every shipped program
    -- that declares :done?; that trade belongs to REPLAY-INJECT
    -- (docs/compiler-team-roadmap.md), not here.
    settleDef = case mDone of
      Nothing -> []
      Just _  ->
        [ "    settle " <> settleParam <> " seqN line logHandle = do"
        , "      hPutStrLn logHandle (eventJsonL seqN \"stdin\" line \"none\" \"\")"
        , "      hFlush logHandle"
        ] ++ onDoneLine ++
        -- PROC-BOUNDARY-1: the settled run's status leaves through the return
        -- value, so `main` still closes the log before exiting. :on-done keeps
        -- running FIRST and its command is still performed here, outside
        -- performStep, exactly as before -- the status application is appended
        -- after it and observes only the state, so it cannot reorder anything.
        [ "      return (Just (" <> statusExpr <> "))" ]
    -- Absent :status is exit 0, which is what every program shipped before this
    -- field did on the :done? path. The annotation pins the literal's type
    -- rather than leaving it to the use site, so the generated code does not
    -- depend on where GHC generalizes the where-block's binding group.
    onDoneLine = maybe [] (\od -> ["      " <> emitExpr od <> " s'"]) mOnDone
    statusExpr = maybe "0 :: Integer" (\st -> emitExpr st <> " s'") mStatus
    -- Underscore-prefixed when NEITHER :on-done nor :status is present, so
    -- -Wunused-matches stays quiet on generated code. :status reads the final
    -- state too, so it binds the parameter for the same reason :on-done does.
    settleParam
      | isJust mOnDone || isJust mStatus = "s'"
      | otherwise                        = "_s'"

-- The cli harness gets the same pins as the console one. It has no event log and
-- no captureStdout, so only the standard handles are at stake -- but `print` of
-- any non-ASCII result dies exactly as the console path did, and a fix that left
-- one of the two modes on the ambient locale would be the same defect with a
-- smaller blast radius rather than a fix.
emitMainBody _ SDefMain{defMainMode = ModeCli, defMainStep = step} =
  [ "main :: IO ()"
  , "main = do"
  , "  setLocaleEncoding utf8"
  , "  hSetEncoding stdout utf8"
  , "  hSetEncoding stderr utf8"
  , "  args <- getArgs"
  , "  print (" <> stepCall step <> " args)"
  ]
  where
    stepCall (EVar n) = toHsIdent n
    stepCall e        = "(" <> emitExpr e <> ")"

emitMainBody _ SDefMain{defMainMode = ModeHttp{httpPort = port}, defMainStep = step, defMainInit = mInit} =
  [ "-- HTTP mode requires 'import haskell.warp' in the LLMLL source."
  , "-- package.yaml dependency: warp, wai, http-types"
  , "-- import Network.Wai (Application, responseLBS)"
  , "-- import Network.Wai.Handler.Warp (run)"
  , "-- import Network.HTTP.Types (status200)"
  , "-- import qualified Data.ByteString.Lazy.Char8 as BLC"
  , "main :: IO ()"
  , "main = do"
  , "  putStrLn \"LLMLL HTTP server on port " <> T.pack (show port) <> "\""
  , "  let _state = " <> maybe "()" emitExpr mInit
  , "  -- run " <> T.pack (show port) <> " (app _state) -- uncomment after wiring warp"
  , "  -- where app s req respond = ..."
  , "  error \"http mode: wire warp in package.yaml and uncomment above\""
  , "  where _step = " <> stepCall step
  ]
  where
    stepCall (EVar n) = toHsIdent n
    stepCall e        = "(" <> emitExpr e <> ")"

emitMainBody _ _ = ["main :: IO ()", "main = return ()"]

-- ---------------------------------------------------------------------------
-- package.yaml
-- ---------------------------------------------------------------------------

-- | Emit a stack.yaml that pins the LTS resolver for the generated package.
emitStackYaml :: Text
emitStackYaml = T.unlines
  [ "resolver: lts-22.43   # GHC 9.6.6 — pin before production deploy"
  , "packages:"
  , "  - ."
  ]

-- | Sanitize a filename-derived module name into a valid Cabal/hpack package
-- (and dependency, and executable-component) name. Cabal package names may
-- only contain letters, digits, and hyphens -- hpack's 'dependencies:' field
-- parses each entry as a package name and rejects underscores outright
-- (\"invalid dependency\"), even though the top-level 'name:' field is more
-- lenient about what it accepts. BUG-2 (v0.14.3): any def-main program whose
-- filename contained an underscore (e.g. event_log_test.llmll) failed to
-- build because 'modName' was emitted verbatim as its own self-dependency.
-- The standard Cabal convention is underscore -> hyphen, applied uniformly
-- to 'name:', the 'executables:' stanza key, and the self-dependency entry
-- so all three stay mutually consistent (hpack auto-links the internal
-- library to an executable whose dependency name matches the package name).
sanitizePkgName :: Text -> Text
sanitizePkgName = T.map (\c -> if c == '_' then '-' else c)

emitPackageYaml :: Text -> Bool -> [Text] -> Text
emitPackageYaml modName hasMain hackagePkgs =
  let pkgName = sanitizePkgName modName
  in T.unlines $
  [ "name: " <> pkgName
  , "version: 0.1.0"
  , "dependencies:"
  , "  - base >= 4.14"
  , "  - containers"
  , "  - QuickCheck"
  , "  - async"
  , "  - regex-tdfa"
  -- WASI-RT: wasi_fs_delete's doesFileExist/removeFile guard. `directory` is a
  -- GHC boot package and is already a compiler dependency
  -- (compiler/package.yaml), so the LTS snapshot build is already cached in CI
  -- and this entry costs no resolver movement.
  , "  - directory"
  -- CAP-PROC: wasi_proc_run needs `process`, wasi_fs_sha256 needs
  -- `cryptohash-sha256` and `bytestring`. All three are already compiler
  -- dependencies (compiler/package.yaml), so the LTS snapshot is cached in CI
  -- and these cost no resolver movement — the same argument as `directory`
  -- above. Measured against lts-22.43, the generated-project closure moves
  -- from 31 to 33 packages. Adding http-client + http-client-tls for a
  -- wasi.http.get would have moved it to 79 (crypton, tls, four crypton-x509-*,
  -- three asn1-*, socks, pem, ...), which is why that operation is not here.
  , "  - process"
  , "  - cryptohash-sha256"
  , "  - bytestring"
  ] ++
  -- src/Main.hs (emitted whenever hasMain) imports System.Posix.IO for the
  -- event-log capture harness; hpack's default source-dirs auto-discovery
  -- pulls Main.hs into the `library` component's other-modules as well as
  -- the executable's, so `unix` must be a top-level (shared) dependency,
  -- not just an executable-scoped one.
  (if hasMain then ["  - unix"] else []) ++
  map (\p -> "  - " <> p) (hackagePkgNames hackagePkgs) ++
  [ ""
  , "library:"
  , "  source-dirs: src"
  , "  exposed-modules: [Lib]"
  ] ++
  (if hasMain
    then [ ""
         , "executables:"
         , "  " <> pkgName <> ":"
         , "    main: Main.hs"
         , "    source-dirs: src"
         , "    dependencies:"
         , "      - " <> pkgName
         ]
    else [])

-- Map haskell.<pkg> import path to the Hackage package name
hackagePkgNames :: [Text] -> [Text]
hackagePkgNames = nub . map toPkg
  where
    toPkg "aeson"    = "aeson"
    toPkg "text"     = "text"
    toPkg "warp"     = "warp"
    toPkg "wai"      = "wai"
    toPkg p          = T.intercalate "-" (T.splitOn "." p)

-- ---------------------------------------------------------------------------
-- FFI stubs for c.* imports
-- ---------------------------------------------------------------------------

emitFfiModHs :: [Text] -> Text
emitFfiModHs libs = T.unlines $
  [ "-- Auto-generated by llmll build. DO NOT EDIT."
  , "module FFI (" <> T.intercalate ", " (map (\l -> "module FFI." <> toHsModName l) libs) <> ") where"
  ] ++ map (\l -> "import FFI." <> toHsModName l) libs

emitFfiStub :: Text -> [Import] -> Text
emitFfiStub lib imports = T.unlines $
  [ "-- FFI stub for '" <> lib <> "'. Generated ONCE."
  , "-- Implement these using the C library API."
  , "{-# LANGUAGE ForeignFunctionInterface #-}"
  , "module FFI." <> toHsModName lib <> " where"
  , "import Foreign.C"
  , ""
  ] ++ concatMap (stubsForLib lib) imports

stubsForLib :: Text -> Import -> [Text]
stubsForLib lib imp
  | classifyImport imp == CLibImport lib =
      maybe [] (map emitFfiDecl) (importInterface imp)
  | otherwise = []

emitFfiDecl :: (Name, Type) -> Text
emitFfiDecl (fname, ftype) =
  let hsName = toHsIdent fname
  in "foreign import ccall \"" <> fname <> "\" " <> hsName
     <> " :: " <> emitFnType ftype

-- ---------------------------------------------------------------------------
-- Identifier helpers
-- ---------------------------------------------------------------------------

toHsIdent :: Text -> Text
toHsIdent = T.map sanitize
  where
    sanitize '-' = '_'
    sanitize '?' = '\''
    sanitize '.' = '_'
    sanitize  c  = c

toHsModName :: Text -> Text
toHsModName t = case T.uncons (T.map sanitize t) of
  Nothing       -> "Unknown"
  Just (c, rest) -> T.singleton (toUpper c) <> rest
  where
    sanitize '-' = '_'
    sanitize '.' = '_'
    sanitize  c  = c
    toUpper c
      | c >= 'a' && c <= 'z' = toEnum (fromEnum c - 32)
      | otherwise             = c

-- ---------------------------------------------------------------------------
-- Warnings
-- ---------------------------------------------------------------------------

-- | Codegen-time diagnostics. Surfaced by `llmll build` (Main.hs prints each
-- as "WARNING: ..." and buildResultJson carries them in the JSON envelope).
--
-- WASI-RT: the only current warning is wasi.http.post, whose preamble body is
-- a stderr-diagnosed stub rather than a network call. Diagnosing at codegen as
-- well as at run time means a program that posts is told so before it runs,
-- not only while it runs.
stmtWarnings :: Statement -> [Text]
stmtWarnings s
  | any (callsName "wasi.http.post") (stmtExprs s) =
      [ "wasi.http.post has no network runtime in the Haskell backend; the \
        \generated body writes a diagnostic to stderr and performs no request." ]
  | otherwise = []

-- | Every expression directly held by a statement. Bodies only — types,
-- contracts and patterns carry no applied names that primEffect would reach.
stmtExprs :: Statement -> [Expr]
stmtExprs s = case s of
  SDefLogic{}     -> [defLogicBody s]
  SDef{}          -> [defBody s]
  SDefShell{}     -> defShellBody s : defShellDecreases s
  SDefInvariant{} -> [defInvariantBody s]
  SLetrec{}       -> [letrecDecreases s, letrecBody s]
  SExpr e         -> [e]
  SDefMain{}      -> catMaybes [ defMainInit s, Just (defMainStep s)
                               , defMainDone s, defMainOnDone s
                               , defMainStatus s ]
  _               -> []

-- | Does this expression apply the given name anywhere inside it?
-- Total over the Expr grammar (Syntax.hs:218-231); a new constructor added
-- without a case here is a -Wincomplete-patterns build failure, which is the
-- intent.
callsName :: Name -> Expr -> Bool
callsName n = go
  where
    go e = case e of
      EApp f args    -> f == n || any go args
      EOp _ args     -> any go args
      ELit _         -> False
      EVar v         -> v == n
      ELet binds b   -> any (\(_, _, x) -> go x) binds || go b
      EIf c t f      -> go c || go t || go f
      EMatch scr arms-> go scr || any (go . snd) arms
      EPair a b      -> go a || go b
      EHole _        -> False
      EAwait x       -> go x
      ELambda _ b    -> go b
      EDo steps      -> any (\(DoStep _ x _) -> go x) steps
