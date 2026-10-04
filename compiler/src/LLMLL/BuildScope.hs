-- |
-- Module      : LLMLL.BuildScope
-- Description : XMOD-SCOPE: a build's top-level names share one scope.
--
-- Codegen concatenates every module of a build into one @Lib.hs@
-- ('LLMLL.CodegenHs.generateHaskellMulti'), so the build closure is one scope
-- for top-level names. This module holds the pure pieces that enforce that at
-- @check@ (docs/design/xmod-name-scope-proposal.md Rev 1;
-- docs/design/xmod-scope-implementation-plan.md):
--
--   * the closure walk ('closureOf', 'importChain');
--   * the declaration table ('closureDecls');
--   * R1, one declaration per top-level name ('checkBuildScope');
--   * R2, a qualified type name resolves to its bare name
--     ('resolveQualifiedTypes', 'unresolvedQualifiedTypes');
--   * R3 codegen, a qualified value name is emitted bare
--     ('stripModuleQualifiers').
--
-- It imports 'LLMLL.Syntax' and 'LLMLL.Diagnostic' only, so 'LLMLL.TypeCheck'
-- and 'LLMLL.Module' can both import it without a cycle.
module LLMLL.BuildScope
  ( closureOf
  , importChain
  , importsOf
  , Namespace(..)
  , Decl(..)
  , closureDecls
  , entrySentinel
  , checkBuildScope
  , resolveQualifiedTypes
  , unresolvedQualifiedTypes
  , stripModuleQualifiers
  , longestModulePrefix
  ) where

import Data.Functor.Const (Const(..))
import Data.Functor.Identity (Identity(..))
import Data.List (nub, nubBy)
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.Diagnostic (Diagnostic(..), mkError)
import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Closure
-- ---------------------------------------------------------------------------

-- | The module paths a statement list imports, in source order.
importsOf :: [Statement] -> [ModulePath]
importsOf ss = [ T.splitOn "." (importPath i) | SImport i <- ss ]

-- | The part of a cache a module's statements reach through their imports,
-- transitively. Imports with no cached module (the @wasi.*@ namespaces) drop
-- out. This was 'LLMLL.EvidenceKey.restrictCache'; that name re-exports it.
closureOf :: [Statement] -> ModuleCache -> ModuleCache
closureOf stmts cache = go Set.empty (importsOf stmts)
  where
    go seen [] = Map.restrictKeys cache seen
    go seen (p : ps)
      | p `Set.member` seen = go seen ps
      | otherwise = case Map.lookup p cache of
          Nothing -> go seen ps
          Just m  -> go (Set.insert p seen) (ps ++ importsOf (meStatements m))

-- | The import path from a module's statements to a target module in the
-- cache: the first element is a direct import, the last is the target. Breadth
-- first, so the path is a shortest one. Empty when the target is unreachable.
importChain :: [Statement] -> ModuleCache -> ModulePath -> [ModulePath]
importChain stmts cache target = go starts (Map.fromList [ (p, Nothing) | p <- starts ])
  where
    starts = nub [ p | p <- importsOf stmts, Map.member p cache ]
    go [] _ = []
    go (p : q) par
      | p == target = reverse (walk par p)
      | otherwise =
          let next = nub [ c | Just m <- [Map.lookup p cache]
                             , c <- importsOf (meStatements m)
                             , Map.member c cache
                             , not (Map.member c par) ]
              par' = foldl (\acc c -> Map.insert c (Just p) acc) par next
          in go (q ++ next) par'
    walk par x = x : maybe [] (walk par) (fromMaybe Nothing (Map.lookup x par))

-- ---------------------------------------------------------------------------
-- Declarations
-- ---------------------------------------------------------------------------

-- | The two top-level namespaces, as in DUP-DEF-1 and in the emitted Haskell.
-- @type@ and @def-interface@ names are types; definitions and constructors are
-- values. So @(type Box (| Box int))@ declares one name in each.
data Namespace = NsType | NsValue
  deriving (Show, Eq, Ord)

-- | One top-level declaration: its declaring module, its name, its namespace,
-- and whether the module exports it.
data Decl = Decl
  { dModule   :: ModulePath
  , dName     :: Name
  , dNs       :: Namespace
  , dExported :: Bool
  } deriving (Show, Eq)

-- | The path under which the module being checked enters the table. No real
-- module has an empty path.
entrySentinel :: ModulePath
entrySentinel = []

