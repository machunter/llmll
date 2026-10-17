-- |
-- Module      : LLMLL.LoadClosure
-- Description : Load the module closure a source file imports, for any caller.
--
-- XMOD-RUN-LOAD-1. 'Main.loadStatementsMulti' was the only place that turned
-- a file's @(import …)@ statements into a 'ModuleCache', so the commands that
-- did not call it (run, patch, refine) checked a multi-module program with an
-- empty cache: a call to @lib.f@ was "unknown", and patch accepted a fill that
-- `check` then rejected. This module holds that step so a library caller
-- ('LLMLL.PatchApply') can use it too.
--
-- It lives here and not in 'LLMLL.Module' because it applies
-- 'TrustReport.checkCacheEvidence', and TrustReport imports Module.
module LLMLL.LoadClosure
  ( loadImportClosure
  , sourceRoot
  ) where

import Control.Monad (foldM)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic)
import LLMLL.Module (loadModule, isBuiltinImport)
import LLMLL.BuildScope (closureOf, resolveQualifiedTypes)
import LLMLL.TrustReport (checkCacheEvidence)

-- | The directory imports resolve against: the entry file's directory, or ""
-- for a bare file name (the spelling 'Main.loadStatementsMulti' has used).
sourceRoot :: FilePath -> FilePath
sourceRoot = reverse . dropWhile (\c -> c /= '/' && c /= '\\') . drop 1 . reverse

-- | Load every user module the statements import (a @wasi.*@ import is a host
-- capability and is skipped), apply the evidence-key read check to the cache,
-- and resolve qualified type names in the statements against the closure.
-- Answers the statements, the cache and the load order, or the load
-- diagnostics. Prints nothing.
loadImportClosure
  :: GrammarMode -> FilePath -> [Statement]
  -> IO (Either [Diagnostic] ([Statement], ModuleCache, [ModulePath]))
loadImportClosure gm fp stmts = do
  let imports = [imp | SImport imp <- stmts]
      srcRoot = sourceRoot fp
  result <- foldM (loadOne srcRoot) (Right (Map.empty, [])) imports
  pure $ case result of
    Left diags -> Left diags
    Right (cache0, loadOrder) ->
      let cache = checkCacheEvidence cache0
      in Right (resolveQualifiedTypes stmts (closureOf stmts cache), cache, loadOrder)
  where
    loadOne _ (Left e) _ = pure (Left e)
    loadOne srcRoot (Right (c, ord)) imp = do
      let path = T.splitOn "." (importPath imp)
      if isBuiltinImport path
        then pure (Right (c, ord))
        else do
          res <- loadModule gm False srcRoot [] c [] path
          pure $ case res of
            Left diags        -> Left diags
            Right (c', o', _) -> Right (c', ord ++ o')
