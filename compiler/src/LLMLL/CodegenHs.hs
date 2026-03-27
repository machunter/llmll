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
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (nub, intercalate)

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
  [ "import Data.List (isPrefixOf, intercalate, nub)"
  , "import Data.Char (ord, chr)"
  , "import qualified Data.Map.Strict as Map"
  , "import System.IO (hPutStr, stderr)"
  , "import Test.QuickCheck (quickCheck, property)"
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

hackageImportLine :: Text -> Text
hackageImportLine pkg = "import " <> pkgToModule pkg
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
  , "range :: Int -> Int -> [Int]"
  , "range from to = [from .. to - 1]"
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
  , "string_char_at s i = if i < length s then [s !! i] else \"\""
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
  , "-- §13.7 Numeric"
  , "int_to_string :: Int -> String"
  , "int_to_string = show"
  , ""
  , "string_to_int :: String -> Either String Int"
  , "string_to_int s = case reads s of"
  , "  [(n, \"\")] -> Right n"
  , "  _         -> Left (\"string_to_int: cannot parse '\" ++ s ++ \"'\")"
  , ""
  , "llmll_abs :: Int -> Int"
  , "llmll_abs = abs"
  , ""
  , "llmll_min :: Int -> Int -> Int"
  , "llmll_min = min"
  , ""
  , "llmll_max :: Int -> Int -> Int"
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
  , "-- §13.9 WASI command constructors (IO actions for v0.1.2)"
  , "wasi_io_stdout :: String -> IO ()"
  , "wasi_io_stdout = putStr"
  , ""
  , "wasi_io_stderr :: String -> IO ()"
  , "wasi_io_stderr = hPutStr stderr"
  , ""
  , "wasi_http_response :: Int -> String -> IO ()"
  , "wasi_http_response code body = putStrLn (show code ++ \" \" ++ body)"
  , ""
  , "seq_commands :: IO () -> IO () -> IO ()"
  , "seq_commands a b = a >> b"
  , ""
  , "random_int :: IO Int"
  , "random_int = return 42  -- stub; wire System.Random in production"
  ]

-- ---------------------------------------------------------------------------
-- Statement emitter
-- ---------------------------------------------------------------------------

emitStmt :: Statement -> Text
emitStmt (STypeDef name body)             = emitTypeDef name body
emitStmt (SDefInterface name fns)         = emitInterface name fns
emitStmt (SDefLogic name params mRet c b) = emitDefLogic name params mRet c b
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
mapLlmllPrimType "int"    = "Int"
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

-- | Emit a def-interface as a Haskell typeclass.
emitInterface :: Name -> [(Name, Type)] -> Text
emitInterface name fns = T.unlines $
  [ "class " <> toHsIdent name <> " t where" ]
  ++ map emitMethod fns
  ++ [ "" ]
  where
    emitMethod (fname, ftype) =
      "  " <> toHsIdent fname <> " :: t -> " <> emitFnType ftype

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
    bodyWithPre = case contractPre contract of
      Nothing -> emitExpr body
      Just e  ->
        let preExpr = "if " <> emitExpr e <> " then () else error \"pre-condition failed\""
        in "(let { _pre_ = " <> preExpr <> " } in _pre_ `seq` " <> emitExpr body <> ")"

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
emitExpr (EApp func args)  = emitApp func args
emitExpr (EOp op args)     = emitOp op args
emitExpr (EMatch scrut cs) = emitMatch scrut cs
emitExpr (ELambda ps body) =
  "(\\" <> T.unwords (map (toHsIdent . fst) ps) <> " -> " <> emitExpr body <> ")"
emitExpr (EAwait e)        = emitExpr e  -- IO t in v0.1.2; await is a no-op wrapper
emitExpr (EDo steps)       = emitDo steps
emitExpr (EHole hk)        = emitHole hk

emitLet :: [(Name, Maybe Type, Expr)] -> Expr -> Text
emitLet bs body =
  "(let { "
  <> T.intercalate "; " (map (\(n,_,e) -> toHsIdent n <> " = " <> emitExpr e) bs)
  <> " } in " <> emitExpr body <> ")"

emitApp :: Name -> [Expr] -> Text
emitApp "first"  [a] = "(fst " <> emitExpr a <> ")"
emitApp "second" [a] = "(snd " <> emitExpr a <> ")"
emitApp "pair"   [a,b] = "(" <> emitExpr a <> ", " <> emitExpr b <> ")"
-- B3 fix: operators used as app fn names (kind:app, fn:"/") must be routed to
-- emitOp, otherwise we emit `(/ (i) (width))` which GHC parses as a section.
emitApp op args
  | op `elem` ["/", "mod", "%", "+", "-", "*", "=", "!=",
               "<", ">", "<=", ">=", "and", "or", "not"]
  = emitOp op args
emitApp func args =
  "(" <> toHsIdent func <> " " <> T.unwords (map (\a -> "(" <> emitExpr a <> ")") args) <> ")"


emitOp :: Name -> [Expr] -> Text
emitOp "="   [a,b] = "(" <> emitExpr a <> " == " <> emitExpr b <> ")"
emitOp "!="  [a,b] = "(" <> emitExpr a <> " /= " <> emitExpr b <> ")"
emitOp "and" [a,b] = "(" <> emitExpr a <> " && " <> emitExpr b <> ")"
emitOp "or"  [a,b] = "(" <> emitExpr a <> " || " <> emitExpr b <> ")"
emitOp "not" [a]   = "(not " <> emitExpr a <> ")"
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