-- | The declarations of one module, one per (namespace, name), each with the
-- word the R1 diagnostic uses for it. The constructor list is recomputed here
-- (the shape of 'LLMLL.TypeCheck.collectConstructors'), so this module does not
-- import the checker.
moduleDecls :: ModulePath -> (Name -> Bool) -> [Statement] -> [(Decl, Text)]
moduleDecls path exported stmts =
  nubBy (\(a, _) (b, _) -> dNs a == dNs b && dName a == dName b) $
       [ (mk NsType n, "type") | STypeDef n _ <- stmts ]
    ++ [ (mk NsType n, "type") | SDefInterface n _ _ <- stmts ]
    ++ [ (mk NsValue n, "function") | Just n <- map fnNameOf stmts ]
    ++ [ (mk NsValue c, "constructor") | STypeDef _ (TSumType cs) <- stmts, (c, _) <- cs ]
  where
    mk ns n = Decl path n ns (exported n)
    fnNameOf (SDef n _ _ _ _)          = Just n
    fnNameOf (SDefShell n _ _ _ _ _)   = Just n
    fnNameOf (SDefLogic n _ _ _ _)     = Just n
    fnNameOf (SLetrec n _ _ _ _ _)     = Just n
    fnNameOf (SDefInvariant n _ _ _ _) = Just n
    fnNameOf _                         = Nothing

-- | Every declaration of every module in a cache (normally a closure), keyed by
-- namespace and name. A module's export status is read off 'meExports', which
-- already applies its @(export ...)@ list to functions, types and constructors.
closureDecls :: ModuleCache -> Map (Namespace, Name) [Decl]
closureDecls cache = Map.map fst (closureDeclsL cache)

closureDeclsL :: ModuleCache -> Map (Namespace, Name) ([Decl], [Text])
closureDeclsL cache =
  Map.fromListWith (\(d2, l2) (d1, l1) -> (d1 ++ d2, l1 ++ l2))
    [ ((dNs d, dName d), ([d], [lbl]))
    | (path, m) <- Map.toList cache
    , (d, lbl) <- moduleDecls path (`Map.member` meExports m) (meStatements m) ]

-- ---------------------------------------------------------------------------
-- R1: one declaration for each top-level name in a build closure
-- ---------------------------------------------------------------------------

-- | R1. The statements are the module being checked; the cache is its closure.
-- A name declared by two or more distinct modules in one namespace is one
-- error, diagKind @duplicate-definition@. A declaration is its (module, name)
-- pair, so one module reached twice is counted once (E5), and a name a single
-- module declares twice is DUP-DEF-1's error, not this one.
checkBuildScope :: [Statement] -> ModuleCache -> [Diagnostic]
checkBuildScope stmts cl =
  [ dupDiag k ds lbls
  | (k, (ds0, lbls)) <- Map.toList table
  , let ds = nubBy (\a b -> dModule a == dModule b) ds0
  , length ds >= 2 ]
  where
    entry = Map.fromListWith (\(d2, l2) (d1, l1) -> (d1 ++ d2, l1 ++ l2))
              [ ((dNs d, dName d), ([d], [lbl]))
              | (d, lbl) <- moduleDecls entrySentinel (const True) stmts ]
    -- the entry's own declarations come first, then the closure in path order
    table = Map.unionWith (\(d1, l1) (d2, l2) -> (d1 ++ d2, l1 ++ l2)) entry (closureDeclsL cl)
    direct = Set.fromList (importsOf stmts)

    dupDiag (_, n) ds lbls =
      (mkError Nothing msg) { diagKind = Just "duplicate-definition" }
      where
        what = case nub lbls of
          [l] -> l
          _   -> if any ((== NsType) . dNs) ds then "type" else "value"
        msg = "duplicate top-level definition '" <> n <> "': " <> what
              <> " declared " <> joinIn (map (place . dModule) ds)
              <> "; a build's top-level names share one scope (LLMLL.md §1, §8.5)"

    place p
      | p == entrySentinel = "this module"
      | p `Set.member` direct = dotted p
      | otherwise = case init' (importChain stmts cl p) of
          []  -> dotted p
          via -> dotted p <> " (" <> dotted p <> " reached through "
                 <> T.intercalate " \x2192 " (map dotted via) <> ")"
    init' [] = []
    init' xs = init xs

    joinIn ms = case map ("in " <>) ms of
      []  -> ""
      [a] -> a
      xs  -> T.intercalate ", " (init xs) <> " and " <> last xs

dotted :: ModulePath -> Text
dotted = T.intercalate "."

-- ---------------------------------------------------------------------------
-- R2: a qualified type name resolves to its declaring module's name
-- ---------------------------------------------------------------------------

