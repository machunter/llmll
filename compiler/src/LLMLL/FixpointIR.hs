-- |
-- Module      : LLMLL.FixpointIR
-- Description : Intermediate representation for liquid-fixpoint .fq constraint files.
--
-- D4: Decoupled verification backend.
-- Rather than integrating LiquidHaskell as a GHC plugin (fragile, version-locked),
-- we emit .fq constraints directly from the LLMLL typed AST and run liquid-fixpoint
-- as a standalone binary.
--
-- Coverage: QF linear integer arithmetic only.
-- Non-linear sites are flagged as HProofRequired and skipped (D3).

module LLMLL.FixpointIR
  ( -- * Sorts
    FQSort(..)
    -- * Predicates
  , FQPred(..)
  , FQBinOp(..)
    -- * Refinement type
  , FQReft(..)
    -- * Binders (environment entries)
  , FQBind(..)
  , FQBindId
    -- * Constraints
  , FQConstraint(..)
  , FQConstraintId
    -- * Qualifiers
  , FQQualifier(..)
    -- * Data declarations (ADT sorts)
  , FQDataDecl(..)
    -- * Top-level .fq file
  , FQFile(..)
  , emptyFQFile
    -- * Emission to text
  , emitFQFile
  ) where

import Data.Text (Text)
import qualified Data.Text as T

-- ---------------------------------------------------------------------------
-- Sorts
-- ---------------------------------------------------------------------------

-- | Supported liquid-fixpoint base sorts (linear arithmetic fragment).
data FQSort
  = FQInt            -- ^ int
  | FQBool           -- ^ bool
  | FQUnit           -- ^ unit (for functions returning ())
  | FQData Text      -- ^ named ADT sort, e.g. Color
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------

data FQBinOp
  = FQGe   -- ^ >=
  | FQGt   -- ^ >
  | FQLe   -- ^ <=
  | FQLt   -- ^ <
  | FQEq   -- ^ =
  | FQNeq  -- ^ /=
  | FQAdd  -- ^ +
  | FQSub  -- ^ -
  deriving (Show, Eq)

data FQPred
  = FQTrue
  | FQFalse
  | FQVar Text                        -- ^ variable reference, e.g. "v", "n"
  | FQLit Integer                     -- ^ integer literal
  | FQBinPred FQBinOp FQPred FQPred  -- ^ comparison: p1 >= p2
  | FQBinArith FQBinOp FQPred FQPred -- ^ arithmetic: p1 + p2
  | FQAnd [FQPred]
  | FQOr  [FQPred]
  | FQNot FQPred
  | FQKVar Text [FQPred]              -- ^ $k0(v) — wf constraint variable
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Refinement type
-- ---------------------------------------------------------------------------

