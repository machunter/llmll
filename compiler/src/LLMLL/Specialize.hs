-- |
-- Module      : LLMLL.Specialize
-- Description : GENERICS-1 (S5) and GENERIC-COMPARE-1 (S7): specialize each
--               reached instantiation of a generic def-shell into an ordinary
--               def-shell copy before verification.
--
-- The verifier checks generic code per instance (SPARK discipline,
-- docs/design/generics-proposal.md "Verification", steps 1 to 9). This pass
-- turns a checked program into the program the verifier reads:
--
--   1. Roots: every non-generic definition and every other statement.
--   2. Worklist: each generic call site of a root, read from the type
--      checker's site table ('GenericSites'), names a pair (f, [T...]). The
--      enclosing copy's type arguments are substituted into the site's, an
--      unfixed one becomes @int@ (step 6), and transparent aliases are
--      expanded. Each new pair is copied, and its own sites are read in turn.
--      Rule 2 (polymorphic-recursion) makes the set finite; a hard cap of
--      10,000 copies stops a defect from looping.
--   3. Copy: an 'SDefShell' named @f\@[T1,T2]@ with no type parameters. Lookups
--      are made on the ORIGINAL body, keyed by the original argument text,
--      before any call inside the arguments is renamed.
--   4. Roots are rewritten the same way.
--   5. A copy of a generic imported from module M has its free top-level
--      names qualified with M's path, so an entry definition with the same
--      name cannot capture them. Copies go into the entry statement list.
--   6. Generic sources are dropped from the output.
--
-- A @compare@ site whose operand type is @int@ or @bool@ (through aliases and
-- refinements) is renamed @compare%int@ / @compare%bool@, which the emitter
-- unfolds definitionally; any other operand keeps @compare@ and falls back.
--
-- The pass is the identity when the module has no generic definition and the
-- site table is empty (no generic call and no @compare@), which is the
-- guarantee that existing programs are unaffected. The type checker is not run
-- again: the site table carries every type the pass needs (plan F2).
module LLMLL.Specialize
  ( specialize
  , specializeWithRet
  , GenericStats(..)
  , emptyGenericStats
  , gsDefinitions
  , gsInstances
  , renderTypeArg
  , copyTypeArgsSuffix
  ) where