-- | R2, the load-time rewrite. @TCustom "M.T"@ becomes @TCustom "T"@ when M is
-- a direct import of these statements and M declares T. Under R1 a bare type
-- name has one declaring module in the closure, so dropping the qualifier
-- cannot capture another type. An unresolved qualified name stays as written;
-- 'unresolvedQualifiedTypes' reports it.
--
-- Type positions: parameter and return types, the bodies of @type@, @let@
-- annotations, lambda parameters and interface signatures.
resolveQualifiedTypes :: [Statement] -> ModuleCache -> [Statement]
resolveQualifiedTypes stmts cl
  | Map.null cl = stmts
  | otherwise   = map (runIdentity . travStmtTypes (onCustom (Identity . resolve))) stmts
  where
    direct = Set.fromList [ p | p <- importsOf stmts, Map.member p cl ]
    tys    = typeDeclSet cl
    resolve n = case qualSplit n of
      Just (m, t) | m `Set.member` direct, (m, t) `Set.member` tys -> t
      _ -> n

-- | R2, the diagnostics. A @TCustom@ that is still qualified and whose prefix
-- is a module in the closure. One diagnostic per distinct name, diagKind
-- @name-not-in-scope@.
unresolvedQualifiedTypes :: [Statement] -> ModuleCache -> [Diagnostic]
unresolvedQualifiedTypes stmts cl =
  [ (mkError Nothing msg) { diagKind = Just "name-not-in-scope" }
  | n <- nub (concatMap (getConst . travStmtTypes (onCustom (\x -> Const [x]))) stmts)
  , Just (m, t) <- [qualSplit n]
  , Map.member m cl
  , let declared = (m, t) `Set.member` tys
        isDirect = m `Set.member` direct
  , not (declared && isDirect)
  , let msg | not declared = "type '" <> n <> "' is not declared in " <> dotted m
            | otherwise    = "type '" <> n <> "' is declared in " <> dotted m
                             <> ", which is not imported here; add (import " <> dotted m <> ")"
  ]
  where
    direct = Set.fromList (importsOf stmts)
    tys    = typeDeclSet cl

-- | (module, type name) for every type a cached module declares.
typeDeclSet :: ModuleCache -> Set (ModulePath, Name)
typeDeclSet cl = Set.fromList
  [ (dModule d, dName d) | ((NsType, _), ds) <- Map.toList (closureDecls cl), d <- ds ]

-- | @"a.b.T"@ to @(["a","b"], "T")@; Nothing for an undotted name.
qualSplit :: Name -> Maybe (ModulePath, Name)
qualSplit n = case T.splitOn "." n of
  segs@(_ : _ : _) -> Just (init segs, last segs)
  _                -> Nothing

-- | Apply a function to every 'TCustom' name inside a type.
onCustom :: Applicative f => (Name -> f Name) -> Type -> f Type
onCustom g = go
  where
    go t = case t of
      TCustom n        -> TCustom <$> g n
      TList a          -> TList <$> go a
      TMap a b         -> TMap <$> go a <*> go b
      TResult a b      -> TResult <$> go a <*> go b
      TPair a b        -> TPair <$> go a <*> go b
      TFn as r         -> TFn <$> traverse go as <*> go r
      TPromise a       -> TPromise <$> go a
      TDependent v a e -> (\a' -> TDependent v a' e) <$> go a
      TSumType cs      -> TSumType <$> traverse (\(c, mp) -> (,) c <$> traverse go mp) cs
      _                -> pure t

-- | Every type position R2 reads in a statement.
travStmtTypes :: Applicative f => (Type -> f Type) -> Statement -> f Statement
travStmtTypes f s = case s of
  SDef n ps r c b ->
    SDef n <$> params ps <*> traverse f r <*> travContract ex c <*> ex b
  SDefShell n ps r c b ds ->
    SDefShell n <$> params ps <*> traverse f r <*> travContract ex c <*> ex b <*> traverse ex ds
  SDefLogic n ps r c b ->
    SDefLogic n <$> params ps <*> traverse f r <*> travContract ex c <*> ex b
  SDefInvariant n ps r c b ->
    SDefInvariant n <$> params ps <*> traverse f r <*> travContract ex c <*> ex b
  SLetrec n ps r c d b ->
    SLetrec n <$> params ps <*> traverse f r <*> travContract ex c <*> ex d <*> ex b
  STypeDef n t -> STypeDef n <$> f t
  SDefInterface n fns laws -> (\fns' -> SDefInterface n fns' laws) <$> params fns
  _ -> travStmtExprs ex s
  where
    params = traverse (\(n, t) -> (,) n <$> f t)
    ex     = travExprTypes f

-- | Every type annotation inside an expression: @let@ and lambda parameters.
travExprTypes :: Applicative f => (Type -> f Type) -> Expr -> f Expr
travExprTypes f = go
  where
    go e = case e of
      ELet bs b      -> ELet <$> traverse (\(p, mt, x) -> (,,) p <$> traverse f mt <*> go x) bs <*> go b
      ELambda ps b   -> ELambda <$> traverse (\(n, t) -> (,) n <$> f t) ps <*> go b
      _              -> descendExpr go e

-- ---------------------------------------------------------------------------
-- R3 codegen: a qualified value name is emitted bare
-- ---------------------------------------------------------------------------