-- | A liquid-fixpoint refinement type: { v : sort | pred }
data FQReft = FQReft
  { reftVar  :: Text    -- ^ refinement variable name (usually "v")
  , reftSort :: FQSort
  , reftPred :: FQPred
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Binders
-- ---------------------------------------------------------------------------

type FQBindId = Int

-- | Environment binder: bind N name : { v : sort | pred }
data FQBind = FQBind
  { bindId   :: FQBindId
  , bindName :: Text
  , bindReft :: FQReft
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------------------

type FQConstraintId = Int

-- | A subtyping constraint: env ⊢ lhs <: rhs
data FQConstraint = FQConstraint
  { conId  :: FQConstraintId
  , conEnv :: [FQBindId]     -- ^ binder IDs in scope
  , conLhs :: FQReft
  , conRhs :: FQReft
  , conTag :: [Text]         -- ^ diagnostic metadata (function name, clause)
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Qualifiers
-- ---------------------------------------------------------------------------

-- | A qualifier template: qualif Name(params): body
data FQQualifier = FQQualifier
  { qualName   :: Text
  , qualParams :: [(Text, FQSort)]  -- ^ (param name, sort)
  , qualBody   :: FQPred
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Data type declarations (ADT sorts)
-- ---------------------------------------------------------------------------

-- | data Name arity = [ Ctor arity | ... ]
data FQDataDecl = FQDataDecl
  { ddName  :: Text
  , ddArity :: Int
  , ddCtors :: [(Text, Int)]  -- ^ (ctor name, ctor arity)
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Top-level .fq file
-- ---------------------------------------------------------------------------

data FQFile = FQFile
  { fqDataDecls   :: [FQDataDecl]
  , fqQualifiers  :: [FQQualifier]
  , fqBinds       :: [FQBind]
  , fqConstraints :: [FQConstraint]
  } deriving (Show, Eq)

emptyFQFile :: FQFile
emptyFQFile = FQFile [] [] [] []

-- ---------------------------------------------------------------------------
-- Emission to .fq text
-- ---------------------------------------------------------------------------

emitFQFile :: FQFile -> Text
emitFQFile f = T.unlines $
    map emitDataDecl  (fqDataDecls f)
 ++ map emitQualifier (fqQualifiers f)
 ++ map emitBind      (fqBinds f)
 ++ map emitConstraint (fqConstraints f)

emitSort :: FQSort -> Text
emitSort FQInt      = "int"
emitSort FQBool     = "bool"
emitSort FQUnit     = "unit"
emitSort (FQData n) = n

emitPred :: FQPred -> Text
emitPred FQTrue               = "true"
emitPred FQFalse              = "false"
emitPred (FQVar v)            = v
emitPred (FQLit n)            = T.pack (show n)
emitPred (FQBinPred op l r)   = "(" <> emitPred l <> " " <> emitOp op <> " " <> emitPred r <> ")"
emitPred (FQBinArith op l r)  = "(" <> emitPred l <> " " <> emitOp op <> " " <> emitPred r <> ")"
emitPred (FQAnd [])           = "true"
emitPred (FQAnd ps)           = T.intercalate " && " (map emitPred ps)
emitPred (FQOr  [])           = "false"
emitPred (FQOr  ps)           = T.intercalate " || " (map emitPred ps)
emitPred (FQNot p)            = "(not " <> emitPred p <> ")"
emitPred (FQKVar k args)      = "$" <> k <> "(" <> T.intercalate "," (map emitPred args) <> ")"

emitOp :: FQBinOp -> Text
emitOp FQGe  = ">="
emitOp FQGt  = ">"
emitOp FQLe  = "<="
emitOp FQLt  = "<"
emitOp FQEq  = "="
emitOp FQNeq = "/="
emitOp FQAdd = "+"
emitOp FQSub = "-"

emitReft :: FQReft -> Text
emitReft r =
  "{ " <> reftVar r <> " : " <> emitSort (reftSort r)
  <> " | " <> emitPred (reftPred r) <> " }"

emitBind :: FQBind -> Text
emitBind b =
  "bind " <> T.pack (show (bindId b))
  <> " " <> bindName b
  <> " : " <> emitReft (bindReft b)

emitConstraint :: FQConstraint -> Text
emitConstraint c = T.unlines
  [ "constraint:"
  , "  id " <> T.pack (show (conId c))
  , "  tag [" <> T.intercalate "; " (conTag c) <> "]"
  , "  env [" <> T.intercalate "; " (map (T.pack . show) (conEnv c)) <> "]"
  , "  lhs " <> emitReft (conLhs c)
  , "  rhs " <> emitReft (conRhs c)
  ]

emitQualifier :: FQQualifier -> Text
emitQualifier q =
  "qualif " <> qualName q
  <> "(" <> T.intercalate ", " (map emitParam (qualParams q)) <> ")"
  <> ": (" <> emitPred (qualBody q) <> ")"
  where
    emitParam (nm, srt) = nm <> " : " <> emitSort srt

emitDataDecl :: FQDataDecl -> Text
emitDataDecl d =
  "data " <> ddName d <> " " <> T.pack (show (ddArity d))
  <> " = [" <> T.intercalate " | " (map emitCtor (ddCtors d)) <> "]"
  where
    emitCtor (nm, ar) = nm <> " " <> T.pack (show ar)
