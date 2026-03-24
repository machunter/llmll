-- |
-- Module      : LLMLL.Module
-- Description : Phase 2a multi-file module loader, DFS resolver, and ModuleEnv builder.
--
-- Provides:
--   * resolveModulePath   — turn a ModulePath into a FilePath on disk
--   * loadModule          — DFS-based loader with cycle detection and caching
--   * buildModuleEnv      — construct a ModuleEnv from parsed + type-checked data
--   * mergeModuleEnvs     — seed a TypeEnv from a set of ModuleEnvs (qualified names)
--   * checkInterfaceMismatch — cross-module structural interface verification
--
-- The single-file path in Main.hs is unaffected: it calls typeCheck with an
-- empty ModuleCache, which routes through the existing code unchanged.
module LLMLL.Module
  ( resolveModulePath
  , loadModule
  , buildModuleEnv
  , mergeModuleEnvs
  , checkInterfaceMismatch
  ) where

-- All imports must be at the top in Haskell (no inline imports).
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Maybe (mapMaybe, fromMaybe)
import System.FilePath ((</>), (<.>), takeExtension)
import System.Directory (doesFileExist, getHomeDirectory)
import Control.Monad (foldM)
import qualified Data.ByteString.Lazy as BL

import LLMLL.Syntax
import LLMLL.Diagnostic
import LLMLL.TypeCheck (typeCheck, emptyEnv, TypeEnv)
import qualified LLMLL.Parser    as P
import qualified LLMLL.ParserJSON as PJ

-- ---------------------------------------------------------------------------
-- Module path utilities
-- ---------------------------------------------------------------------------

-- | Convert a ModulePath to the relative file path stem.
-- ["foo","bar","baz"] -> "foo/bar/baz"
pathToRelFile :: ModulePath -> FilePath
pathToRelFile []     = ""
pathToRelFile [x]    = T.unpack x
pathToRelFile (x:xs) = T.unpack x </> pathToRelFile xs

-- | Convert a ModulePath to a dotted Text for diagnostics.
pathToText :: ModulePath -> Text
pathToText = T.intercalate "."

-- | Split a dotted Text into a ModulePath.
splitDotted :: Text -> ModulePath
splitDotted = T.splitOn "."

-- ---------------------------------------------------------------------------
-- File-system resolution
-- ---------------------------------------------------------------------------

-- | Hub cache root: ~/.llmll/modules/
hubCacheRoot :: IO FilePath
hubCacheRoot = do
  home <- getHomeDirectory
  pure (home </> ".llmll" </> "modules")

-- | Resolve a ModulePath to a concrete FilePath.
--
-- Search order for (import foo.bar.baz):
--   1. <srcRoot>/foo/bar/baz.llmll
--   2. <srcRoot>/foo/bar/baz.ast.json
--   3. Same for each extra root in extraRoots
--   4. ~/.llmll/modules/foo/bar/baz.llmll   (hub cache)
--   5. ~/.llmll/modules/foo/bar/baz.ast.json
--
-- Hub imports (first segment == "hub") skip steps 1-3 and go straight to cache.
resolveModulePath :: FilePath      -- ^ source root (directory of entry-point file)
                  -> [FilePath]    -- ^ additional roots
                  -> ModulePath    -- ^ module path to resolve
                  -> IO (Maybe FilePath)
resolveModulePath srcRoot extraRoots modPath = do
  hubRoot <- hubCacheRoot
  case modPath of
    ("hub":rest) -> tryRoots [hubRoot] rest
    _            -> do
      found <- tryRoots (srcRoot : extraRoots) modPath
      case found of
        Just fp -> pure (Just fp)
        Nothing -> tryRoots [hubRoot] modPath
  where
    tryRoots [] _     = pure Nothing
    tryRoots (r:rs) p = do
      let stem       = r </> pathToRelFile p
          candidates = [stem <.> "llmll", stem <.> "ast.json"]
      found <- firstExisting candidates
      case found of
        Just fp -> pure (Just fp)
        Nothing -> tryRoots rs p

    firstExisting []     = pure Nothing
    firstExisting (f:fs) = doesFileExist f >>= \ex ->
      if ex then pure (Just f) else firstExisting fs

