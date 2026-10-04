-- |
-- Module      : LLMLL.EvidenceKey
-- Description : HASH-PRE-ASYM: the key a persisted verdict is checked against.
--
-- A @.verified.json@ record is read back without running the solver: by
-- @--trust-report@, by the admission check for a @def@, and by every importer.
-- The key decides whether the record still describes a proof. Before
-- HASH-PRE-ASYM it covered the def's own text only, so a caller kept
-- @verified@ after a callee's contract changed (measured on v0.27.1:
-- docs/design/hash-pre-asym-witness.md).
--
-- The key now covers everything the def's proof read, built from the same
-- 'KeyEnv' the emitter takes its inputs from
-- (docs/design/hash-pre-asym-proposal.md Rev 3, S1 and §3.2):
--
--   * the def's form, body, effective pre and post, and measures;
--   * the declarations of the types in its signature;
--   * for each contracted function its body names (called or passed as a
--     value): its resolved name, parameter types, effective pre and post,
--     effective return type, measures, and the declarations of those types;
--   * the RESP-FACT refinement seeded for it, if any;
--   * for a record that claims termination, its recursion group (the sorted
--     members and their measures). A record that claims no termination does not
--     fold the group, so a post's key never depends on it.
--
-- A callee's body is not read, except through its effective return type when it
-- declares none ('keCenv' carries 'effRet').
--
-- Every site that writes or checks a key calls 'evidenceKey', with the 'KeyEnv'
-- of the module the record belongs to.
module LLMLL.EvidenceKey
  ( evidenceKey
  , evidenceKeys
  , moduleKeyEnv
  , restrictCache
  ) where

import Data.Graph (SCC(..), stronglyConnComp)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Maybe (mapMaybe, maybeToList)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.BuildScope (closureOf)
import LLMLL.FixpointEmit (KeyEnv(..), augmentContractPost, augmentContractPre, buildKeyEnv)
import LLMLL.PBT (canonicalDefEvidenceHashWith, canonicalExpr)
import LLMLL.Syntax

-- | The evidence key of one definition. The flag says whether the record being
-- written or checked claims termination; only such a record folds the
-- recursion group. 'Nothing' for a statement that is not a definition.
evidenceKey :: KeyEnv -> Bool -> Statement -> Maybe (Name, Text)
evidenceKey ke withTerm s = do
  (n, params, mRet, c, body) <- normalizeDefStmt s
  let am   = keAliases ke
      cEff = augmentContractPost am mRet (augmentContractPre am params c)
      decs = case s of SDefShell _ _ _ _ _ d -> d; _ -> []
  pure ( n
       , canonicalDefEvidenceHashWith (depsFragment ke withTerm n params mRet body)
           (defFormTag s) body (contractPre cEff) (contractPost cEff) decs )

-- | The 'KeyEnv' an imported module's records were written with: its own
-- statements over its own transitive imports, with its recorded return types.
-- Reading a record with an importer's wider cache would let a local name that
-- collides with an unrelated module's function enter the key.
moduleKeyEnv :: ModuleCache -> ModuleEnv -> KeyEnv
moduleKeyEnv cache m =
  buildKeyEnv (restrictCache (meStatements m) cache) (meRetTypes m) (meStatements m)

-- | The part of a cache a module's statements reach through their imports,
-- transitively. Imports with no cached module (the @wasi.*@ namespaces) drop out.
-- XMOD-SCOPE: the walk moved to 'LLMLL.BuildScope.closureOf', which R1 also
-- uses; this name stays so its callers do not change.
restrictCache :: [Statement] -> ModuleCache -> ModuleCache
restrictCache = closureOf

-- | 'evidenceKey' for every definition of a module.
evidenceKeys :: KeyEnv -> Bool -> [Statement] -> Map Name Text
evidenceKeys ke withTerm = Map.fromList . mapMaybe (evidenceKey ke withTerm)

