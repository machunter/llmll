{-# LANGUAGE OverloadedStrings #-}
-- | HEADLINE-TERM-1 + STRICT-XMOD-1: the whole-program call graph with
-- module-qualified node names, and the caller closures read by the 'verify'
-- headline, the '--json' fields, '--strict-verified-core' and the trust report.
--
-- The graph itself ('qualifiedCallGraph', 'undischargedCycleMembers',
-- 'callerClosure') lives in 'LLMLL.CallGraph' and is re-exported here, so the
-- trust report can import it without an import cycle (PARTIAL-FNS-GRAPH-1).
-- This module keeps the two functions that read sidecar evidence through
-- 'LLMLL.TrustReport'.
module LLMLL.ProgramGraph
  ( qualifiedCallGraph
  , undischargedCycleMembers
  , cachedDischargedFns
  , importUnprovedFns
  , callerClosure
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.CallGraph (qualifiedCallGraph, undischargedCycleMembers, callerClosure)
import LLMLL.TrustReport (downgradeStaleVerifiedSidecar, positiveTier)

prefixOf :: ModulePath -> Text
prefixOf p = T.intercalate "." p <> "."

-- | Descent-discharged functions of the cached modules, qualified. Read from
-- each module's sidecar AFTER the staleness gate, so an edited body does not
-- keep a total-correctness claim its sidecar no longer backs.
cachedDischargedFns :: ModuleCache -> Set Name
cachedDischargedFns cache = Set.unions
  [ Set.fromList
      [ prefixOf p <> f
      | (f, cs) <- Map.toList (validated m)
      , Just er <- [csPost cs]
      , positiveTier (erDisplayLevel er)
      , erTerminationVerified er ]
  | (p, m) <- Map.toList cache ]

-- | Contracted functions of the cached modules whose post is not proved
-- (asserted or tested), qualified. The staleness gate applies, so a missing
-- sidecar and an edited body both land here.
importUnprovedFns :: ModuleCache -> Set Name
importUnprovedFns cache = Set.unions
  [ Set.fromList
      [ prefixOf p <> f
      | (f, cs) <- Map.toList (validated m)
      , Just er <- [csPost cs]
      , not (positiveTier (erDisplayLevel er)) ]
  | (p, m) <- Map.toList cache ]

validated :: ModuleEnv -> Map Name ContractStatus
validated m = fst (downgradeStaleVerifiedSidecar (meStatements m) (meContractStatus m))