-- ---------------------------------------------------------------------------
-- Module loading (post-order DFS with cycle detection)
-- ---------------------------------------------------------------------------

type LoadResult = Either [Diagnostic] (ModuleCache, ModuleEnv)

-- | Load a module and all its transitive imports.
--
-- Algorithm (post-order DFS):
--   1. If path ∈ visitedStack → circular-import error.
--   2. If path ∈ cache → return memoised env.
--   3. Resolve file path → module-not-found if absent.
--   4. Parse file.
--   5. Recurse into each SImport (push path, pop after).
--   6. Type-check with imported envs seeded.
--   7. Build ModuleEnv + insert into cache.
loadModule :: Bool             -- ^ json mode
           -> FilePath         -- ^ source root (dir of entry file)
           -> [FilePath]       -- ^ extra roots
           -> ModuleCache      -- ^ already-loaded modules
           -> Set ModulePath   -- ^ DFS stack for cycle detection
           -> ModulePath       -- ^ module to load
           -> IO LoadResult
loadModule jsonMode srcRoot extraRoots cache0 visitedStack modPath
  | Set.member modPath visitedStack =
      let cycleList = map pathToText (Set.toList visitedStack) ++ [pathToText modPath]
      in pure $ Left [mkCircularImport cycleList]
  | Just env <- Map.lookup modPath cache0 =
      pure $ Right (cache0, env)
  | otherwise = do
      mFp <- resolveModulePath srcRoot extraRoots modPath
      case mFp of
        Nothing -> pure $ Left
          [ mkModuleNotFound (pathToText modPath) (srcRoot : extraRoots) ]
        Just fp -> loadFromFile jsonMode srcRoot extraRoots cache0 visitedStack modPath fp

loadFromFile :: Bool -> FilePath -> [FilePath] -> ModuleCache -> Set ModulePath
             -> ModulePath -> FilePath -> IO LoadResult
loadFromFile _jsonMode srcRoot extraRoots cache0 visitedStack modPath fp = do
  mStmts <- parseFile fp
  case mStmts of
    Left diag -> pure $ Left [diag]
    Right stmts -> do
      let imports  = [imp | SImport imp <- stmts]
          newStack = Set.insert modPath visitedStack
      result <- foldM (loadOneImport srcRoot extraRoots newStack) (Right cache0) imports
      case result of
        Left diags -> pure $ Left diags
        Right cache1 -> do
          let importedEnvs = mapMaybe
                (\imp -> Map.lookup (splitDotted (importPath imp)) cache1) imports
              baseEnv = mergeModuleEnvs importedEnvs emptyEnv
              report  = typeCheck baseEnv stmts
              env     = buildModuleEnv modPath stmts baseEnv
              cache2  = Map.insert modPath env cache1
              hardErrors = filter ((== SevError) . diagSeverity) (reportDiagnostics report)
          if null hardErrors
            then pure $ Right (cache2, env)
            else pure $ Left hardErrors

loadOneImport :: FilePath -> [FilePath] -> Set ModulePath
              -> Either [Diagnostic] ModuleCache
              -> Import
              -> IO (Either [Diagnostic] ModuleCache)
loadOneImport _       _          _     (Left diags) _   = pure (Left diags)
loadOneImport srcRoot extraRoots stack (Right cache) imp = do
  let path = splitDotted (importPath imp)
  result <- loadModule False srcRoot extraRoots cache stack path
  case result of
    Left diags     -> pure (Left diags)
    Right (c', _)  -> pure (Right c')

-- | Parse a file dispatching on extension (.llmll vs. .ast.json / .json).
parseFile :: FilePath -> IO (Either Diagnostic [Statement])
parseFile fp
  | ext == ".json" = do
      bs <- BL.readFile fp
      pure (PJ.parseJSONAST fp bs)
  | otherwise = do
      src <- TIO.readFile fp
      case P.parseTopLevel fp src of
        Left err    -> pure $ Left (megaparsecToDiagnostic fp err)
        Right stmts -> pure $ Right stmts
  where
    ext = takeExtension fp

-- ---------------------------------------------------------------------------
-- ModuleEnv construction
-- ---------------------------------------------------------------------------

