{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.HubQuery
-- Description : Query-by-signature: find hub modules exporting functions
--               that match a given type signature pattern.
--
-- v0.6.1 HUB-1..HUB-3
--
-- Semantics (per Language Team specification):
--   * TDependent is stripped before matching.
--   * TVar in the query acts as a wildcard (matches any type).
--   * Structural matching is order-sensitive.
--   * TPair normalization is applied via the parser.
--   * Brute-force scan of ~/.llmll/modules/ (no index).
module LLMLL.HubQuery
  ( -- * Core
    QueryResult(..)
  , queryBySignature
  , structuralMatch
    -- * Scanning
  , scanHubModules
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.ByteString.Lazy as BL
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe, catMaybes)
import System.Directory
  ( getHomeDirectory, doesDirectoryExist, doesFileExist
  , listDirectory )
import System.FilePath ((</>), takeExtension)

import LLMLL.Syntax
import qualified LLMLL.ParserJSON as PJ
import qualified LLMLL.Parser    as P

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A single query match result.
data QueryResult = QueryResult
  { qrModulePath :: Text        -- ^ dotted module path (e.g. "llmll-crypto.hash")
  , qrFuncName   :: Name        -- ^ function name
  , qrSignature  :: Text        -- ^ rendered type signature
  , qrHasContract :: Bool       -- ^ True if the function has a pre or post contract
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Structural type matching
-- ---------------------------------------------------------------------------

-- | Structural type matching with wildcard TVar support.
--
-- Rules:
--   1. TVar _ in the query matches any type.
--   2. TVar _ in the candidate also matches any type (both directions).
--   3. TDependent is stripped (match on the base type).
--   4. Matching is order-sensitive for TFn parameters.
structuralMatch :: Type -> Type -> Bool
-- TVar is a wildcard in both positions
structuralMatch (TVar _) _ = True
structuralMatch _ (TVar _) = True
-- Strip TDependent from both sides
structuralMatch (TDependent _ a _) b = structuralMatch a b
structuralMatch a (TDependent _ b _) = structuralMatch a b
-- Recursive structural cases
structuralMatch (TFn as r) (TFn bs s) =
  length as == length bs
  && all (uncurry structuralMatch) (zip as bs)
  && structuralMatch r s
structuralMatch (TList a) (TList b) = structuralMatch a b
structuralMatch (TMap k1 v1) (TMap k2 v2) =
  structuralMatch k1 k2 && structuralMatch v1 v2
structuralMatch (TResult a b) (TResult c d) =
  structuralMatch a c && structuralMatch b d
structuralMatch (TPair a b) (TPair c d) =
  structuralMatch a c && structuralMatch b d
structuralMatch (TPromise a) (TPromise b) = structuralMatch a b
structuralMatch (TBytes m) (TBytes n) = m == n
-- Base cases: exact equality
structuralMatch a b = a == b

-- ---------------------------------------------------------------------------
-- Hub scanning
-- ---------------------------------------------------------------------------

-- | Scan ~/.llmll/modules/ for all .ast.json and .llmll files,
-- returning (module path, [(funcName, funcType, hasContract)]).
scanHubModules :: IO [(Text, [(Name, Type, Bool)])]
scanHubModules = do
  root <- hubRoot
  exists <- doesDirectoryExist root
  if not exists
    then pure []
    else walkDir root root

-- | Hub cache root.
hubRoot :: IO FilePath
hubRoot = do
  home <- getHomeDirectory
  pure (home </> ".llmll" </> "modules")

-- | Recursively walk directories, parsing source files.
walkDir :: FilePath -> FilePath -> IO [(Text, [(Name, Type, Bool)])]
walkDir root dir = do
  entries <- listDirectory dir
  results <- mapM (processEntry root dir) entries
  pure (concat results)

processEntry :: FilePath -> FilePath -> FilePath -> IO [(Text, [(Name, Type, Bool)])]
processEntry root dir entry = do
  let full = dir </> entry
  isDir <- doesDirectoryExist full
  if isDir
    then walkDir root full
    else do
      let ext = takeExtension full
      if ext `elem` [".json", ".llmll"]
        then do
          mFuncs <- parseModuleFunctions full
          case mFuncs of
            [] -> pure []
            fs -> do
              let modPath = fileToModulePath root full
              pure [(modPath, fs)]
        else pure []

-- | Parse a source file and extract top-level function signatures.
parseModuleFunctions :: FilePath -> IO [(Name, Type, Bool)]
parseModuleFunctions fp
  | takeExtension fp == ".json" = do
      bs <- BL.readFile fp
      case PJ.parseJSONAST fp bs of
        Left _      -> pure []
        Right stmts -> pure (extractFunctions stmts)
  | otherwise = do
      src <- TIO.readFile fp
      case P.parseTopLevel fp src of
        Left _      -> pure []
        Right stmts -> pure (extractFunctions stmts)

-- | Extract (name, type, hasContract) from def-logic/letrec statements.
extractFunctions :: [Statement] -> [(Name, Type, Bool)]
extractFunctions = mapMaybe go
  where
    go (SDefLogic name params mRet contract _) =
      let retType   = maybe (TVar "?") id mRet
          funcType  = TFn (map snd params) retType
          hasCon    = contractPre contract /= Nothing || contractPost contract /= Nothing
      in Just (name, funcType, hasCon)
    go (SLetrec name params mRet contract _ _) =
      let retType   = maybe (TVar "?") id mRet
          funcType  = TFn (map snd params) retType
          hasCon    = contractPre contract /= Nothing || contractPost contract /= Nothing
      in Just (name, funcType, hasCon)
    go _ = Nothing

-- | Compute a dotted module path from the hub root and file path.
-- e.g. ~/.llmll/modules/crypto/hash/sha256.ast.json → "crypto.hash.sha256"
fileToModulePath :: FilePath -> FilePath -> Text
fileToModulePath root fp =
  let relative = drop (length root + 1) fp  -- strip root + separator
      -- Strip extension(s)
      stripped = stripExts relative
      -- Replace path separators with dots
  in T.intercalate "." (T.splitOn "/" (T.pack stripped))
  where
    stripExts s
      | ".ast.json" `isSuffixOf` s = take (length s - 9) s
      | ".llmll" `isSuffixOf` s    = take (length s - 6) s
      | ".json" `isSuffixOf` s     = take (length s - 5) s
      | otherwise                  = s
    isSuffixOf suffix str = drop (length str - length suffix) str == suffix

-- ---------------------------------------------------------------------------
-- Query execution
-- ---------------------------------------------------------------------------

-- | Query the hub cache for functions matching a given type signature.
-- Brute-force: scans all modules, tries structuralMatch against each
-- exported function's type.
queryBySignature :: Type -> IO [QueryResult]
queryBySignature queryType = do
  modules <- scanHubModules
  pure $ concatMap (matchModule queryType) modules

matchModule :: Type -> (Text, [(Name, Type, Bool)]) -> [QueryResult]
matchModule queryType (modPath, funcs) =
  [ QueryResult
      { qrModulePath  = modPath
      , qrFuncName    = name
      , qrSignature   = typeLabel funcType
      , qrHasContract = hasCon
      }
  | (name, funcType, hasCon) <- funcs
  , structuralMatch queryType funcType
  ]
