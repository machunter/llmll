{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.AstEmit
-- Description : Serialise a [Statement] AST to JSON-AST format.
--
-- This is the exact inverse of 'LLMLL.ParserJSON'. The round-trip property:
--
--   parseJSONAST fp (emitJsonAST stmts) == Right stmts
--
-- …must hold for all valid programs. Any divergence is a bug.
--
-- Output is pretty-printed JSON (2-space indent) for human readability
-- and regression-diff friendliness.
module LLMLL.AstEmit
  ( emitJsonAST
  , stmtToJson
  , exprToJson
  , typeToJson
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import Data.Aeson (Value(..), object, (.=), toJSON, encode)
import Data.Aeson.Encode.Pretty (encodePretty', defConfig, confIndent, Indent(..))
import qualified Data.Vector as V

import LLMLL.Syntax
import LLMLL.ParserJSON (expectedSchemaVersion)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Serialise a list of statements to a pretty-printed JSON-AST byte string.
emitJsonAST :: [Statement] -> BL.ByteString
emitJsonAST stmts =
  encodePretty' cfg $
    object
      [ "schemaVersion" .= expectedSchemaVersion
      , "llmll_version" .= expectedSchemaVersion
      , "statements"    .= map stmtToJson stmts
      ]
  where
    cfg = defConfig { confIndent = Spaces 2 }

-- ---------------------------------------------------------------------------
-- Statement serialiser
-- ---------------------------------------------------------------------------

stmtToJson :: Statement -> Value
stmtToJson (SDefLogic name params _ret (Contract mPre mPost) body) =
  object $
    [ "kind"   .= ("def-logic" :: Text)
    , "name"   .= name
    , "params" .= map typedParamToJson params
    , "body"   .= exprToJson body
    ] ++
    maybe [] (\e -> ["pre"  .= exprToJson e]) mPre  ++
    maybe [] (\e -> ["post" .= exprToJson e]) mPost

stmtToJson (SDefInterface name fns) =
  object
    [ "kind"    .= ("def-interface" :: Text)
    , "name"    .= name
    , "methods" .= map ifaceMethodToJson fns
    ]
  where
    ifaceMethodToJson (n, ty) =
      object ["name" .= n, "fn_type" .= typeToJson ty]

stmtToJson (STypeDef name ty) =
  object
    [ "kind" .= ("type-decl" :: Text)
    , "name" .= name
    , "body" .= typeBodyToJson ty
    ]

stmtToJson (SCheck (Property desc bindings body)) =
  object
    [ "kind"    .= ("check" :: Text)
    , "label"   .= desc
    , "for_all" .= object
        [ "kind"     .= ("for-all" :: Text)
        , "bindings" .= map typedParamToJson bindings
        , "body"     .= exprToJson body
        ]
    ]

stmtToJson (SImport (Import path mIface mCap)) =
  object $
    [ "kind" .= ("import" :: Text)
    , "path" .= path
    ] ++
    maybe [] (\ms -> ["interface" .= map ifaceMethJ ms]) mIface ++
    maybe [] (\c  -> ["capability" .= capToJson c])     mCap
  where
    ifaceMethJ (n, ty) = object ["name" .= n, "fn_type" .= typeToJson ty]

stmtToJson (SExpr e) =
  -- Gen-decl and bare expressions are stored as SExpr
  object
    [ "kind" .= ("gen-decl" :: Text)
    , "type_name" .= ("" :: Text)
    , "body" .= exprToJson e
    ]

stmtToJson (SDefMain mode mInit step mRead mDone mOnDone) =
  -- No JSON schema node for def-main yet — emit as a comment-like object
  object $
    [ "kind" .= ("def-main" :: Text)
    , "mode" .= entryModeLabel mode
    , "step" .= exprToJson step
    ] ++
    maybe [] (\e -> ["init"    .= exprToJson e]) mInit    ++
    maybe [] (\e -> ["read"    .= exprToJson e]) mRead    ++
    maybe [] (\e -> ["done?"   .= exprToJson e]) mDone    ++
    maybe [] (\e -> ["on-done" .= exprToJson e]) mOnDone
  where
    entryModeLabel ModeConsole  = "console" :: Text
    entryModeLabel ModeCli      = "cli"
    entryModeLabel (ModeHttp p) = "http:" <> T.pack (show p)

-- v0.2 module system nodes
stmtToJson (SOpen path mNames) =
  object $
    [ "kind" .= ("open" :: Text)
    , "path" .= T.intercalate "." path
    ] ++
    maybe [] (\ns -> ["names" .= ns]) mNames

stmtToJson (SExport names) =
  object
    [ "kind"  .= ("export" :: Text)
    , "names" .= names
    ]

-- ---------------------------------------------------------------------------
-- Type serialiser
-- ---------------------------------------------------------------------------

typeToJson :: Type -> Value
typeToJson TInt              = object ["kind" .= ("primitive" :: Text), "name" .= ("int"    :: Text)]
typeToJson TFloat            = object ["kind" .= ("primitive" :: Text), "name" .= ("float"  :: Text)]
typeToJson TString           = object ["kind" .= ("primitive" :: Text), "name" .= ("string" :: Text)]
typeToJson TBool             = object ["kind" .= ("primitive" :: Text), "name" .= ("bool"   :: Text)]
typeToJson TUnit             = object ["kind" .= ("primitive" :: Text), "name" .= ("unit"   :: Text)]
typeToJson (TBytes n)        = object ["kind" .= ("bytes" :: Text),     "length" .= n]
typeToJson (TList t)         = object ["kind" .= ("list" :: Text),      "elem_type" .= typeToJson t]
typeToJson (TMap k v)        = object ["kind" .= ("map" :: Text),       "key_type" .= typeToJson k, "val_type" .= typeToJson v]
typeToJson (TResult t e)     = object ["kind" .= ("result" :: Text),    "ok_type" .= typeToJson t,  "err_type" .= typeToJson e]
typeToJson (TPromise t)      = object ["kind" .= ("promise" :: Text),   "inner_type" .= typeToJson t]
typeToJson (TFn args ret)    = object
  [ "kind"        .= ("fn-type" :: Text)
  , "params"      .= map (\t -> object ["name" .= ("" :: Text), "param_type" .= typeToJson t]) args
  , "return_type" .= typeToJson ret
  ]
typeToJson (TDependent bindName base constraint) = object
  [ "kind"      .= ("where" :: Text)
  , "binding"   .= bindName
  , "base_type" .= typeToJson base
  , "predicate" .= exprToJson constraint
  ]
typeToJson TDelegationError  = object ["kind" .= ("named" :: Text), "name" .= ("DelegationError" :: Text)]
typeToJson (TVar n)          = object ["kind" .= ("named" :: Text), "name" .= n]
typeToJson (TCustom "Command") = object ["kind" .= ("command" :: Text)]
typeToJson (TCustom n)       = object ["kind" .= ("named" :: Text), "name" .= n]

-- | Serialise a type in type-decl body position (handles sum types).
typeBodyToJson :: Type -> Value
typeBodyToJson (TCustom label) =
  -- Reconstruct sum type if it looks like "A | B | C"
  let parts = T.splitOn " | " label
  in if length parts > 1
       then object
              [ "kind"     .= ("sum" :: Text)
              , "variants" .= map (\c -> object ["constructor" .= c, "payload" .= typeToJson TUnit]) parts
              ]
       else object ["kind" .= ("named" :: Text), "name" .= label]
typeBodyToJson t = typeToJson t

-- ---------------------------------------------------------------------------
-- Expression serialiser
-- ---------------------------------------------------------------------------

exprToJson :: Expr -> Value
exprToJson (ELit (LitInt n))    = object ["kind" .= ("lit-int"    :: Text), "value" .= n]
exprToJson (ELit (LitFloat d))  = object ["kind" .= ("lit-float"  :: Text), "value" .= d]
exprToJson (ELit (LitString s)) = object ["kind" .= ("lit-string" :: Text), "value" .= s]
exprToJson (ELit (LitBool b))   = object ["kind" .= ("lit-bool"   :: Text), "value" .= b]
exprToJson (ELit LitUnit)       = object ["kind" .= ("lit-unit"   :: Text)]
exprToJson (EVar n)             = object ["kind" .= ("var"        :: Text), "name"  .= n]

exprToJson (ELet bindings body) =
  object
    [ "kind"     .= ("let" :: Text)
    , "bindings" .= map bindingToJson bindings
    , "body"     .= exprToJson body
    ]
  where
    bindingToJson (n, _, e) = object ["name" .= n, "expr" .= exprToJson e]

exprToJson (EIf cond t f) =
  object
    [ "kind"        .= ("if" :: Text)
    , "cond"        .= exprToJson cond
    , "then_branch" .= exprToJson t
    , "else_branch" .= exprToJson f
    ]

exprToJson (EMatch scrut arms) =
  object
    [ "kind"      .= ("match" :: Text)
    , "scrutinee" .= exprToJson scrut
    , "arms"      .= map armToJson arms
    ]
  where
    armToJson (pat, body) =
      object ["pattern" .= patternToJson pat, "body" .= exprToJson body]

exprToJson (EApp fn args) =
  -- Distinguish qualified (contains dot) from plain apps
  if T.elem '.' fn
    then object ["kind" .= ("qual-app" :: Text), "qual_fn" .= fn, "args" .= map exprToJson args]
    else object ["kind" .= ("app"      :: Text), "fn"      .= fn, "args" .= map exprToJson args]

exprToJson (EOp op args) =
  object ["kind" .= ("op" :: Text), "op" .= op, "args" .= map exprToJson args]

exprToJson (EPair fst_ snd_) =
  object ["kind" .= ("pair" :: Text), "fst" .= exprToJson fst_, "snd" .= exprToJson snd_]

exprToJson (ELambda params body) =
  object
    [ "kind"   .= ("lambda" :: Text)
    , "params" .= map typedParamToJson params
    , "body"   .= exprToJson body
    ]

exprToJson (EAwait e) =
  object ["kind" .= ("await" :: Text), "expr" .= exprToJson e]

exprToJson (EDo steps) =
  object ["kind" .= ("do" :: Text), "steps" .= map doStepToJson steps]
  where
    doStepToJson (DoBind n e) = object ["kind" .= ("bind-step" :: Text), "name" .= n, "expr" .= exprToJson e]
    doStepToJson (DoExpr e)   = object ["kind" .= ("expr-step" :: Text), "expr" .= exprToJson e]

exprToJson (EHole hk) = holeToJson hk

-- ---------------------------------------------------------------------------
-- Hole serialiser
-- ---------------------------------------------------------------------------

holeToJson :: HoleKind -> Value
holeToJson (HNamed n)            = object ["kind" .= ("hole-named"       :: Text), "name"    .= n]
holeToJson (HChoose opts)        = object ["kind" .= ("hole-choose"      :: Text), "options" .= opts]
holeToJson (HRequestCap cap)     = object ["kind" .= ("hole-request-cap" :: Text), "cap_path" .= cap]
holeToJson (HScaffold spec)      = object
  [ "kind"     .= ("hole-scaffold" :: Text)
  , "template" .= scaffoldTemplate spec
  ]
holeToJson (HDelegate spec)      = delegateToJson "hole-delegate" spec
holeToJson (HDelegateAsync spec) = delegateToJson "hole-delegate-async" spec
holeToJson (HDelegatePending t)  = object
  [ "kind"        .= ("hole-delegate" :: Text)
  , "agent"       .= ("" :: Text)
  , "description" .= ("pending" :: Text)
  , "return_type" .= typeToJson t
  ]
holeToJson HConflictResolution   = object ["kind" .= ("hole-named" :: Text), "name" .= ("conflict" :: Text)]

delegateToJson :: Text -> DelegateSpec -> Value
delegateToJson kindStr spec =
  object $
    [ "kind"        .= kindStr
    , "agent"       .= delegateAgent spec
    , "description" .= delegateDescription spec
    , "return_type" .= typeToJson (delegateReturnType spec)
    ] ++
    maybe [] (\e -> ["on_failure" .= exprToJson e]) (delegateOnFailure spec)

-- ---------------------------------------------------------------------------
-- Pattern serialiser
-- ---------------------------------------------------------------------------

patternToJson :: Pattern -> Value
patternToJson PWildcard           = object ["kind" .= ("wildcard" :: Text)]
patternToJson (PVar n)            = object ["kind" .= ("bind" :: Text), "name" .= n]
patternToJson (PLiteral lit)      = object ["kind" .= ("literal" :: Text), "value" .= litVal lit]
  where
    litVal (LitInt  i) = toJSON i
    litVal (LitFloat d) = toJSON d
    litVal (LitString s) = toJSON s
    litVal (LitBool b)  = toJSON b
    litVal LitUnit      = toJSON (0 :: Int)
patternToJson (PConstructor c ps) =
  object ["kind" .= ("constructor" :: Text), "constructor" .= c, "sub_patterns" .= map patternToJson ps]

-- ---------------------------------------------------------------------------
-- Other helpers
-- ---------------------------------------------------------------------------

typedParamToJson :: (Name, Type) -> Value
typedParamToJson (n, TCustom "_") =
  object ["name" .= n, "untyped" .= True, "comment" .= ("pair-type or unresolved" :: Text)]
typedParamToJson (n, ty) =
  object ["name" .= n, "param_type" .= typeToJson ty]

capToJson :: Capability -> Value
capToJson cap =
  object
    [ "name"          .= capKindLabel (capKind cap)
    , "path_or_port"  .= capTarget cap
    , "deterministic" .= capDeterministic cap
    ]

capKindLabel :: CapabilityKind -> Text
capKindLabel CapRead           = "read"
capKindLabel CapWrite          = "write"
capKindLabel CapReadWrite      = "read-write"
capKindLabel CapNetConnect     = "connect"
capKindLabel CapNetServe       = "serve"
capKindLabel CapHttpPost       = "post"
capKindLabel CapHttpGet        = "get"
capKindLabel CapClockMonotonic = "monotonic-read"
capKindLabel CapRandomGet      = "get-bytes"
capKindLabel (CapCpu c)        = "cpu-" <> c
capKindLabel (CapCustom c)     = c