-- | Build a ModuleEnv from a parsed statement list.
-- Applies export filtering if an SExport declaration is present.
-- check and def-invariant blocks are never exported.
buildModuleEnv :: ModulePath -> [Statement] -> TypeEnv -> ModuleEnv
buildModuleEnv path stmts _env =
  let aliasMap'  = Map.fromList [(n, b) | STypeDef n b <- stmts]
      allExports = Map.fromList $ mapMaybe toExport stmts
      ifaceMap   = Map.fromList
                     [(defInterfaceName s, defInterfaceFns s)
                      | s@SDefInterface{} <- stmts]
      mExportDecl = listToMaybe [ns | SExport ns <- stmts]
      filteredExports = case mExportDecl of
        Nothing -> allExports
        Just ns -> Map.filterWithKey (\k _ -> k `elem` ns) allExports
  in ModuleEnv
       { meExports    = filteredExports
       , meStatements = stmts
       , meInterfaces = ifaceMap
       , meAliasMap   = aliasMap'
       , mePath       = path
       }
  where
    toExport (SDefLogic name params mRet _ _) =
      let retType = fromMaybe (TVar "?") mRet
      in Just (name, TFn (map snd params) retType)
    toExport (SDefInterface name _) = Just (name, TCustom name)
    toExport (STypeDef name body)   = Just (name, body)
    toExport _                      = Nothing

listToMaybe :: [a] -> Maybe a
listToMaybe []    = Nothing
listToMaybe (x:_) = Just x

-- ---------------------------------------------------------------------------
-- TypeEnv seeding
-- ---------------------------------------------------------------------------

-- | Merge exported names from a list of ModuleEnvs into a base TypeEnv.
-- Each export is inserted with its fully-qualified name (module.path.name).
mergeModuleEnvs :: [ModuleEnv] -> TypeEnv -> TypeEnv
mergeModuleEnvs envs base = foldl insertEnv base envs
  where
    insertEnv acc menv =
      let prefix    = pathToText (mePath menv) <> "."
          qualified = Map.mapKeys (prefix <>) (meExports menv)
      in Map.union qualified acc

-- ---------------------------------------------------------------------------
-- Cross-module def-interface enforcement
-- ---------------------------------------------------------------------------

-- | Compare an expected def-interface shape against what a module exports.
checkInterfaceMismatch :: ModulePath
                       -> Text
                       -> [(Name, Type)]
                       -> ModuleEnv
                       -> [Diagnostic]
checkInterfaceMismatch importerPath ifaceName expected implEnv =
  concatMap (checkMethod implPath) expected
  where
    implPath = T.intercalate "/" importerPath
    checkMethod ptr (methodName, expectedTy) =
      case Map.lookup methodName (meExports implEnv) of
        Nothing ->
          [ mkInterfaceMismatch
              (pathToText importerPath) ifaceName methodName
              (typeLabel expectedTy) "(not exported)"
              ("/import/" <> ptr) ]
        Just actualTy ->
          if compatibleTy expectedTy actualTy
            then []
            else [ mkInterfaceMismatch
                     (pathToText importerPath) ifaceName methodName
                     (typeLabel expectedTy) (typeLabel actualTy)
                     ("/import/" <> ptr) ]

-- | Structural type compatibility (mirrors TypeCheck.compatibleWith).
compatibleTy :: Type -> Type -> Bool
compatibleTy (TVar _) _                = True
compatibleTy _ (TVar _)                = True
compatibleTy (TCustom "_") _           = True
compatibleTy _ (TCustom "_")           = True
compatibleTy (TCustom a) (TCustom b)   = a == b
compatibleTy (TDependent _ a _) b      = compatibleTy a b
compatibleTy a (TDependent _ b _)      = compatibleTy a b
compatibleTy (TList a) (TList b)       = compatibleTy a b
compatibleTy (TMap k1 v1) (TMap k2 v2) = compatibleTy k1 k2 && compatibleTy v1 v2
compatibleTy (TResult a b) (TResult c d) = compatibleTy a c && compatibleTy b d
compatibleTy (TPromise a) (TPromise b) = compatibleTy a b
compatibleTy (TFn as r) (TFn bs s)    =
  length as == length bs
  && all (uncurry compatibleTy) (zip as bs)
  && compatibleTy r s
compatibleTy (TBytes m) (TBytes n)     = m == n
compatibleTy a b                       = a == b
