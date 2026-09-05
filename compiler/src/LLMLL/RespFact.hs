{-# LANGUAGE OverloadedStrings #-}
-- | RESP-FACT-1: an effect's result carries a proved property to its caller.
--
-- Design: @docs/design/resp-fact-proposal.md@ Rev 6 (§5.1 to §5.4, §8).
-- Plan:   @docs/design/resp-fact-implementation-plan.md@ revision 2.
--
-- The compiler declares one fact per @(builtin, Response arm)@ in
-- 'respFactTable'. A program opts in by writing a FACT REQUEST (§5.1): a def
-- whose @pre@ has a conjunct @(= p T)@, with @p@ a parameter typed by a sum
-- declared in this module, @T@ one of its constructors, and at least one
-- @Response@ parameter. Four syntactic analyses then run over the entry module:
--
--   1. 'factRequests'    which defs request a fact                     (§5.1)
--   2. 'moduleSites'     which builtin each control tag is BOUND to     (§5.2, @Sites@)
--   3. 'deliveredParams' which parameters carry harness-delivered values (§5.3)
--   4. 'exportCondition' the @(export …)@ list closes the import boundary (§5.2)
--
-- 'analyzeRespFacts' composes them. Every failure is a hard error that the
-- checker raises ('LLMLL.TypeCheck.checkStatements'), so @check@, @verify@ and
-- @build@ all stop and nothing is withheld quietly. On success the plan carries:
--
--   * the refinement the emitter seeds on each delivered @Response@ arm binder
--     of a requesting def ('rpRefEnvs', consumed at the @refEnv@ seam of
--     'LLMLL.FixpointEmit.emitFnConstraints');
--   * the PREMISE sites of each program-determined fact ('rpPremises'): a
--     literal argument is folded here at check time, a scalar parameter of the
--     issuing def becomes one @call-pre:<builtin>@ constraint in the emitter;
--   * the disclosure rows the trust report renders under @assumed_facts@
--     ('rpDisclosures'), one per requesting def and fact, naming the premise case
--     (§12: a line that says only "assumed fact" is the discrimination failure
--     the design exists to prevent).
--
-- This module is pure and imports only 'LLMLL.Syntax', 'LLMLL.TypeAdmissibility'
-- and 'LLMLL.HoleAnalysis', so the checker, the emitter and the trust report can
-- all import it without an import cycle. A module with no request sees no
-- analysis, no error, no warning and no @.fq@ change: that is what makes the
-- design opt-in (§5.1).
--
-- Soundness argument, in one paragraph (§5.4, the harness lemma). The console
-- loop hands a step the state @s@ and the response @r@ of ONE turn, and @r@
-- answers the command returned in the same pair as @s@ ('CodegenHs' harness
-- loop). Rule 5.2 says every returned pair whose tag is @T@ carries a command
-- whose head is the one builtin @T@ is bound to. Rule 5.3 says a requesting
-- step's @p@ is a bare copy of @(second s)@ and its @x@ a bare copy of @r@ for
-- the current turn. So @(= p T)@, proved by the caller on the call-pre channel,
-- entails that @x@ is that builtin's reply, and the declared fact for its arm
-- holds of the arm payload. The export condition and the entry-module rule keep
-- every producer, every requesting step and the tag type inside the one module
-- the analysis reads (cells R-5, R-6).
module LLMLL.RespFact
  ( -- * The fact table
    RespFact(..)
  , FactCategory(..)
  , factCategoryName
  , respFactTable
  , respFactsOf
    -- * Requests (§5.1)
  , FactRequest(..)
  , factRequests
    -- * The issuing rule (§5.2)
  , SiteElem(..)
  , SiteArg(..)
  , SitesResult(..)
  , sitesOfDef
  , moduleSites
  , tagBindings
  , pairReturningDefs
    -- * The delivery rule (§5.3)
  , ParamKind(..)
  , Refusal(..)
  , deliveredParams
    -- * The export condition (§5.2)
  , exportCondition
    -- * The composed plan
  , RespFactPlan(..)
  , PremiseSite(..)
  , PremiseCase(..)
  , AssumedFact(..)
  , emptyRespFactPlan
  , analyzeRespFacts
  , respFactPlanOrEmpty
    -- * Helpers shared with tests
  , renderExprS
  , evalClosedBool
  , unboundWarningPrefix
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Maybe (mapMaybe, fromMaybe)
import Data.List (foldl', nub)
import Data.Char (isUpper)

import LLMLL.Syntax
import LLMLL.TypeAdmissibility (AliasMap, builtinAliases, resolveAliasTy, nullaryEnumArity, isScalarLike)
import LLMLL.HoleAnalysis (buildCallGraph)

-- ---------------------------------------------------------------------------
-- The fact table (§6, §7, §8 item 12)
-- ---------------------------------------------------------------------------

-- | Why the fact holds. Only the program-determined category ships (§6): the
-- value property is established by the program's own argument at the issuing
-- site, and the compiler proves that premise ('PremiseSite'). The residue is
-- codegen's pass-through, disclosed on @codegen_semantics_version@.
--
-- A @FactCodegen@ category (the value is fixed by generated code) is
-- deliberately NOT declared: no shipped builtin is in it. @FS-STAT-1@ adds it,
-- so the constructor is not dead code here waiting for a producer.
--
-- ITS FIRING WITNESS IS THE ERROR BRANCH, NOT A CLAMP. This comment said
-- "with its clamp as the firing witness" and that was already wrong when it was
-- written: @fs-capability-trio-proposal.md@ Rev 2 §4 withdrew the clamp on
-- 2026-08-19, because clamping a negative age to zero reports maximal freshness
-- to a liveness check. @wasi.fs.stat@ answers @RErr@ instead, so its @RCode@ arm
-- carries @v >= 0@ because the negative case never reaches the arm.
data FactCategory
  = FactProgram Int   -- ^ program-determined; the Int is the ARGUMENT INDEX of
                      --   the builtin that carries the value into the arm
  | FactCodegen       -- ^ codegen-determined: the generated body cannot publish
                      --   a violating value. There is NO argument and therefore
                      --   NO premise to prove. This is an AXIOM about a sealed
                      --   builtin, of the same class as @bytes-set@'s
                      --   length-preservation fact, and it is DISCLOSED rather
                      --   than discharged (FS-STAT-1).
  deriving (Show, Eq)

-- | The disclosed name of a category (§12). A reader must be able to tell a
-- proved fact from an assumed one, so this is derived and never written as a
-- literal at the disclosure site.
factCategoryName :: FactCategory -> Text
factCategoryName (FactProgram _) = "program-determined"
factCategoryName FactCodegen     = "codegen-determined"

data RespFact = RespFact
  { rfCategory  :: FactCategory
  , rfBinder    :: Name   -- ^ the bound variable of the predicate (always @v@)
  , rfPredicate :: Expr   -- ^ the fact over 'rfBinder', a QF-LIA predicate
  } deriving (Show, Eq)

-- | One entry: @wasi.http.response@ declares its @RCode@ payload
-- @{v : int | v >= 100}@ ('LLMLL.TypeCheck' builtin signature), and that value
-- is the program's own first argument, so the category is program-determined
-- with argument index 0. @wasi.proc.run@ is NOT here: its @RCode@ arm is
-- OS-determined through the @ExitFailure c@ path (§6, §8 item 1).
--
-- A wrong row here is the single unsound direction of the design (§8 item 12),
-- identical in kind to a wrong arity in 'nullaryEnumArity'. The Spec pins the
-- table to exactly this content, and pins the runtime preamble's pass-through.
respFactTable :: Map (Name, Name) RespFact
respFactTable = Map.fromList
  [ ( ("wasi.http.response", "RCode")
    , RespFact (FactProgram 0) "v" (EOp ">=" [EVar "v", ELit (LitInt 100)]) )
  -- FS-STAT-1. The age is the FILESYSTEM's, not an argument the program passes,
  -- so there is no premise and the category is 'FactCodegen'.
  --
  -- THE FACT HOLDS BECAUSE THE NEGATIVE CASE NEVER REACHES THIS ARM. The
  -- emitted 'wasi_fs_stat' answers RErr on a negative computed age; it does NOT
  -- clamp. A clamp would keep this predicate true and make it a lie, by
  -- reporting maximal freshness to a liveness check (SKIP-SILENT-1's class).
  -- Changing that codegen branch INVALIDATES this row.
  , ( ("wasi.fs.stat", "RCode")
    , RespFact FactCodegen "v" (EOp ">=" [EVar "v", ELit (LitInt 0)]) )
  ]

-- | Every @(arm, fact)@ the table declares for one builtin.
respFactsOf :: Name -> [(Name, RespFact)]
respFactsOf b = [ (arm, f) | ((b', arm), f) <- Map.toList respFactTable, b' == b ]

-- ---------------------------------------------------------------------------
-- Shared shapes
-- ---------------------------------------------------------------------------

-- | The five def-like statement forms, with their statement index.
defsOf :: [Statement] -> [(Int, Name, [(Name, Type)], Maybe Type, Contract, Expr)]
defsOf stmts =
  [ (i, n, ps, r, c, b)
  | (i, s) <- zip [0 ..] stmts
  , Just (n, ps, r, c, b) <- [defLike s] ]

defLike :: Statement -> Maybe (Name, [(Name, Type)], Maybe Type, Contract, Expr)
defLike (SDefLogic     n p r c b)   = Just (n, p, r, c, b)
defLike (SDef          n p r c b)   = Just (n, p, r, c, b)
defLike (SDefShell     n p r c b _) = Just (n, p, r, c, b)
defLike (SLetrec       n p r c _ b) = Just (n, p, r, c, b)
defLike (SDefInvariant n p r c b)   = Just (n, p, r, c, b)
defLike _                           = Nothing

-- | The declared sum a type resolves to, with the NAME of the @STypeDef@ whose
-- body is that sum (the innermost name on an alias chain).
sumTypeOf :: AliasMap -> Type -> Maybe (Name, [(Name, Maybe Type)])
sumTypeOf am = go Set.empty
  where
    go seen (TCustom n)
      | n `Set.member` seen = Nothing
      | otherwise = case Map.lookup n am of
          Just (TSumType cs) -> Just (n, cs)
          Just t             -> go (Set.insert n seen) t
          Nothing            -> Nothing
    go seen (TDependent _ b _) = go seen b
    go _ _ = Nothing

-- | The sealed @Response@ sum, by structure (an alias of it counts).
isResponseTy :: AliasMap -> Type -> Bool
isResponseTy am ty = case Map.lookup "Response" builtinAliases of
  Just r  -> resolveAliasTy am ty == r
  Nothing -> False

-- | Uppercase-initial name: the surface convention for a constructor.
isCtorSpelled :: Name -> Bool
isCtorSpelled c = not (T.null c) && isUpper (T.head c)

-- | The command builtins: every @wasi.*@ builtin returns @Command@
-- ('LLMLL.TypeCheck.builtinEnv' §13.9). @seq-commands@ is handled as a form,
-- not as a head (§5.2: take the head of its right operand).
isCommandBuiltin :: Name -> Bool
isCommandBuiltin n = "wasi." `T.isPrefixOf` n

patVars :: Pattern -> [Name]
patVars (PVar x)            = [x]
patVars (PConstructor _ ps) = concatMap patVars ps
patVars _                   = []

-- | A compact s-expression rendering, for error text that names a call site or
-- a form. Kept local: the equivalent renderer in 'LLMLL.TrustReport' cannot be
-- imported here without a cycle.
renderExprS :: Expr -> Text
renderExprS = go
  where
    go (ELit l)       = lit l
    go (EVar n)       = n
    go (EOp op as)    = sx op as
    go (EApp f as)    = sx f as
    go (EPair a b)    = "(pair " <> go a <> " " <> go b <> ")"
    go (EIf c t e)    = "(if " <> go c <> " " <> go t <> " " <> go e <> ")"
    go (EAwait e)     = "(await " <> go e <> ")"
    go (ELet bs b)    = "(let [" <> T.intercalate " " [ "(" <> pat p <> " " <> go e <> ")" | (p, _, e) <- bs ] <> "] " <> go b <> ")"
    go (EMatch s as)  = "(match " <> go s <> " " <> T.intercalate " " [ "(" <> pat p <> " " <> go b <> ")" | (p, b) <- as ] <> ")"
    go (ELambda ps b) = "(fn [" <> T.intercalate " " (map fst ps) <> "] " <> go b <> ")"
    go (EDo _)        = "(do …)"
    go (EHole _)      = "?"
    sx h []  = "(" <> h <> ")"
    sx h as  = "(" <> h <> " " <> T.intercalate " " (map go as) <> ")"
    pat (PVar x)            = x
    pat (PConstructor c []) = "(" <> c <> ")"
    pat (PConstructor c ps) = "(" <> c <> " " <> T.intercalate " " (map pat ps) <> ")"
    pat (PLiteral l)        = lit l
    pat PWildcard           = "_"
    lit (LitInt n)    = T.pack (show n)
    lit (LitFloat f)  = T.pack (show f)
    lit (LitString s) = "\"" <> s <> "\""
    lit (LitBool b)   = if b then "true" else "false"
    lit LitUnit       = "()"

-- ---------------------------------------------------------------------------
-- 1. Requests (§5.1)
-- ---------------------------------------------------------------------------

data FactRequest = FactRequest
  { frDef            :: Name
  , frIdx            :: Int            -- ^ statement index of the def
  , frParams         :: [(Name, Type)]
  , frTagParam       :: Name           -- ^ @p@ in @(= p T)@
  , frTagType        :: Name           -- ^ the @STypeDef@ name of @p@'s sum
  , frTag            :: Name           -- ^ @T@
  , frResponseParams :: [Name]         -- ^ every @Response@ parameter of the def
  } deriving (Show, Eq)

-- | The conjuncts of a clause, split over nested @and@ in either of the two
-- shapes the parser produces: @EOp "and"@ for a written @(and …)@ and
-- @EApp "and"@ for a multi-clause fold ('LLMLL.Parser.foldClauses').
conjuncts :: Expr -> [Expr]
conjuncts (EOp  "and" as) = concatMap conjuncts as
conjuncts (EApp "and" as) = concatMap conjuncts as
conjuncts e               = [e]

-- | @(= x C)@ or @(= C x)@ with @C@ spelled as a constructor, bare or as @(C)@.
tagEquality :: Expr -> Maybe (Name, Name)
tagEquality e = case e of
  EOp  "=" [a, b] -> pick a b
  EApp "=" [a, b] -> pick a b
  _               -> Nothing
  where
    pick a b = case (ctorOf b, ctorOf a) of
      (Just t, _) | EVar x <- a, not (isCtorSpelled x) -> Just (x, t)
      (_, Just t) | EVar x <- b, not (isCtorSpelled x) -> Just (x, t)
      _ -> Nothing
    ctorOf (EVar c)    | isCtorSpelled c = Just c
    ctorOf (EApp c []) | isCtorSpelled c = Just c
    ctorOf _ = Nothing

-- | §5.1: a def holds a fact request when its @pre@ has a conjunct @(= p T)@
-- or @(= T p)@, @p@ is a parameter whose type is a declared sum, @T@ is a
-- constructor of that sum, and the def has a @Response@ parameter. One request
-- per such conjunct.
factRequests :: AliasMap -> [Statement] -> [FactRequest]
factRequests am stmts =
  [ FactRequest n i ps p tyName t respPs
  | (i, n, ps, _, c, _) <- defsOf stmts
  , let respPs = [ v | (v, ty) <- ps, isResponseTy am ty ]
  , not (null respPs)
  , Just pre <- [contractPre c]
  , conj <- conjuncts pre
  , Just (p, t) <- [tagEquality conj]
  , Just pty <- [lookup p ps]
  , Just (tyName, ctors) <- [sumTypeOf am pty]
  , t `elem` map fst ctors ]

-- ---------------------------------------------------------------------------
-- 2. The issuing rule: Sites (§5.2)
-- ---------------------------------------------------------------------------

-- | One collected @(tag, builtin)@ pair, with the builtin's arguments resolved
-- and the def whose body WROTE the pair. When the pair was reached through the
-- substitution row, 'seOriginDef' is the transparent constructor (e.g. @go@)
-- and a 'SAParam' argument names the CALLER whose parameter it resolved to.
data SiteElem = SiteElem
  { seTag       :: Name
  , seBuiltin   :: Name
  , seArgs      :: [SiteArg]
  , seOriginDef :: Name
  , seOriginIdx :: Int
  } deriving (Show, Eq)

-- | A builtin argument after resolution through let copy-propagation and call
-- substitution.
data SiteArg
  = SALit Integer                 -- ^ an int literal (folds at check)
  | SAParam Name Int Name Type    -- ^ (def, def index, parameter, type): a parameter of that def
  | SAOther Text                  -- ^ anything else, rendered
  deriving (Show, Eq)

-- | @Sites(D)@: a set (with the @PARAM@ marker as a flag), or @⊥@ with the def
-- and the form that defeated the recursion. @⊥@ wins over @PARAM@ (§5.2).
-- Positional on purpose: a record selector on a two-constructor sum is partial.
data SitesResult
  = SitesResult [SiteElem] Bool   -- ^ the collected elements; True when some component resolved to an OWN parameter (@PARAM@)
  | SitesBottom Name Text         -- ^ @⊥@: the def whose body holds the form, and why
  deriving (Show, Eq)

unionSites :: SitesResult -> SitesResult -> SitesResult
unionSites b@SitesBottom{} _ = b
unionSites _ b@SitesBottom{} = b
unionSites (SitesResult a p) (SitesResult b q) = SitesResult (a ++ b) (p || q)

-- | What a variable in a pair-returning body is bound to.
data Binding
  = BOwn Name Int Name Type   -- ^ an own parameter of (def, index, name, type)
  | BSubst Expr Env           -- ^ a substituted expression, closed over the env it was written in

-- | The resolution environment of one body: the def being read, and every name
-- in scope. @Nothing@ marks a name rebound by a @let@, a pattern or a @fn@ to a
-- value the rule does not propagate (§5.2: only a command or, for the premise,
-- an int literal is copied).
data Env = Env
  { envDef  :: Name
  , envIdx  :: Int
  , envVars :: Map Name (Maybe Binding)
  }

-- | A resolved tag or command component. 'CBad' names the def whose body holds
-- the offending form, which under the substitution row is the CALLER that
-- supplied the argument, not the def whose body wrote the pair.
data Comp
  = CCtor Name
  | CCmd Name [Expr] Env
  | CLit Integer
  | CParam Name Int Name Type
  | CBad Name Text

data SitesCtx = SitesCtx
  { scCtors    :: Set Name                                        -- ^ constructors of the module's declared sums
  , scPairDefs :: Map Name (Int, [(Name, Type)], Expr)            -- ^ pair-returning defs of the module
  }

resolveExpr :: SitesCtx -> Env -> Expr -> Comp
resolveExpr ctx env e = case e of
  EVar x
    | Just mb <- Map.lookup x (envVars env) -> fromBinding x mb
    | x `Set.member` scCtors ctx            -> CCtor x
    | isCommandBuiltin x                    -> CCmd x [] env
    | otherwise -> CBad (envDef env) ("'" <> x <> "' is neither a constructor of this module, a builtin command, nor a parameter")
  EApp f []
    | Map.notMember f (envVars env), f `Set.member` scCtors ctx -> CCtor f
  EApp "seq-commands" [_, b] -> resolveExpr ctx env b
  EApp f as
    | isCommandBuiltin f -> CCmd f as env
  ELit (LitInt n) -> CLit n
  _ -> CBad (envDef env) ("the form " <> renderExprS e)
  where
    fromBinding _ (Just (BOwn d i p t))  = CParam d i p t
    fromBinding _ (Just (BSubst e' env')) = resolveExpr ctx env' e'
    fromBinding x Nothing = CBad (envDef env) ("'" <> x <> "' is rebound by a let, a pattern or a fn to a value the rule does not propagate")

resolveArg :: SitesCtx -> Env -> Expr -> SiteArg
resolveArg ctx env a = case resolveExpr ctx env a of
  CLit n           -> SALit n
  CParam d i p t   -> SAParam d i p t
  _                -> SAOther (renderExprS a)

-- | The structural recursion of §5.2, in @env@, with @stack@ the pair-returning
-- defs on the current substitution path (a repeat is a cycle, which is @⊥@).
sitesExpr :: SitesCtx -> Env -> [Name] -> Expr -> SitesResult
sitesExpr ctx env stack e = case e of
  EPair (EPair _ tE) cE -> pairRow tE cE
  EPair _ _ ->
    bottom ("the returned pair " <> renderExprS e
            <> " does not write the tag constructor in its state component; write"
            <> " (pair (pair <state> <Tag>) <command>) rather than pairing the incoming state")
  EIf _ a b ->
    sitesExpr ctx env stack a `unionSites` sitesExpr ctx env stack b
  EMatch _ arms ->
    foldr (\(p, b) acc -> sitesExpr ctx (shadow (patVars p) env) stack b `unionSites` acc)
          (SitesResult [] False) arms
  ELet binds body ->
    sitesExpr ctx (foldl' bindLet env binds) stack body
  EApp f as
    | Just (fi, fps, fbody) <- Map.lookup f (scPairDefs ctx) ->
        if f `elem` stack
          then bottom ("the call " <> renderExprS e <> " closes a cycle among pair-returning defs ("
                       <> T.intercalate " -> " (reverse (f : stack)) <> "); the issuing rule needs that graph acyclic")
          else
            let env' = Env f fi (Map.fromList [ (p, Just (BSubst a env)) | ((p, _), a) <- zip fps as ])
            in sitesExpr ctx env' (f : stack) fbody
    | otherwise ->
        bottom ("the call " <> renderExprS e <> " is not to a pair-returning def of this module"
                <> "; a pair-returning callee must be declared in the entry module with a (σ, Command) return")
  EDo _ ->
    bottom "a do body discards every command but the last, so the tag it returns cannot be read against one command; write the tag constructor and the command in one returned pair"
  _ ->
    bottom ("the form " <> renderExprS e <> " is not a returned pair, an if, a match, a let, or a call to a pair-returning def")
  where
    bottom = SitesBottom (envDef env)
    -- A component that went bad in a CALLER's argument names that caller, and
    -- says which pair-writing def it reached, so the reader edits the right def.
    bottomAt d msg
      | d == envDef env = SitesBottom d msg
      | otherwise       = SitesBottom d (msg <> " (reached through the pair returned by '" <> envDef env <> "')")

    shadow vs en = en { envVars = foldr (\v -> Map.insert v Nothing) (envVars en) vs }

    bindLet en (PVar x, _, rhs) =
      let mb = case resolveExpr ctx en rhs of
                 CCmd{} -> Just (BSubst rhs en)
                 CLit{} -> Just (BSubst rhs en)
                 _      -> Nothing
      in en { envVars = Map.insert x mb (envVars en) }
    bindLet en (p, _, _) = shadow (patVars p) en

    pairRow tE cE =
      let tc = resolveExpr ctx env tE
          cc = resolveExpr ctx env cE
      in case (tc, cc) of
           (CCtor t, CCmd b as env') ->
             SitesResult [SiteElem t b (map (resolveArg ctx env') as) (envDef env) (envIdx env)] False
           (CBad d m, _) -> bottomAt d ("the tag component of the returned pair is not a constructor written in the source: " <> m)
           (_, CBad d m) -> bottomAt d ("the command component of the returned pair is not a builtin command: " <> m)
           (CParam{}, CParam{}) -> SitesResult [] True
           (CParam{}, CCmd{})   -> SitesResult [] True
           (CCtor{}, CParam{})  -> SitesResult [] True
           (CParam{}, _) -> bottom ("the command component of the returned pair is not a builtin command: " <> renderExprS cE)
           (_, CParam{}) -> bottom ("the tag component of the returned pair is not a constructor: " <> renderExprS tE)
           _ -> bottom ("the returned pair " <> renderExprS e <> " does not pair a constructor with a builtin command")

-- | The module's pair-returning defs: declared return @(σ, Command)@.
pairReturningDefs :: AliasMap -> [Statement] -> Map Name (Int, [(Name, Type)], Expr)
pairReturningDefs am stmts = Map.fromList
  [ (n, (i, ps, b))
  | (i, n, ps, Just r, _, b) <- defsOf stmts
  , isPairCommand r ]
  where
    isPairCommand t = case resolveAliasTy am t of
      TPair _ c -> resolveAliasTy am c == TCustom "Command"
      _         -> False

-- | @Sites(D)@ for one def by name, or @Nothing@ when it is not pair-returning.
sitesOfDef :: AliasMap -> [Statement] -> Name -> Maybe SitesResult
sitesOfDef am stmts d = do
  (i, ps, body) <- Map.lookup d pairDefs
  pure (sitesExpr ctx (ownEnv d i ps) [d] body)
  where
    pairDefs = pairReturningDefs am stmts
    ctx = SitesCtx (declaredCtors stmts) pairDefs

ownEnv :: Name -> Int -> [(Name, Type)] -> Env
ownEnv d i ps = Env d i (Map.fromList [ (p, Just (BOwn d i p t)) | (p, t) <- ps ])

declaredCtors :: [Statement] -> Set Name
declaredCtors stmts = Set.fromList
  [ c | STypeDef _ (TSumType cs) <- stmts, (c, _) <- cs ]

-- | The module union of §5.2: every pair-returning def whose result is a set
-- (a def whose result carries @PARAM@ contributes nothing of its own and is
-- read through the substitution row at its call sites), plus the @:step@
-- lambda when @def-main@ writes one inline, plus the @:init@ expression.
-- Returns the collected elements and every @⊥@ as @(def, reason)@.
moduleSites :: AliasMap -> [Statement] -> ([SiteElem], [(Name, Text)])
moduleSites am stmts = foldr merge ([], []) (defResults ++ mainResults)
  where
    pairDefs = pairReturningDefs am stmts
    ctx = SitesCtx (declaredCtors stmts) pairDefs
    defResults =
      [ sitesExpr ctx (ownEnv d i ps) [d] body
      | (d, (i, ps, body)) <- Map.toList pairDefs ]
    mainResults = concat
      [ [ sitesExpr ctx (ownEnv ":step" i ps) [] body | ELambda ps body <- [defMainStep m] ]
        ++ [ sitesExpr ctx (Env ":init" i Map.empty) [] ini | Just ini <- [defMainInit m] ]
      | (i, m@SDefMain{}) <- zip [0 ..] stmts ]
    merge (SitesBottom d why) (es, bs) = (es, (d, why) : bs)
    merge (SitesResult _ True) acc     = acc            -- transparent: read at its call sites only
    merge (SitesResult es' False) (es, bs) = (es' ++ es, bs)

-- | Rule 1 of §5.2 over the collected elements: a tag is BOUND when every
-- element carrying it carries the same builtin. Returns the bound map and the
-- unbound tags with the builtins that compete for them.
tagBindings :: [SiteElem] -> (Map Name Name, [(Name, [Name])])
tagBindings elems =
  let byTag = Map.fromListWith (\a b -> nub (b ++ a)) [ (seTag e, [seBuiltin e]) | e <- elems ]
      bound   = Map.mapMaybe (\bs -> case bs of [b] -> Just b; _ -> Nothing) byTag
      unbound = [ (t, bs) | (t, bs) <- Map.toList byTag, length bs > 1 ]
  in (bound, unbound)

-- ---------------------------------------------------------------------------
-- 3. The delivery rule (§5.3)
-- ---------------------------------------------------------------------------

-- | The three kinds of delivered value.
data ParamKind = KState | KTag | KResponse
  deriving (Show, Eq, Ord)

-- | The first call site that refused a parameter.
data Refusal = Refusal
  { rfCaller :: Name   -- ^ the def whose body holds the call (@:step@, @:init@, … for def-main slots)
  , rfCall   :: Text   -- ^ the call, rendered
  , rfArg    :: Text   -- ^ the refused argument, rendered
  , rfWhy    :: Text   -- ^ which row of the grammar it failed
  } deriving (Show, Eq)

paramKind :: AliasMap -> Set Name -> Type -> Maybe ParamKind
paramKind am tagTys ty
  | isResponseTy am ty = Just KResponse
  | Just (n, _) <- sumTypeOf am ty, n `Set.member` tagTys = Just KTag
  | TPair _ b <- resolveAliasTy am ty
  , Just (n, _) <- sumTypeOf am b, n `Set.member` tagTys = Just KState
  | otherwise = Nothing

-- | The walk scope of one body (§5.3, "Scope tracks let and fn bindings").
data Scope = Scope
  { spDef       :: Name
  , spLive      :: Map Name ParamKind   -- ^ delivered names in scope, by kind
  , spShadow    :: Set Name             -- ^ names rebound inside this body
  , spArmTags   :: Set Name             -- ^ (t5): constructors admitted by an enclosing arm
  }

-- | The greatest fixpoint of §5.3. Every tracked parameter (a parameter whose
-- type is a tag type, the @(σ, tag)@ state, or @Response@) starts delivered; a
-- call site that passes an expression outside the grammar removes it; repeat
-- until nothing changes. The @:step@ function's state and response are the
-- harness's sources (§5.4); an in-module call of it is checked like any other.
--
-- Returns, for every tracked @(def, index)@, either @Nothing@ (delivered) or
-- the first refusal.
deliveredParams :: AliasMap -> Set Name -> [Statement] -> Map (Name, Int) (Maybe Refusal)
deliveredParams am tagTys stmts = go (Map.map (const Nothing) tracked)
  where
    ctors = declaredCtors stmts
    defs  = defsOf stmts
    -- (def, params with kinds)
    defKinds :: Map Name [(Name, Maybe ParamKind)]
    defKinds = Map.fromList [ (n, [ (p, paramKind am tagTys t) | (p, t) <- ps ]) | (_, n, ps, _, _, _) <- defs ]
    tracked :: Map (Name, Int) ()
    tracked = Map.fromList [ ((n, i), ()) | (n, ks) <- Map.toList defKinds, (i, (_, Just _)) <- zip [0 ..] ks ]
    -- (t3): an entry-module def of one parameter q whose body is (second q)
    projDefs = Set.fromList [ n | (_, n, [(q, _)], _, _, EApp "second" [EVar q']) <- defs, q == q' ]

    go st =
      let refusals = concatMap (walkSlot st) slots
          st' = foldl' (\m (k, r) -> case Map.lookup k m of
                                       Just Nothing -> Map.insert k (Just r) m   -- first refusal wins
                                       _            -> m) st refusals
      in if st' == st then st else go st'

    -- Every place a call can be written: def bodies and contract clauses, the
    -- def-main slots, top-level expressions and check bodies.
    slots :: [(Name, [(Name, Maybe ParamKind)], [Expr])]
    slots =
      [ (n, ks, b : mapMaybe id [contractPre c, contractPost c])
      | (_, n, _, _, c, b) <- defs, Just ks <- [Map.lookup n defKinds] ]
      ++ concat
      [ case defMainStep m of
          ELambda ps body ->
            [ (":step", [ (p, paramKind am tagTys t) | (p, t) <- ps ], [body]) ]
          _ -> []
        ++ [ (":init", [], [ini]) | Just ini <- [defMainInit m] ]
        ++ [ (":done?", [], [d]) | Just d <- [defMainDone m] ]
        ++ [ (":on-done", [], [d]) | Just d <- [defMainOnDone m] ]
        ++ [ (":status", [], [d]) | Just d <- [defMainStatus m] ]
      | m@SDefMain{} <- stmts ]
      ++ [ ("<top-level>", [], [e]) | SExpr e <- stmts ]
      ++ [ ("<check>", [], [propBody p]) | SCheck p <- stmts ]

    walkSlot st (caller, ks, bodies) =
      let live = Map.fromList
            [ (p, k)
            | (i, (p, Just k)) <- zip [0 ..] ks
            , caller == ":step" || Map.lookup (caller, i) st == Just Nothing ]
          sc = Scope caller live Set.empty Set.empty
      in concatMap (walk st sc) bodies

    walk st sc e = case e of
      EApp f as ->
        let here = case Map.lookup f defKinds of
              Just ks ->
                [ ((f, i), Refusal (spDef sc) (renderExprS e) (renderExprS a) (why sc k a))
                | (i, (a, (_, Just k))) <- zip [0 ..] (zip as ks)
                , not (admits sc k a) ]
              Nothing -> []
        in here ++ concatMap (walk st sc) as
      EOp _ as       -> concatMap (walk st sc) as
      EPair a b      -> walk st sc a ++ walk st sc b
      EIf c t el     -> walk st sc c ++ walk st sc t ++ walk st sc el
      EAwait a       -> walk st sc a
      ELet binds body ->
        let step (sc', acc) (p, _, rhs) = (bindLet sc' p rhs, acc ++ walk st sc' rhs)
            (scB, rs) = foldl' step (sc, []) binds
        in rs ++ walk st scB body
      EMatch scr arms ->
        walk st sc scr ++ concat [ walk st (armScope sc scr p) b | (p, b) <- arms ]
      ELambda ps body -> walk st (shadowAll sc (map fst ps)) body
      EDo steps ->
        let step (sc', acc) (DoStep mn se _) = (maybe sc' (\n -> shadowAll sc' [n]) mn, acc ++ walk st sc' se)
        in snd (foldl' step (sc, []) steps)
      ELit _  -> []
      EVar _  -> []
      EHole _ -> []

    shadowAll sc vs = sc { spLive   = foldr Map.delete (spLive sc) vs
                         , spShadow = foldr Set.insert (spShadow sc) vs }

    -- (t4): a let-bound name whose right side is (t2) or (t3)
    bindLet sc (PVar x) rhs
      | isProjectedTag sc rhs = sc { spLive = Map.insert x KTag (spLive sc), spShadow = Set.delete x (spShadow sc) }
    bindLet sc p _ = shadowAll sc (patVars p)

    -- (t5): inside ((T) …) of a match whose scrutinee is (t1) to (t4)
    armScope sc scr (PConstructor c [])
      | c `Set.member` ctors, isDeliveredTag sc scr = sc { spArmTags = Set.insert c (spArmTags sc) }
    armScope sc _ p = shadowAll sc (patVars p)

    admits sc KState    e = isDeliveredState sc e
    admits sc KResponse e = case e of
      EVar v -> Map.lookup v (spLive sc) == Just KResponse
      _      -> False
    admits sc KTag      e = isDeliveredTag sc e

    isDeliveredState sc (EVar v) = Map.lookup v (spLive sc) == Just KState
    isDeliveredState _ _         = False

    -- (t2), (t3)
    isProjectedTag sc e = case e of
      EApp "second" [EVar v] -> isDeliveredState sc (EVar v)
      EApp f [EVar v] | f `Set.member` projDefs -> isDeliveredState sc (EVar v)
      _ -> False

    -- (t1) to (t5)
    isDeliveredTag sc e = case e of
      EVar v  | Map.lookup v (spLive sc) == Just KTag -> True                                -- (t1), (t4)
      EVar c  | c `Set.member` ctors, Set.notMember c (spShadow sc), c `Set.member` spArmTags sc -> True   -- (t5)
      EApp c [] | c `Set.member` ctors, Set.notMember c (spShadow sc), c `Set.member` spArmTags sc -> True -- (t5)
      _ -> isProjectedTag sc e                                                                   -- (t2), (t3)

    why sc k a = case a of
      EVar v
        | v `Set.member` spShadow sc -> "'" <> v <> "' is rebound by a let, a pattern or a fn parameter inside '" <> spDef sc <> "'"
        | v `Set.member` ctors ->
            "the literal tag '" <> v <> "' is written outside a ((" <> v <> ") …) arm of a match on a delivered tag"
        | Just _ <- lookup v =<< Map.lookup (spDef sc) defKinds ->
            "'" <> v <> "' is a parameter of '" <> spDef sc <> "' that is not itself delivered"
        | otherwise -> "'" <> v <> "' is not a parameter of '" <> spDef sc <> "'"
      EApp c [] | c `Set.member` ctors ->
        "the literal tag '" <> c <> "' is written outside a ((" <> c <> ") …) arm of a match on a delivered tag"
      EApp "second" _ -> "a projection of a value that is not the delivered state"
      EApp "first" _  -> "a projection other than second of the state is not a delivered tag"
      EApp f _
        | f `Set.member` ctors || isCtorSpelled f -> "a constructed value is not delivered"
        | otherwise -> "a call result is not delivered"
      ELit _  -> "a literal is not delivered"
      _ -> "the form is not in the delivery grammar for a " <> kindName k
    kindName KState = "state"
    kindName KTag = "tag"
    kindName KResponse = "response"

-- ---------------------------------------------------------------------------
-- 4. The export condition (§5.2)
-- ---------------------------------------------------------------------------

-- | A module with a request must declare an @(export …)@ list, and the list
-- must name no constructor of a control-tag type and no def from whose body a
-- requesting def is reachable. @(export)@ satisfies both.
exportCondition :: [Statement] -> [FactRequest] -> [Text]
exportCondition _ [] = []
exportCondition stmts reqs@(r0 : _) =
  case [ ns | SExport ns <- stmts ] of
    [] -> [ "RESP-FACT-1: '" <> frDef r0 <> "' requests a fact, so this module must declare an (export …) list"
            <> " that names no constructor of '" <> frTagType r0 <> "' and no def that reaches a requesting def;"
            <> " write (export) to export nothing" ]
    lists -> concatMap check (concat lists)
  where
    tagTys   = Set.fromList (map frTagType reqs)
    tagCtors = Map.fromList [ (c, ty) | STypeDef ty (TSumType cs) <- stmts, ty `Set.member` tagTys, (c, _) <- cs ]
    reqDefs  = Set.fromList (map frDef reqs)
    graph    = buildCallGraph stmts
    -- reverse closure: defs from which a requesting def is reachable
    reaches  = closure reqDefs (Map.fromListWith (++) [ (callee, [caller]) | (caller, callees) <- Map.toList graph, callee <- callees ])
    closure seen rev =
      let next = Set.fromList (concat [ fromMaybe [] (Map.lookup n rev) | n <- Set.toList seen ])
          seen' = Set.union seen next
      in if seen' == seen then seen else closure seen' rev
    firstReached n = case [ r | r <- Set.toList reqDefs, r == n || pathTo n r ] of
      (r : _) -> r
      []      -> frDef r0
    pathTo from to = to `Set.member` forward (Set.singleton from)
      where
        forward seen =
          let next = Set.fromList (concat [ fromMaybe [] (Map.lookup n graph) | n <- Set.toList seen ])
              seen' = Set.union seen next
          in if seen' == seen then seen else forward seen'
    check n
      | Just ty <- Map.lookup n tagCtors =
          [ "RESP-FACT-1: the export list names '" <> n <> "', a constructor of the control-tag type '" <> ty
            <> "'; an importer that opens it could produce the tag, so it cannot be exported" ]
      | n `Set.member` reaches =
          [ "RESP-FACT-1: the export list names '" <> n <> "', from whose body the requesting def '" <> firstReached n
            <> "' is reachable; an importer could call it with a response the harness did not deliver, so it cannot be exported" ]
      | otherwise = []

-- ---------------------------------------------------------------------------
-- The composed plan
-- ---------------------------------------------------------------------------

-- | How the program-determined premise of one fact is discharged at one
-- issuing site (§9 row "program-determined premise").
data PremiseCase
  = PremiseFolded Integer        -- ^ a literal argument; folded at check and it passed
  | PremiseParam Name Int Name   -- ^ (issuing def, its index, its scalar parameter): the emitter proves
                                 --   @pre(def) ⇒ fact[v := param]@ as one @call-pre:<builtin>@ constraint
  deriving (Show, Eq)

data PremiseSite = PremiseSite
  { psTag       :: Name
  , psBuiltin   :: Name
  , psArm       :: Name
  , psFact      :: RespFact
  , psCase      :: PremiseCase
  , psOriginDef :: Name       -- ^ the def whose body wrote the pair
  , psOriginIdx :: Int
  } deriving (Show, Eq)

-- | One disclosure row (§12): per requesting def, per @(tag, builtin, arm)@.
data AssumedFact = AssumedFact
  { afDef       :: Name
  , afTag       :: Name
  , afBuiltin   :: Name
  , afArm       :: Name
  , afPredicate :: Text   -- ^ rendered, e.g. @{v : int | (>= v 100)}@
  , afCategory  :: Text   -- ^ @program-determined@
  , afPremise   :: Text   -- ^ @folded-literal@ and/or @call-pre:<issuing def>@, comma-separated
  } deriving (Show, Eq)

data RespFactPlan = RespFactPlan
  { rpRefEnvs     :: Map Name [(Name, (Name, Expr))]  -- ^ def → [(@x$Arm@, (binder, predicate))]
  , rpPremises    :: [PremiseSite]
  , rpDisclosures :: [AssumedFact]
  , rpWarnings    :: [Text]
  , rpBindings    :: Map Name Name                    -- ^ bound tag → builtin
  , rpRequests    :: [FactRequest]
  } deriving (Show, Eq)

emptyRespFactPlan :: RespFactPlan
emptyRespFactPlan = RespFactPlan Map.empty [] [] [] Map.empty []

respFactPlanOrEmpty :: Either [Text] RespFactPlan -> RespFactPlan
respFactPlanOrEmpty = either (const emptyRespFactPlan) id

-- | The warning's stable prefix, so a consumer can key on it.
unboundWarningPrefix :: Text
unboundWarningPrefix = "W-RESP-FACT-UNBOUND"

-- | Run every rule over one module. @Left@ is the list of hard errors; @Right@
-- the plan. A module with no request returns the empty plan without reading
-- anything else.
analyzeRespFacts :: AliasMap -> [Statement] -> Either [Text] RespFactPlan
analyzeRespFacts am0 stmts
  | null reqs = Right emptyRespFactPlan
  | not (null structural) = Left structural
  | not (null errs) = Left errs
  | otherwise = Right RespFactPlan
      { rpRefEnvs     = refEnvs
      , rpPremises    = premises
      , rpDisclosures = disclosures
      , rpWarnings    = warnings
      , rpBindings    = bound
      , rpRequests    = reqs
      }
  where
    am   = Map.union am0 builtinAliases
    reqs = factRequests am stmts
    localTypes = Set.fromList [ n | STypeDef n _ <- stmts ]
    hasConsoleMain = or [ True | SDefMain { defMainMode = ModeConsole } <- stmts ]
    tagTys = Set.fromList (map frTagType reqs)

    -- Entry-module rule and tag-type shape (§5.2, §8 item 5)
    structural = nub $ concat
      [ [ "RESP-FACT-1: '" <> frDef r <> "' requests a fact on '" <> frTagType r <> "', which is declared in an imported module;"
          <> " the control-tag type, every pair-returning def, def-main and every requesting step must be statements of the entry module"
        | Set.notMember (frTagType r) localTypes ]
        ++
        [ "RESP-FACT-1: '" <> frDef r <> "' requests a fact, but this module holds no console def-main;"
          <> " the delivery rule takes its source from :step, which lives beside def-main"
        | not hasConsoleMain ]
        ++
        [ "RESP-FACT-1: '" <> frTagType r <> "' carries a payload on some constructor, so it is not a control tag;"
          <> " '" <> frDef r <> "' preconditions on it and would fall back to contract-only verification. Move the payload into the state and leave the tag nullary"
        | Set.member (frTagType r) localTypes, nullaryEnumArity am (TCustom (frTagType r)) == Nothing ]
      | r <- reqs ]

    -- Sites and bindings (§5.2)
    (elems, bottoms) = moduleSites am stmts
    (bound, unbound) = tagBindings elems
    bottomErrs = nub [ "RESP-FACT-1: the issuing rule cannot read the pair returned by '" <> d <> "': " <> why | (d, why) <- bottoms ]
    requestedTags = nub (map frTag reqs)
    warnings =
      [ unboundWarningPrefix <> ": '" <> t <> "' pairs with more than one builtin (" <> T.intercalate ", " bs
        <> "), so it binds to nothing and the fact requested in '" <> T.intercalate "', '" [ frDef r | r <- reqs, frTag r == t ] <> "' is withheld"
      | (t, bs) <- unbound, t `elem` requestedTags ]
      ++
      [ "W-RESP-FACT-NONE: '" <> frTag r <> "' " <> reason <> ", so the request in '" <> frDef r <> "' receives no fact"
      | r <- reqs
      , Just reason <- [ case Map.lookup (frTag r) bound of
                           Nothing | frTag r `elem` map fst unbound -> Nothing
                                   | otherwise -> Just "is written in no returned pair of this module"
                           Just b | null (respFactsOf b) -> Just ("is bound to '" <> b <> "', which declares no fact")
                                  | otherwise -> Nothing ] ]

    -- Delivery (§5.3)
    delivered = deliveredParams am tagTys stmts
    paramIndex r p = lookup p (zip (map fst (frParams r)) [0 ..])
    deliveryErrs = nub
      [ "RESP-FACT-1: in '" <> rfCaller ref <> "', the call " <> rfCall ref <> " passes " <> rfArg ref
        <> " for the parameter '" <> p <> "' of '" <> frDef r <> "', which is not delivered: " <> rfWhy ref
        <> ". A requesting def must receive its tag and its Response from :step through bare variables (§5.3)"
      | r <- reqs
      , p <- frTagParam r : frResponseParams r
      , Just i <- [paramIndex r p]
      , Just (Just ref) <- [Map.lookup (frDef r, i) delivered] ]

    -- Export condition (§5.2)
    exportErrs = exportCondition stmts reqs

    -- Premise sites (§9)
    (premises, premiseErrs) = foldr collect ([], []) elems
    collect el (ps, es)
      | Just b <- Map.lookup (seTag el) bound, b == seBuiltin el, seTag el `elem` requestedTags =
          foldr (site el) (ps, es) (respFactsOf b)
      | otherwise = (ps, es)
    -- FS-STAT-1: this was `let FactProgram i = rfCategory f`, an IRREFUTABLE
    -- pattern that a second constructor makes partial. A 'FactCodegen' fact
    -- emits NO premise site and NO error: an axiom has no argument to check,
    -- which is exactly what distinguishes it from a program-determined fact.
    site _ (_, f) acc
      | FactCodegen <- rfCategory f = acc
    site el (arm, f) (ps, es) =
      let i = case rfCategory f of
                FactProgram k -> k
                FactCodegen   -> error "unreachable: FactCodegen is handled above"
          here = "at the pair returned by '" <> seOriginDef el <> "' for '" <> seTag el <> "'"
      in case drop i (seArgs el) of
           (SALit n : _) -> case evalClosedBool (substVar (rfBinder f) (ELit (LitInt n)) (rfPredicate f)) of
             Just True  -> (PremiseSite (seTag el) (seBuiltin el) arm f (PremiseFolded n) (seOriginDef el) (seOriginIdx el) : ps, es)
             Just False -> (ps, ("RESP-FACT-1: " <> here <> ", the literal " <> T.pack (show n) <> " passed to '" <> seBuiltin el
                                <> "' violates the declared fact " <> renderFact f <> " for arm '" <> arm <> "'") : es)
             Nothing    -> (ps, ("RESP-FACT-1: " <> here <> ", the declared fact " <> renderFact f <> " does not fold on the literal " <> T.pack (show n)) : es)
           (SAParam d di p t : _)
             | isScalarLike am t -> (PremiseSite (seTag el) (seBuiltin el) arm f (PremiseParam d di p) (seOriginDef el) (seOriginIdx el) : ps, es)
             | otherwise -> (ps, ("RESP-FACT-1: " <> here <> ", argument " <> T.pack (show i) <> " of '" <> seBuiltin el
                                 <> "' is the non-scalar parameter '" <> p <> "' of '" <> d <> "'; it must be an int literal or a scalar parameter of the issuing def") : es)
           (SAOther rendered : _) -> (ps, ("RESP-FACT-1: " <> here <> ", argument " <> T.pack (show i) <> " of '" <> seBuiltin el
                                          <> "' is " <> rendered <> "; it must be an int literal or a scalar parameter of the issuing def, so that the fact's premise can be proved") : es)
           [] -> (ps, ("RESP-FACT-1: " <> here <> ", '" <> seBuiltin el <> "' has no argument " <> T.pack (show i)) : es)

    errs = bottomErrs ++ deliveryErrs ++ exportErrs ++ premiseErrs

    -- Refinement entries and disclosures, per requesting def whose tag is bound
    refEnvs = Map.fromListWith (++)
      [ (frDef r, [ (x <> "$" <> arm, (rfBinder f, rfPredicate f)) | x <- frResponseParams r, (arm, f) <- facts ])
      | r <- reqs
      , Just b <- [Map.lookup (frTag r) bound]
      , let facts = respFactsOf b
      , not (null facts) ]
    disclosures =
      [ AssumedFact (frDef r) (frTag r) b arm (renderFact f)
                    (factCategoryName (rfCategory f)) (premiseText f (frTag r) b)
      | r <- reqs
      , Just b <- [Map.lookup (frTag r) bound]
      , (arm, f) <- respFactsOf b ]
    -- FS-STAT-1: a 'FactCodegen' fact has no premise site, so the list
    -- comprehension below yields nothing and 'T.intercalate' renders "". An
    -- EMPTY FIELD READS AS A MISSING VALUE rather than as an absent obligation,
    -- which is the opposite of what this row must say. Name the axiom instead.
    premiseText f t b = case rfCategory f of
      FactCodegen -> "codegen:" <> b
      FactProgram _ -> T.intercalate ", " $ nub
        [ case psCase p of
            PremiseFolded _   -> "folded-literal"
            PremiseParam d _ _ -> "call-pre:" <> d
        | p <- premises, psTag p == t, psBuiltin p == b ]

renderFact :: RespFact -> Text
renderFact f = "{" <> rfBinder f <> " : int | " <> renderExprS (rfPredicate f) <> "}"

substVar :: Name -> Expr -> Expr -> Expr
substVar x r = go
  where
    go e = case e of
      EVar v | v == x -> r
      EOp op as  -> EOp op (map go as)
      EApp f as  -> EApp f (map go as)
      EIf c t el -> EIf (go c) (go t) (go el)
      _          -> e

-- | Evaluate a closed QF-LIA predicate over int literals. @Nothing@ when a leaf
-- is not a literal or an operator is outside the fragment.
evalClosedBool :: Expr -> Maybe Bool
evalClosedBool e = case e of
  ELit (LitBool b) -> Just b
  EOp "and" as  -> and <$> mapM evalClosedBool as
  EApp "and" as -> and <$> mapM evalClosedBool as
  EOp "or" as   -> or <$> mapM evalClosedBool as
  EApp "or" as  -> or <$> mapM evalClosedBool as
  EOp "not" [a] -> not <$> evalClosedBool a
  EApp "not" [a] -> not <$> evalClosedBool a
  EOp op [a, b] -> cmp op a b
  EApp op [a, b] -> cmp op a b
  _ -> Nothing
  where
    cmp op a b = do
      x <- evalClosedInt a
      y <- evalClosedInt b
      case op of
        ">=" -> Just (x >= y)
        ">"  -> Just (x > y)
        "<=" -> Just (x <= y)
        "<"  -> Just (x < y)
        "="  -> Just (x == y)
        "/=" -> Just (x /= y)
        "!=" -> Just (x /= y)
        _    -> Nothing

evalClosedInt :: Expr -> Maybe Integer
evalClosedInt e = case e of
  ELit (LitInt n) -> Just n
  EOp op [a, b]   -> arith op a b
  EApp op [a, b]  -> arith op a b
  _ -> Nothing
  where
    arith op a b = do
      x <- evalClosedInt a
      y <- evalClosedInt b
      case op of
        "+" -> Just (x + y)
        "-" -> Just (x - y)
        "*" -> Just (x * y)
        _   -> Nothing