-- | The longest prefix of a dotted name that is a module path in the set, with
-- the remainder. Nothing when no prefix is in the set.
longestModulePrefix :: Set ModulePath -> Name -> Maybe (ModulePath, Name)
longestModulePrefix paths n =
  case [ (take k segs, T.intercalate "." (drop k segs))
       | k <- [length segs - 1, length segs - 2 .. 1]
       , take k segs `Set.member` paths ] of
    (hit : _) -> Just hit
    []        -> Nothing
  where segs = T.splitOn "." n

-- | R3. Rewrite @EVar@, the @EApp@ callee and @PConstructor@ names of the form
-- @M.x@ to @x@ when M is in the set (longest prefix). R1 makes the bare name
-- unique in @Lib.hs@, so the rewrite cannot capture another declaration. A
-- @wasi.*@ name never matches, because no @wasi@ module is in a cache.
stripModuleQualifiers :: Set ModulePath -> [Statement] -> [Statement]
stripModuleQualifiers paths
  | Set.null paths = id
  | otherwise      = map (runIdentity . travStmtExprs (Identity . goE))
  where
    strip n = maybe n snd (longestModulePrefix paths n)
    goE e = case e of
      EVar n       -> EVar (strip n)
      EApp f as    -> EApp (strip f) (map goE as)
      EMatch sc as -> EMatch (goE sc) [ (goP p, goE x) | (p, x) <- as ]
      _            -> runIdentity (descendExpr (Identity . goE) e)
    goP p = case p of
      PConstructor c ps -> PConstructor (strip c) (map goP ps)
      _                 -> p

-- ---------------------------------------------------------------------------
-- Generic traversals
-- ---------------------------------------------------------------------------

-- | Apply a function to every top-level expression of a statement: bodies,
-- contract clauses, measures, @def-main@ fields, @check@ bodies and top-level
-- expressions. The function is responsible for its own recursion.
travStmtExprs :: Applicative f => (Expr -> f Expr) -> Statement -> f Statement
travStmtExprs ex s = case s of
  SDef n ps r c b              -> SDef n ps r <$> travContract ex c <*> ex b
  SDefShell n ps r c b ds      -> SDefShell n ps r <$> travContract ex c <*> ex b <*> traverse ex ds
  SDefLogic n ps r c b         -> SDefLogic n ps r <$> travContract ex c <*> ex b
  SDefInvariant n ps r c b     -> SDefInvariant n ps r <$> travContract ex c <*> ex b
  SLetrec n ps r c d b         -> SLetrec n ps r <$> travContract ex c <*> ex d <*> ex b
  SExpr e                      -> SExpr <$> ex e
  SCheck p                     -> (\b -> SCheck p { propBody = b }) <$> ex (propBody p)
  m@SDefMain{}                 ->
    (\i st d od stt -> m { defMainInit = i, defMainStep = st, defMainDone = d
                         , defMainOnDone = od, defMainStatus = stt })
      <$> traverse ex (defMainInit m) <*> ex (defMainStep m) <*> traverse ex (defMainDone m)
      <*> traverse ex (defMainOnDone m) <*> traverse ex (defMainStatus m)
  _                            -> pure s

-- | The contract's scalar clauses and its per-conjunct lists (SRC-CONJ-1 keeps
-- the scalar equal to the fold of the list, so both are rewritten).
travContract :: Applicative f => (Expr -> f Expr) -> Contract -> f Contract
travContract ex c =
  (\pre post pcs qcs -> c { contractPre = pre, contractPost = post
                          , contractPreClauses = pcs, contractPostClauses = qcs })
    <$> traverse ex (contractPre c) <*> traverse ex (contractPost c)
    <*> traverse clause (contractPreClauses c) <*> traverse clause (contractPostClauses c)
  where clause pc = (\e -> pc { pcExpr = e }) <$> ex (pcExpr pc)

-- | One layer of structural recursion over an expression's children.
descendExpr :: Applicative f => (Expr -> f Expr) -> Expr -> f Expr
descendExpr go e = case e of
  ELet bs b      -> ELet <$> traverse (\(p, mt, x) -> (,,) p mt <$> go x) bs <*> go b
  EIf a b c      -> EIf <$> go a <*> go b <*> go c
  EMatch sc arms -> EMatch <$> go sc <*> traverse (\(p, x) -> (,) p <$> go x) arms
  EApp f as      -> EApp f <$> traverse go as
  EOp o as       -> EOp o <$> traverse go as
  EPair a b      -> EPair <$> go a <*> go b
  EAwait a       -> EAwait <$> go a
  ELambda ps b   -> ELambda ps <$> go b
  EDo steps      -> EDo <$> traverse (\st -> (\x -> st { dsExpr = x }) <$> go (dsExpr st)) steps
  _              -> pure e