emitDo :: [DoStep] -> Text
emitDo steps =
  "(do { " <> T.intercalate "; " (map emitStep steps) <> " })"
  where
    emitStep (DoBind n e) = toHsIdent n <> " <- " <> emitExpr e
    emitStep (DoExpr e)   = emitExpr e

emitHole :: HoleKind -> Text
emitHole (HNamed n)        = "( error (\"hole: \" ++ " <> T.pack (show (T.unpack n)) <> ") {- HOLE -} )"
emitHole (HDelegate spec)  = "( error (\"delegate: \" ++ " <> T.pack (show (T.unpack (delegateAgent spec))) <> ") )"
emitHole (HDelegateAsync s)= "( error (\"delegate-async: \" ++ " <> T.pack (show (T.unpack (delegateAgent s))) <> ") )"
emitHole (HDelegatePending _) = "( error \"delegate-pending: blocking hole\" )"
-- D3: proof-required holes compile to an explicit error stub — the LH pipeline validates this site
emitHole (HProofRequired r) = "( error \"PROOF REQUIRED [" <> r <> "]: add LiquidHaskell annotation\" )"
emitHole _                 = "( error \"unresolved hole\" )"

-- ---------------------------------------------------------------------------
-- Pattern emitter
-- ---------------------------------------------------------------------------

emitPat :: Pattern -> Text
emitPat PWildcard             = "_"
emitPat (PVar n)              = toHsIdent n
emitPat (PLiteral lit)        = emitLit lit
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
emitLit (LitInt n)    = "(" <> T.pack (show n) <> " :: Int)"  -- B2: monomorphise to Int (LLMLL int = Haskell Int)
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
toHsType TInt              = "Int"
toHsType TFloat            = "Double"
toHsType TString           = "String"
toHsType TBool             = "Bool"
toHsType TUnit             = "()"
toHsType (TBytes _)        = "[Word8]"
toHsType (TList t)         = "[" <> toHsType t <> "]"
toHsType (TMap k v)        = "(Map.Map " <> toHsType k <> " " <> toHsType v <> ")"
toHsType (TResult t e)     = "(Either " <> toHsType e <> " " <> toHsType t <> ")"
toHsType (TPromise t)      = "(IO " <> toHsType t <> ")"
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
      , "import System.IO (hSetBuffering, BufferMode(..), hIsEOF, stdin, stdout)"
      , ""
      ] ++ emitMainBody modName dm

emitMainBody :: Text -> Statement -> [Text]
emitMainBody _ SDefMain{defMainMode = ModeConsole, defMainStep = step, defMainInit = mInit, defMainDone = mDone, defMainOnDone = mOnDone} =
  [ "main :: IO ()"
  , "main = do"
  , "  hSetBuffering stdin LineBuffering"
  , "  hSetBuffering stdout NoBuffering"
  , initBlock
  , "  loop state0"
  , "  where"
  , "    loop s = do"
  ] ++ doneLines
  where
    -- init returns (state, IO ()) pair — destructure and execute the command
    initBlock = case mInit of
      Nothing -> "  let state0 = ()"
      Just e  -> "  let (state0, initCmd) = " <> emitExpr e <> "\n  initCmd"
    stepCall (EVar n) = toHsIdent n
    stepCall e        = "(\\ s l -> " <> emitExpr e <> " s l)"
    -- The inner loop body (eof check + step call).
    -- 'ind' is the indentation prefix:
    --   6 spaces ("      ") when there is no :done? guard (body sits directly in `do`)
    --   8 spaces ("        ") when the body must sit inside an `else do` branch
    loopBody ind =
      [ ind <> "eof <- hIsEOF stdin"
      , ind <> "if eof then return () else do"
      , ind <> "  line <- getLine"
      , ind <> "  let (s', cmd) = " <> stepCall step <> " s line"
      , ind <> "  cmd"
      , ind <> "  loop s'"
      ]
    -- Check done? at the TOP of the loop, before blocking on stdin.
    -- When :done? is absent the body is at 6-space indent (same level as `do`).
    -- When :done? is present the guard ends with `else do` and the body must be
    -- indented 2 extra spaces (8 total) to sit inside that branch.
    -- Fixing this resolves the GHC-82311 "empty do block" error in S-expression
    -- console programs. The JSON-AST path took the (Nothing,_) branch and was
    -- never affected.
    doneLines = case (mDone, mOnDone) of
      (Nothing, _) ->
          "      let _done = False"   -- placeholder; never triggers
        : loopBody "      "
      (Just e, Nothing) ->
          ("      if " <> emitExpr e <> " s then return () else do")
        : loopBody "        "
      (Just e, Just od) ->
          ("      if " <> emitExpr e <> " s then " <> emitExpr od <> " s else do")
        : loopBody "        "

emitMainBody _ SDefMain{defMainMode = ModeCli, defMainStep = step} =
  [ "main :: IO ()"
  , "main = do"
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

emitPackageYaml :: Text -> Bool -> [Text] -> Text
emitPackageYaml modName hasMain hackagePkgs = T.unlines $
  [ "name: " <> modName
  , "version: 0.1.0"
  , "dependencies:"
  , "  - base >= 4.14"
  , "  - containers"
  , "  - QuickCheck"
  ] ++
  map (\p -> "  - " <> p) (hackagePkgNames hackagePkgs) ++
  [ ""
  , "library:"
  , "  source-dirs: src"
  , "  exposed-modules: [Lib]"
  ] ++
  (if hasMain
    then [ ""
         , "executables:"
         , "  " <> modName <> ":"
         , "    main: Main.hs"
         , "    source-dirs: src"
         , "    dependencies:"
         , "      - " <> modName
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

stmtWarnings :: Statement -> [Text]
stmtWarnings _ = []