import Data.List (foldl')
import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Set (Set)
import Data.Text (Text)
import qualified Data.Text as T

import LLMLL.PBT (canonicalExpr)
import LLMLL.Syntax
import LLMLL.TypeAdmissibility (AliasMap, buildAliasMap)

-- | What the pass did, for the @verify@ count line, its JSON twin, and the
-- PBT subject mapping.
data GenericStats = GenericStats
  { gsPerDefinition :: [(Name, Int)]
    -- ^ each generic definition, with its instance count: the entry module's
    -- in statement order (an uninstantiated one counts 0), then each imported
    -- generic that has at least one copy, under its qualified name
  , gsSiteCopies    :: Map SiteKey Name
    -- ^ each generic call site of an entry root, mapped to the copy it now
    -- calls (the PBT @subject_key@ lift reads this)
  } deriving (Show, Eq)

emptyGenericStats :: GenericStats
emptyGenericStats = GenericStats [] Map.empty

-- | Number of generic definitions reported (N in "N definitions").
gsDefinitions :: GenericStats -> Int
gsDefinitions = length . gsPerDefinition

-- | Number of copies made (M in "M instances").
gsInstances :: GenericStats -> Int
gsInstances = sum . map snd . gsPerDefinition

-- | Where a generic definition lives.
data Origin = Entry | Imported ModulePath
  deriving (Show, Eq, Ord)

-- | A generic definition, by origin and bare name.
type GKey = (Origin, Name)

-- | One instance: a generic and its concrete, expanded type arguments.
type Instance = (GKey, [Type])

-- | Everything one module's names resolve against.
data ModCtx = ModCtx
  { mcOrigin   :: Origin
  , mcStmts    :: [Statement]
  , mcSites    :: GenericSites
  , mcGenerics :: Map Name Statement      -- ^ bare name -> generic def-shell
  , mcTopNames :: Set Name                -- ^ the module's own top-level definitions
  }

-- | GENERICS-1 (S5): specialize a checked entry program. See the module
-- header for the steps.
specialize :: ModuleCache -> GenericSites -> [Statement] -> ([Statement], GenericStats)
specialize cache sites stmts =
  let (out, stats, _) = specializeWithRet Map.empty cache sites stmts in (out, stats)

-- | 'specialize', plus the effective return type (tau_ret) of each copy whose
-- source declares none: the source's own tau_ret (the entry's from the given
-- map, an imported module's from its 'meRetTypes') with the type arguments
-- substituted. The verify path unions it into the map the emitter reads, so a
-- copy's @result@ is sorted as its hand-written equivalent's would be, never
-- by the int default. A tau_ret that is still a placeholder is left out.
specializeWithRet
  :: Map Name Type -> ModuleCache -> GenericSites -> [Statement]
  -> ([Statement], GenericStats, Map Name Type)
specializeWithRet retTypes cache sites stmts
  | null entryGenerics && Map.null sites = (stmts, emptyGenericStats, Map.empty)
  | otherwise =
      let rootsOut  = [ (i, rewriteRoot i s) | (i, s) <- zip [0 :: Int ..] stmts ]
          rootReqs  = concat [ reqs | (_, (_, reqs, _)) <- rootsOut ]
          siteCopies = Map.unions [ m | (_, (_, _, m)) <- rootsOut ]
          (copies, done) = worklist rootReqs
          kept      = [ s' | (_, (Just s', _, _)) <- rootsOut ]
          counts    = Map.fromListWith (+) [ (k, 1 :: Int) | (k, _) <- Map.elems done ]
          perDef    = [ (n, Map.findWithDefault 0 (Entry, n) counts) | (n, _) <- entryGenerics ]
                      ++ [ (qualName o n, c) | ((o@(Imported _), n), c) <- Map.toList counts ]
          copyRets  = Map.fromList
            [ (cn, t')
            | (cn, ((o, bare), tys)) <- Map.toList done
            , Just SDefShell{defShellReturn = Nothing, defShellTypeParams = tps} <- [Map.lookup bare (mcGenerics (ctxOf o))]
            , Just t <- [sourceRet o bare]
            , let t' = substTP (Map.fromList (zip (map fst tps) tys)) t
            , not (mentionsTP t'), not (hasTVar t') ]
      in (kept ++ copies, GenericStats perDef siteCopies, copyRets)
  where
    sourceRet Entry bare        = Map.lookup bare retTypes
    sourceRet (Imported p) bare = Map.lookup p cache >>= Map.lookup bare . meRetTypes
    hasTVar t = case t of
      TVar _           -> True
      TList a          -> hasTVar a
      TMap k v         -> hasTVar k || hasTVar v
      TResult a b      -> hasTVar a || hasTVar b
      TPair a b        -> hasTVar a || hasTVar b
      TFn as r         -> any hasTVar as || hasTVar r
      TPromise a       -> hasTVar a
      TDependent _ b _ -> hasTVar b
      _                -> False
    entryGenerics = [ (n, s) | s@SDefShell{defShellName = n, defShellTypeParams = (_ : _)} <- stmts ]

    am :: AliasMap
    am = Map.union (buildAliasMap stmts) (Map.unions [ meAliasMap m | m <- Map.elems cache ])

    entryCtx = mkCtx Entry stmts sites
    ctxOf Entry           = entryCtx
    ctxOf o@(Imported p)  = case Map.lookup p cache of
      Just menv -> mkCtx o (meStatements menv) (meGenericSites menv)
      Nothing   -> mkCtx o [] Map.empty

    mkCtx o ss st = ModCtx
      { mcOrigin   = o
      , mcStmts    = ss
      , mcSites    = st
      , mcGenerics = Map.fromList [ (n, s) | s@SDefShell{defShellName = n, defShellTypeParams = (_ : _)} <- ss ]
      , mcTopNames = Set.fromList (mapMaybe defNameOf ss)
      }

    modulePaths = Set.fromList (Map.keys cache)

    -- | Resolve a callee name, as written in module ctx, to a generic.
    resolveGeneric :: ModCtx -> Name -> Maybe GKey
    resolveGeneric ctx f
      | Map.member f (mcGenerics ctx) = Just (mcOrigin ctx, f)
      | Set.member f (mcTopNames ctx) = Nothing   -- a local non-generic definition
      | Just (p, bare) <- longestPrefix f
      , Just menv <- Map.lookup p cache
      , isGenericIn (meStatements menv) bare = Just (Imported p, bare)
      | otherwise = case [ p | SOpen p mNames <- mcStmts ctx
                             , maybe True (f `elem`) mNames
                             , Just menv <- [Map.lookup p cache]
                             , isGenericIn (meStatements menv) f ] of
          (p : _) -> Just (Imported p, f)
          []      -> Nothing

    isGenericIn ss n = not (null [ () | SDefShell{defShellName = m, defShellTypeParams = (_ : _)} <- ss, m == n ])

    longestPrefix f = case [ (take k segs, T.intercalate "." (drop k segs))
                           | k <- [length segs - 1, length segs - 2 .. 1]
                           , take k segs `Set.member` modulePaths ] of
      (hit : _) -> Just hit
      []        -> Nothing
      where segs = T.splitOn "." f

    -- | The owner key the checker gives statement i of the entry module.
    ownerOf :: Int -> Statement -> Name
    ownerOf i s = fromMaybe ("/statements/" <> T.pack (show i)) (defNameOf s)

    -- | A root: a non-generic statement, rewritten; a generic source, dropped.
    rewriteRoot :: Int -> Statement -> (Maybe Statement, [Instance], Map SiteKey Name)
    rewriteRoot i s = case s of
      SDefShell{defShellTypeParams = (_ : _)} -> (Nothing, [], Map.empty)
      -- A check is a root (its instances must exist for the PBT
      -- subject_key), but the verifier emits no check, and the PBT liveness
      -- test hashes the property body as written. So the statement is kept
      -- unchanged; only its instances and site mapping are taken.
      SCheck{} ->
        let RW _ reqs hits = rewriteStmt entryCtx (ownerOf i s) Map.empty False s
        in (Just s, reqs, hits)
      _ ->
        let RW s' reqs hits = rewriteStmt entryCtx (ownerOf i s) Map.empty False s
        in (Just s', reqs, hits)

    -- | The worklist over instances. Returns the copies in creation order and
    -- the instances made, keyed by copy name ('copyName' is injective on the
    -- instance, and 'Type' has no 'Ord').
    worklist :: [Instance] -> ([Statement], Map Name Instance)
    worklist = go [] Map.empty
      where
        go acc done [] = (reverse acc, done)
        go acc done (x@((o, bare), tys) : xs)
          | cn `Map.member` done = go acc done xs
          | Map.size done >= copyCap =
              error ("internal error (GENERICS-1): more than " <> show copyCap
                     <> " specialized copies; rule 2 should bound the instantiation set")
          | otherwise = case makeCopy x of
              Nothing          -> go acc (Map.insert cn x done) xs
              Just (c, reqs)   -> go (c : acc) (Map.insert cn x done) (xs ++ reqs)
          where cn = copyName o bare tys

    copyCap :: Int
    copyCap = 10000

    makeCopy :: Instance -> Maybe (Statement, [Instance])
    makeCopy ((o, bare), tys) = do
      let ctx = ctxOf o
      src <- Map.lookup bare (mcGenerics ctx)
      case src of
        SDefShell n ps r c b ds tps
          | length tps == length tys ->
              let subst = Map.fromList (zip (map fst tps) tys)
                  RW st' reqs _ = rewriteStmt ctx bare subst True (SDefShell n ps r c b ds [])
                  st'' = case st' of
                    SDefShell _ ps' r' c' b' ds' _ ->
                      mapStmtTypes (substTP subst) (SDefShell (copyName o bare tys) ps' r' c' b' ds' [])
                    other -> other
              in Just (st'', reqs)
        _ -> Nothing

    -- | Finalize one site type argument: the enclosing instance's
    -- arguments substituted, an unfixed type taken at int, transparent
    -- aliases expanded. 'Nothing' when a rigid parameter is left over (a
    -- defect; the call is then left alone and the emitter falls back).
    finalizeArg :: Map Name Type -> Type -> Maybe Type
    finalizeArg subst t =
      let t' = expandTransparent am (unfix (substTP subst t))
      in if mentionsTP t' then Nothing else Just t'

    -- | The rename of a compare site: by the base scalar of its operand.
    compareName :: Map Name Type -> Type -> Name
    compareName subst t = case baseScalar am (substTP subst t) of
      Just TInt  -> "compare%int"
      Just TBool -> "compare%bool"
      _          -> "compare"

    -- | Rewrite one definition's (or statement's) expressions: each generic
    -- call to its copy, each compare site to its unfolding name and, in a
    -- copy of an imported generic, each free top-level name qualified.
    rewriteStmt :: ModCtx -> Name -> Map Name Type -> Bool -> Statement -> RW Statement
    rewriteStmt ctx owner subst isCopy s = case s of
      SDefShell n ps r c b ds tps ->
        let bound0 = Set.fromList (map fst ps)
            RW c' r1 h1 = rwContract bound0 c
            RW b' r2 h2 = rw bound0 b
            RW ds' r3 h3 = rwList bound0 ds
        in RW (SDefShell n ps r c' b' ds' tps) (r1 ++ r2 ++ r3) (Map.unions [h1, h2, h3])
      SDef n ps r c b ->
        let bound0 = Set.fromList (map fst ps)
            RW c' r1 h1 = rwContract bound0 c
            RW b' r2 h2 = rw bound0 b
        in RW (SDef n ps r c' b') (r1 ++ r2) (Map.union h1 h2)
      SDefLogic n ps r c b ->
        let bound0 = Set.fromList (map fst ps)
            RW c' r1 h1 = rwContract bound0 c
            RW b' r2 h2 = rw bound0 b
        in RW (SDefLogic n ps r c' b') (r1 ++ r2) (Map.union h1 h2)
      SDefInvariant n ps r c b ->
        let bound0 = Set.fromList (map fst ps)
            RW c' r1 h1 = rwContract bound0 c
            RW b' r2 h2 = rw bound0 b
        in RW (SDefInvariant n ps r c' b') (r1 ++ r2) (Map.union h1 h2)
      SLetrec n ps r c d b ->
        let bound0 = Set.fromList (map fst ps)
            RW c' r1 h1 = rwContract bound0 c
            RW d' r2 h2 = rw bound0 d
            RW b' r3 h3 = rw bound0 b
        in RW (SLetrec n ps r c' d' b') (r1 ++ r2 ++ r3) (Map.unions [h1, h2, h3])
      SCheck p ->
        let RW b' r1 h1 = rw (Set.fromList (map fst (propBindings p))) (propBody p)
        in RW (SCheck p { propBody = b' }) r1 h1
      SExpr e ->
        let RW e' r1 h1 = rw Set.empty e
        in RW (SExpr e') r1 h1
      _ -> RW s [] Map.empty
      where
        rwContract bound c =
          let RW pre'  r1 h1 = rwMaybe bound (contractPre c)
              RW post' r2 h2 = rwMaybe bound (contractPost c)
              RW pcs'  r3 h3 = rwClauses bound (contractPreClauses c)
              RW qcs'  r4 h4 = rwClauses bound (contractPostClauses c)
          in RW c { contractPre = pre', contractPost = post'
                  , contractPreClauses = pcs', contractPostClauses = qcs' }
                (r1 ++ r2 ++ r3 ++ r4) (Map.unions [h1, h2, h3, h4])
        rwClauses bound pcs =
          let outs = [ (pc, rw bound (pcExpr pc)) | pc <- pcs ]
          in RW [ pc { pcExpr = e' } | (pc, RW e' _ _) <- outs ]
                (concat [ r | (_, RW _ r _) <- outs ])
                (Map.unions [ h | (_, RW _ _ h) <- outs ])
        rwMaybe _ Nothing      = RW Nothing [] Map.empty
        rwMaybe bound (Just e) = let RW e' r h = rw bound e in RW (Just e') r h
        rwList bound es =
          let outs = map (rw bound) es
          in RW [ e | RW e _ _ <- outs ] (concat [ r | RW _ r _ <- outs ]) (Map.unions [ h | RW _ _ h <- outs ])

        rw :: Set Name -> Expr -> RW Expr
        rw bound e = case e of
          EApp f args
            | f `Set.member` bound ->
                let RW as' r h = rwList bound args in RW (EApp f as') r h
            | otherwise ->
                let key = (owner, f, map canonicalExpr args)
                    RW as' r h = rwList bound args
                    site = Map.lookup key (mcSites ctx)
                in case (f, site) of
                     ("compare", Just [t]) -> RW (EApp (compareName subst t) as') r h
                     (_, Just tys)
                       | Just gk@(o, bare) <- resolveGeneric ctx f
                       , Just tys' <- mapM (finalizeArg subst) tys ->
                           let cn  = copyName o bare tys'
                               hit = if isCopy then Map.empty else Map.singleton key cn
                           in RW (EApp cn as') ((gk, tys') : r) (Map.union hit h)
                     _ -> RW (EApp (qual bound f) as') r h
          EOp o args -> let RW as' r h = rwList bound args in RW (EOp o as') r h
          EVar v -> RW (EVar (qual bound v)) [] Map.empty
          EIf a b c ->
            let RW a' r1 h1 = rw bound a
                RW b' r2 h2 = rw bound b
                RW c' r3 h3 = rw bound c
            in RW (EIf a' b' c') (r1 ++ r2 ++ r3) (Map.unions [h1, h2, h3])
          ELet binds body ->
            let step (accB, bnd, rs, hs) (p, mt, x) =
                  let RW x' r h = rw bnd x
                  in (accB ++ [(p, mt, x')], Set.union bnd (patVars p), rs ++ r, Map.union hs h)
                (binds', bnd', rs0, hs0) = foldl' step ([], bound, [], Map.empty) binds
                RW body' r1 h1 = rw bnd' body
            in RW (ELet binds' body') (rs0 ++ r1) (Map.union hs0 h1)
          EMatch sc arms ->
            let RW sc' r0 h0 = rw bound sc
                outs = [ (p, rw (Set.union bound (patVars p)) a) | (p, a) <- arms ]
            in RW (EMatch sc' [ (p, a') | (p, RW a' _ _) <- outs ])
                  (r0 ++ concat [ r | (_, RW _ r _) <- outs ])
                  (Map.unions (h0 : [ h | (_, RW _ _ h) <- outs ]))
          EPair a b ->
            let RW a' r1 h1 = rw bound a
                RW b' r2 h2 = rw bound b
            in RW (EPair a' b') (r1 ++ r2) (Map.union h1 h2)
          EAwait a -> let RW a' r h = rw bound a in RW (EAwait a') r h
          ELambda ps body ->
            let RW body' r h = rw (Set.union bound (Set.fromList (map fst ps))) body
            in RW (ELambda ps body') r h
          EDo steps ->
            let step (accS, bnd, rs, hs) st =
                  let RW x' r h = rw bnd (dsExpr st)
                      bnd' = maybe bnd (`Set.insert` bnd) (dsName st)
                  in (accS ++ [st { dsExpr = x' }], bnd', rs ++ r, Map.union hs h)
                (steps', _, rs0, hs0) = foldl' step ([], bound, [], Map.empty) steps
            in RW (EDo steps') rs0 hs0
          _ -> RW e [] Map.empty

        -- Step 5: in a copy of an imported generic, a free name that is a
        -- top-level definition of its module (or one the module opened) is
        -- qualified, so the entry's own definitions cannot capture it.
        qual bound v
          | not isCopy = v
          | v `Set.member` bound = v
          | Imported p <- mcOrigin ctx =
              if v `Set.member` mcTopNames ctx
                then T.intercalate "." p <> "." <> v
                else case [ q | SOpen q mNames <- mcStmts ctx
                              , maybe True (v `elem`) mNames
                              , Just menv <- [Map.lookup q cache]
                              , v `elem` mapMaybe defNameOf (meStatements menv) ] of
                       (q : _) -> T.intercalate "." q <> "." <> v
                       []      -> v
          | otherwise = v

-- | A rewritten value, the instances it requires, and the root sites it hit.
data RW a = RW a [Instance] (Map SiteKey Name)

-- | The name of a definition-like statement, which is also the owner key the
-- type checker gives the calls inside it.
defNameOf :: Statement -> Maybe Name
defNameOf s = case s of
  SDefLogic{defLogicName = n}         -> Just n
  SLetrec{letrecName = n}             -> Just n
  SDef{defName = n}                   -> Just n
  SDefShell{defShellName = n}         -> Just n
  SDefInvariant{defInvariantName = n} -> Just n
  _                                   -> Nothing

patVars :: Pattern -> Set Name
patVars p = case p of
  PVar x            -> Set.singleton x
  PConstructor _ ps -> Set.unions (map patVars ps)
  _                 -> Set.empty

qualName :: Origin -> Name -> Name
qualName Entry n        = n
qualName (Imported p) n = T.intercalate "." p <> "." <> n

-- | The copy's name: @f\@[T1,T2]@, qualified by the module path for an
-- imported generic. @\@@ and @[@ cannot appear in an LLMLL identifier, so no
-- user definition can carry the name.
copyName :: Origin -> Name -> [Type] -> Name
copyName o n tys = qualName o n <> "@[" <> T.intercalate "," (map renderTypeArg tys) <> "]"

-- | The @[...]@ suffix of a copy's name, or 'Nothing' for any other name.
-- 'LLMLL.EvidenceKey' folds it into a copy's key as the @(type-args ...)@
-- fragment, so @f\@[int]@ and @f\@[bool]@ never hash alike.
copyTypeArgsSuffix :: Name -> Maybe Text
copyTypeArgsSuffix n = case T.breakOn "@[" n of
  (_, rest) | not (T.null rest) -> Just (T.drop 1 rest)
  _                             -> Nothing

-- | An injective rendering of a type argument, for copy names. 'typeLabel'
-- is not injective (a function type shows only its arity).
renderTypeArg :: Type -> Text
renderTypeArg t = case t of
  TInt             -> "int"
  TFloat           -> "float"
  TString          -> "string"
  TBool            -> "bool"
  TUnit            -> "unit"
  TBytes n         -> "bytes[" <> T.pack (show n) <> "]"
  TList a          -> "list[" <> renderTypeArg a <> "]"
  TMap k v         -> "map[" <> renderTypeArg k <> "," <> renderTypeArg v <> "]"
  TResult a b      -> "Result[" <> renderTypeArg a <> "," <> renderTypeArg b <> "]"
  TPair a b        -> "(" <> renderTypeArg a <> "," <> renderTypeArg b <> ")"
  TFn as r         -> "fn[" <> T.intercalate "," (map renderTypeArg as) <> "]->" <> renderTypeArg r
  TPromise a       -> "Promise[" <> renderTypeArg a <> "]"
  TDependent x b p -> "{" <> x <> ":" <> renderTypeArg b <> "|" <> canonicalExpr p <> "}"
  TDelegationError -> "DelegationError"
  TVar n           -> n
  TCustom n        -> n
  TSumType cs      -> "(|" <> T.intercalate "|" [ c <> maybe "" ((" " <>) . renderTypeArg) mp | (c, mp) <- cs ] <> ")"
  TParam n _       -> n

-- | An unfixed type (any 'TVar' left in a site type argument) is taken at
-- @int@ (verification step 6; AMBIG-TVAR-1).
unfix :: Type -> Type
unfix = mapTy (\t -> case t of TVar _ -> Just TInt; _ -> Nothing)

substTP :: Map Name Type -> Type -> Type
substTP m = mapTy (\t -> case t of TParam n _ -> Map.lookup n m; _ -> Nothing)

mentionsTP :: Type -> Bool
mentionsTP t = case t of
  TParam _ _       -> True
  TList a          -> mentionsTP a
  TMap k v         -> mentionsTP k || mentionsTP v
  TResult a b      -> mentionsTP a || mentionsTP b
  TPair a b        -> mentionsTP a || mentionsTP b
  TFn as r         -> any mentionsTP as || mentionsTP r
  TPromise a       -> mentionsTP a
  TDependent _ b _ -> mentionsTP b
  TSumType cs      -> any (maybe False mentionsTP . snd) cs
  _                -> False

-- | Bottom-up type rewrite: the function answers 'Just' to replace a node.
mapTy :: (Type -> Maybe Type) -> Type -> Type
mapTy f t = case f t of
  Just t' -> t'
  Nothing -> case t of
    TList a          -> TList (mapTy f a)
    TMap k v         -> TMap (mapTy f k) (mapTy f v)
    TResult a b      -> TResult (mapTy f a) (mapTy f b)
    TPair a b        -> TPair (mapTy f a) (mapTy f b)
    TFn as r         -> TFn (map (mapTy f) as) (mapTy f r)
    TPromise a       -> TPromise (mapTy f a)
    TDependent x b p -> TDependent x (mapTy f b) p
    TSumType cs      -> TSumType [ (c, fmap (mapTy f) mp) | (c, mp) <- cs ]
    _                -> t

-- | Expand transparent aliases in a type argument, so @(type Ints list[int])@
-- and @list[int]@ name one instance. A refinement alias and a sum type stay
-- named: they are what 'FixpointEmit.augmentContractPre' and the sum-sort path
-- read off the copy's parameter types, so the copy states the same
-- obligations a hand-written copy at that type would (edge case 13).
expandTransparent :: AliasMap -> Type -> Type
expandTransparent am = go (32 :: Int)
  where
    go 0 t = t
    go k t = case t of
      TCustom n | Just body <- Map.lookup n am, transparent body -> go (k - 1) body
      TList a          -> TList (go k a)
      TMap a b         -> TMap (go k a) (go k b)
      TResult a b      -> TResult (go k a) (go k b)
      TPair a b        -> TPair (go k a) (go k b)
      TFn as r         -> TFn (map (go k) as) (go k r)
      TPromise a       -> TPromise (go k a)
      _                -> t
    transparent body = case body of
      TSumType _       -> False
      TDependent _ _ _ -> False
      TCustom _        -> False   -- an alias of a named type keeps its own name
      _                -> True

-- | The scalar a type reduces to through aliases and refinements, for the
-- compare unfolding: @PositiveInt@ compares as @int@.
baseScalar :: AliasMap -> Type -> Maybe Type
baseScalar am = go (32 :: Int)
  where
    go 0 _ = Nothing
    go k t = case t of
      TInt             -> Just TInt
      TBool            -> Just TBool
      TDependent _ b _ -> go (k - 1) b
      TCustom n        -> Map.lookup n am >>= go (k - 1)
      _                -> Nothing

-- | Apply a type rewrite to every type position of a def-shell: parameters,
-- return, and every annotation in the contract, the measures and the body.
mapStmtTypes :: (Type -> Type) -> Statement -> Statement
mapStmtTypes f st = case st of
  SDefShell n ps r c b ds tps ->
    SDefShell n [ (p, f t) | (p, t) <- ps ] (fmap f r) (mc c) (me b) (map me ds) tps
  _ -> st
  where
    mc ct = ct { contractPre  = fmap me (contractPre ct)
               , contractPost = fmap me (contractPost ct)
               , contractPreClauses  = [ pc { pcExpr = me (pcExpr pc) } | pc <- contractPreClauses ct ]
               , contractPostClauses = [ pc { pcExpr = me (pcExpr pc) } | pc <- contractPostClauses ct ] }
    me e = case e of
      ELet binds body  -> ELet [ (p, fmap f mt, me x) | (p, mt, x) <- binds ] (me body)
      EIf x y z        -> EIf (me x) (me y) (me z)
      EMatch x arms    -> EMatch (me x) [ (p, me a) | (p, a) <- arms ]
      EApp g args      -> EApp g (map me args)
      EOp o args       -> EOp o (map me args)
      EPair x y        -> EPair (me x) (me y)
      EHole h          -> EHole (mh h)
      EAwait x         -> EAwait (me x)
      ELambda lps body -> ELambda [ (p, f t) | (p, t) <- lps ] (me body)
      EDo steps        -> EDo [ s { dsExpr = me (dsExpr s) } | s <- steps ]
      _                -> e
    mh h = case h of
      HDelegate sp        -> HDelegate (md sp)
      HDelegateAsync sp   -> HDelegateAsync (md sp)
      HDelegatePending t  -> HDelegatePending (f t)
      HProofRequired w mp -> HProofRequired w (fmap me mp)
      _                   -> h
    md sp = sp { delegateReturnType = f (delegateReturnType sp)
               , delegateOnFailure  = fmap me (delegateOnFailure sp) }
