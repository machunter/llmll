{-# LANGUAGE OverloadedStrings #-}
-- | HEADLINE-TERM-1 + STRICT-XMOD-1 + PARTIAL-FNS-GRAPH-1: the whole-program
-- call graph with module-qualified node names.
--
-- Why a separate module. 'LLMLL.ProgramGraph' reads sidecar evidence through
-- 'LLMLL.TrustReport', so 'TrustReport' could not import the graph from there.
-- The graph itself needs only the syntax, so it lives here and both modules
-- import it. 'ProgramGraph' re-exports these names for its existing callers.
--
-- Naming. Entry-module functions keep their bare name, matching
-- 'erBodyFaithfulFns' and the entry's trust entries. A function of cached
-- module @a.b@ is @a.b.f@, matching 'buildModuleEntries'.
--
-- Resolution of a name inside a module, in order: a function defined in that
-- module; a qualified @m.f@ naming a cached module that defines @f@; a bare
-- name through each of that module's 'SOpen' statements. The last step keeps
-- EVERY opened module that defines the name: the type checker has no
-- ambiguity rule for opens, and an extra edge can only add a warning, never
-- hide one. Names that resolve to nothing (builtins, let-bound lambdas) add no
-- edge.
--
-- Edges. A call adds an edge ('HoleAnalysis.extractCalls'). So does a
-- function used as a value, as in @(list-fold xs acc g)@, when no binder in
-- scope shadows the name ('extractRefs', PARTIAL-FNS-GRAPH-1). A reference is
-- not a call, so the second kind over-approximates; that only adds a
-- termination disclosure, never removes one.
module LLMLL.CallGraph
  ( qualifiedCallGraph
  , extractRefs
  , undischargedCycleMembers
  , callerClosure
  ) where

import Data.Graph (stronglyConnComp, SCC(..))
import Data.List (foldl', nub, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Syntax
import LLMLL.HoleAnalysis (extractCalls)

-- | Every function of the program (entry plus cached modules) mapped to the
-- functions it calls or uses as a value, all names qualified as described in
-- the module header.
qualifiedCallGraph :: ModuleCache -> [Statement] -> Map Name [Name]
qualifiedCallGraph cache entryStmts =
  Map.unions (graphFor "" entryStmts
               : [ graphFor (prefixOf p) (meStatements m) | (p, m) <- Map.toList cache ])
  where
    modDefs :: Map Text (Set Name)
    modDefs = Map.fromList
      [ (prefixOf p, Set.fromList [ n | (n, _, _) <- defsOf (meStatements m) ])
      | (p, m) <- Map.toList cache ]

    graphFor :: Text -> [Statement] -> Map Name [Name]
    graphFor prefix stmts =
      let defs   = defsOf stmts
          locals = Set.fromList [ n | (n, _, _) <- defs ]
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
           [ (prefix <> f, nub (concatMap resolve (extractCalls body ++ extractRefs ps body)))
           | (f, ps, body) <- defs ]

-- | The function definitions of a module: name, parameter names, body. The
-- same statement forms 'HoleAnalysis.buildCallGraph' keys.
defsOf :: [Statement] -> [(Name, [Name], Expr)]
defsOf = mapMaybe go
  where
    go (SLetrec n ps _ _ _ b) = Just (n, map fst ps, b)
    go s = (\(n, ps, _, _, b) -> (n, map fst ps, b)) <$> normalizeDefStmt s

prefixOf :: ModulePath -> Text
prefixOf p = T.intercalate "." p <> "."

-- | PARTIAL-FNS-GRAPH-1: the names a body uses as VALUES (an 'EVar' that no
-- parameter, @let@, lambda, @match@ or @do@ binder in scope shadows). The
-- caller resolves them, so a local variable that is not a function adds no
-- edge. A @let@ binding sees only the binders before it; a @do@ step sees the
-- names bound by the steps before it.
extractRefs :: [Name] -> Expr -> [Name]
extractRefs params = go (Set.fromList params)
  where
    go bound expr = case expr of
      EVar n
        | Set.member n bound -> []
        | otherwise          -> [n]
      ELit _          -> []
      EHole _         -> []
      EApp _ args     -> concatMap (go bound) args
      EOp _ args      -> concatMap (go bound) args
      EIf c t e       -> go bound c ++ go bound t ++ go bound e
      EPair a b       -> go bound a ++ go bound b
      EAwait e        -> go bound e
      ELambda ps body -> go (Set.union bound (Set.fromList (map fst ps))) body
      EMatch s arms   -> go bound s
                         ++ concat [ go (Set.union bound (patVars p)) b | (p, b) <- arms ]
      ELet binds body ->
        let step (acc, b) (p, _, e) = (acc ++ go b e, Set.union b (patVars p))
            (inBinds, bound') = foldl' step ([], bound) binds
        in inBinds ++ go bound' body
      EDo steps ->
        let step (acc, b) (DoStep mn e _) = (acc ++ go b e, maybe b (`Set.insert` b) mn)
        in fst (foldl' step ([], bound) steps)

    patVars :: Pattern -> Set Name
    patVars (PVar n)            = Set.singleton n
    patVars (PConstructor _ ps) = Set.unions (map patVars ps)
    patVars _                   = Set.empty

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