depsFragment :: KeyEnv -> Bool -> Name -> [(Name, Type)] -> Maybe Type -> Expr -> Text
depsFragment ke withTerm n params mRet body =
  T.unwords (filter (not . T.null) [ownTypes, callees, resp, group])
  where
    am   = keAliases ke
    cenv = keCenv ke

    ownTypes = typeDeclsText am (map snd params ++ maybeToList mRet)

    calleeNames = sort [ f | f <- Set.toList (exprNames body), f /= n, Map.member f cenv ]
    callees = T.unwords (mapMaybe calleeText calleeNames)
    calleeText f = do
      (ps, cc, mr) <- Map.lookup f cenv
      let tys = typeDeclsText am (map snd ps ++ maybeToList mr)
      pure $ "(callee " <> f
          <> " (params " <> tshow ps <> ")"
          <> " (pre " <> clause (contractPre cc) <> ")"
          <> " (post " <> clause (contractPost cc) <> ")"
          <> " (ret " <> tshow mr <> ")"
          <> " (measure " <> measureText f <> ")"
          <> (if T.null tys then "" else " " <> tys)
          <> ")"

    resp = case Map.lookup n (keRespRefs ke) of
      Nothing -> ""
      Just m  -> "(resp " <> T.unwords
                   [ "(" <> k <> " " <> b <> " " <> canonicalExpr e <> ")"
                   | (k, (b, e)) <- Map.toList m ] <> ")"

    group
      | not withTerm = ""
      | otherwise = case [ ns | CyclicSCC ns <- sccs, n `elem` ns ] of
          (ns : _) -> "(group " <> T.unwords [ m <> " " <> measureText m | m <- sort ns ] <> ")"
          []       -> "(group none)"
    sccs = stronglyConnComp [ (k, k, ds) | (k, ds) <- Map.toList (keCallGraph ke) ]

    measureText f = case Map.lookup f (keCalleeMeasures ke) of
      Nothing      -> "(none)"
      Just (_, ms) -> T.unwords (map canonicalExpr ms)

    clause = maybe "(none)" canonicalExpr

-- | The declarations of every named type the given types reach, through the
-- alias map, in name order. A constructor added to a sum changes the text.
typeDeclsText :: Map Name Type -> [Type] -> Text
typeDeclsText am tys =
  T.unwords [ "(type " <> nm <> " " <> tshow t <> ")"
            | nm <- Set.toAscList (closeOver Set.empty (concatMap typeNames tys))
            , Just t <- [Map.lookup nm am] ]
  where
    closeOver seen [] = seen
    closeOver seen (x : xs)
      | x `Set.member` seen = closeOver seen xs
      | otherwise = closeOver (Set.insert x seen)
                              (xs ++ maybe [] typeNames (Map.lookup x am))

typeNames :: Type -> [Name]
typeNames t = case t of
  TCustom nm       -> [nm]
  TList a          -> typeNames a
  TMap a b         -> typeNames a ++ typeNames b
  TResult a b      -> typeNames a ++ typeNames b
  TPair a b        -> typeNames a ++ typeNames b
  TFn as r         -> concatMap typeNames as ++ typeNames r
  TPromise a       -> typeNames a
  TDependent _ a _ -> typeNames a
  TSumType cs      -> concatMap (maybe [] typeNames . snd) cs
  _                -> []

-- | Every name an expression applies or references. A superset of the callees
-- (it includes locals and builtins); the caller keeps only names in 'keCenv'.
exprNames :: Expr -> Set.Set Name
exprNames e = case e of
  EVar v         -> Set.singleton v
  EApp f as      -> Set.insert f (Set.unions (map exprNames as))
  EOp f as       -> Set.insert f (Set.unions (map exprNames as))
  EIf a b c      -> Set.unions (map exprNames [a, b, c])
  ELet bs b      -> Set.unions (exprNames b : [ exprNames x | (_, _, x) <- bs ])
  EMatch sc arms -> Set.unions (exprNames sc : map (exprNames . snd) arms)
  EPair a b      -> exprNames a `Set.union` exprNames b
  EAwait a       -> exprNames a
  ELambda _ b    -> exprNames b
  EDo steps      -> Set.unions (map (exprNames . dsExpr) steps)
  _              -> Set.empty

tshow :: Show a => a -> Text
tshow = T.pack . show
