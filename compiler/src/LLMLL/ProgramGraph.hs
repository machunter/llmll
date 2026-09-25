{-# LANGUAGE OverloadedStrings #-}
-- | HEADLINE-TERM-1 + STRICT-XMOD-1: the whole-program call graph with
-- module-qualified node names, and the caller closures read by the 'verify'
-- headline, the '--json' fields, '--strict-verified-core' and the trust report.
--
-- Why a second graph. 'TrustReport.cyclicSccMembers' keys nodes by BARE name
-- across modules, so two modules that each define @go@ collapse into one node,
-- and 'refutedClosure' walks trust ENTRIES, which exist only for contracted
-- functions, so a path through an uncontracted helper is cut. Both are fine for
-- what they were built for. A closure that decides whether the headline may
-- print a check mark needs neither weakness.
--
-- Naming. Entry-module functions keep their bare name, matching
-- 'erBodyFaithfulFns' and the entry's trust entries. A function of cached
-- module @a.b@ is @a.b.f@, matching 'buildModuleEntries'.
--
-- Resolution of a call name inside a module, in order: a function defined in
-- that module; a qualified @m.f@ naming a cached module that defines @f@; a bare
-- name through each of that module's 'SOpen' statements. The last step keeps
-- EVERY opened module that defines the name: the type checker has no
-- ambiguity rule for opens, and an extra edge can only add a warning, never
-- hide one. Names that resolve to nothing (builtins, let-bound lambdas) add no
-- edge.
module LLMLL.ProgramGraph
  ( qualifiedCallGraph
  , undischargedCycleMembers
  , cachedDischargedFns
  , importUnprovedFns
  , callerClosure
  ) where

import Data.Graph (stronglyConnComp, SCC(..))
import Data.List (foldl', nub, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.HoleAnalysis (buildCallGraph)
import LLMLL.TrustReport (downgradeStaleVerifiedSidecar, positiveTier)

-- | Every function of the program (entry plus cached modules) mapped to the
-- functions it calls, all names qualified as described in the module header.
qualifiedCallGraph :: ModuleCache -> [Statement] -> Map Name [Name]
qualifiedCallGraph cache entryStmts =
  Map.unions (graphFor "" entryStmts
               : [ graphFor (prefixOf p) (meStatements m) | (p, m) <- Map.toList cache ])
  where
    modDefs :: Map Text (Set Name)
    modDefs = Map.fromList
      [ (prefixOf p, Map.keysSet (buildCallGraph (meStatements m)))
      | (p, m) <- Map.toList cache ]

    graphFor :: Text -> [Statement] -> Map Name [Name]
    graphFor prefix stmts =
      let cg     = buildCallGraph stmts
          locals = Map.keysSet cg
          opens  = [ (prefixOf op, mNames) | SOpen op mNames <- stmts ]
          resolve n
            | Set.member n locals = [prefix <> n]
            | otherwise           = qualified n ++ opened n
          qualified n = case T.breakOnEnd "." n of
            ("", _)     -> []
            (pre, base) -> [ pre <> base
                           | Just ds <- [Map.lookup pre modDefs]
                           , Set.member base ds ]
          opened n =
            [ op <> n
            | (op, mNames) <- opens
            , maybe True (n `elem`) mNames
            , Just ds <- [Map.lookup op modDefs]
            , Set.member n ds ]
      in Map.fromList
           [ (prefix <> f, nub (concatMap resolve calls)) | (f, calls) <- Map.toList cg ]

prefixOf :: ModulePath -> Text
prefixOf p = T.intercalate "." p <> "."

-- | Members of a cyclic strongly connected component (a self-call counts),
-- minus the descent-discharged set. These are the functions whose proof holds
-- only if they terminate.
undischargedCycleMembers :: Map Name [Name] -> Set Name -> Set Name
undischargedCycleMembers g discharged =
  Set.fromList
    [ n
    | CyclicSCC ns <- stronglyConnComp [ (n, n, ds) | (n, ds) <- Map.toList g ]
    , n <- ns
    , Set.notMember n discharged ]

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

-- | Reflexive caller closure of a target set. Each function that reaches a
-- target maps to the nearest one it reaches (a target maps to itself). The
-- walk starts from the targets in ascending order, so the result is
-- deterministic.
callerClosure :: Map Name [Name] -> Set Name -> Map Name Name
callerClosure g targets = go (Map.fromList [ (t, t) | t <- Set.toAscList targets ])
                             (Set.toAscList targets)
  where
    callers :: Map Name [Name]
    callers = Map.map sort $ Map.fromListWith (++)
      [ (callee, [caller]) | (caller, callees) <- Map.toList g, callee <- callees ]
    go acc []       = acc
    go acc frontier =
      let step (a, next) n =
            let via = a Map.! n
                new = [ c | c <- Map.findWithDefault [] n callers, Map.notMember c a ]
            in (foldl' (\m c -> Map.insert c via m) a new, next ++ new)
          (acc', next') = foldl' step (acc, []) frontier
      in go acc' (nub next')
