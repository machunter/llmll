-- |
-- Module      : LLMLL.Codegen
-- Description : Transpile LLMLL AST to Rust source code.
--
-- Converts the LLMLL AST into dynamic Rust code using LlmllVal.
-- This approach ensures that untyped LLMLL code (v0.1) compiles reliably.
module LLMLL.Codegen
  ( -- * Entry Points
    generateRust
  , generateCargoToml
  , classifyImport
  , ImportKind(..)
  , emitFfiModRs
  , emitFfiCrateFile
  , CodegenResult(..)
  , CodegenError(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (intercalate, nub)

import LLMLL.Syntax

-- ---------------------------------------------------------------------------
-- Result Types
-- ---------------------------------------------------------------------------

data CodegenError
  = UnsupportedFeature Text
  | UnresolvedHole Text
  | CodegenInternalError Text
  deriving (Show, Eq)

data CodegenResult = CodegenResult
  { cgRustSource  :: Text         -- ^ Generated Rust source for lib.rs
  , cgMainRs      :: Maybe Text   -- ^ Generated main.rs (if def-main present)
  , cgCargoToml   :: Text         -- ^ Generated Cargo.toml
  , cgFfiModRs    :: Maybe Text   -- ^ Generated src/ffi/mod.rs (if any FFI)
  , cgFfiCrates   :: [(Text, Text)] -- ^ List of (crate_name, src/ffi/xxx.rs)
  , cgModuleName  :: Text         -- ^ The module name used
  , cgWarnings    :: [Text]       -- ^ Non-fatal issues encountered
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Entry Points
-- ---------------------------------------------------------------------------

generateRust :: Text -> [Statement] -> CodegenResult
generateRust moduleName stmts =
  let (warnings, source) = runCodegen moduleName stmts
      mainRs = generateMain moduleName stmts
      hasMain = maybe False (const True) mainRs
      imports = [imp | SImport imp <- stmts]
      hasFfi = any (\imp -> case classifyImport imp of RustCrateImport _ -> True; _ -> False) imports
      ffiMod = if hasFfi then Just (emitFfiModRs imports) else Nothing
      ffiCrates = if hasFfi
                  then let crates = nub [c | imp <- imports, RustCrateImport c <- [classifyImport imp]]
                       in [(c, emitFfiCrateFile c imports) | c <- crates]
                  else []
  in CodegenResult
    { cgRustSource  = source
    , cgMainRs      = mainRs
    , cgCargoToml   = generateCargoToml moduleName hasMain (defMainModeOf stmts) imports
    , cgFfiModRs    = ffiMod
    , cgFfiCrates   = ffiCrates
    , cgModuleName  = moduleName
    , cgWarnings    = warnings
    }

-- | Extract the EntryMode from statements if a SDefMain exists.
defMainModeOf :: [Statement] -> Maybe EntryMode
defMainModeOf stmts = case [defMainMode s | s@SDefMain{} <- stmts] of
  (m:_) -> Just m
  []    -> Nothing

-- ---------------------------------------------------------------------------
-- Import Classification
-- ---------------------------------------------------------------------------

data ImportKind
  = WasiImport
  | RustCrateImport Text
  | CLibImport Text
  | UnknownImport
  deriving (Show, Eq)

classifyImport :: Import -> ImportKind
classifyImport imp
  | "rust." `T.isPrefixOf` path = RustCrateImport (T.drop 5 path)
  | "wasi." `T.isPrefixOf` path = WasiImport
  | "c."    `T.isPrefixOf` path = CLibImport (T.drop 2 path)
  | otherwise                   = UnknownImport
  where path = importPath imp

-- ---------------------------------------------------------------------------
-- Cargo.toml Generation
-- ---------------------------------------------------------------------------
generateCargoToml :: Text -> Bool -> Maybe EntryMode -> [Import] -> Text
generateCargoToml moduleName hasMain mMode imports = T.unlines $
  [ "[package]"
  , "name = \"" <> T.replace "_" "-" moduleName <> "\""
  , "version = \"0.1.0\""
  , "edition = \"2021\""
  , ""
  , "[dependencies]"
  ] ++
  rustDeps ++
  httpDeps ++
  [ ""
  , "[dev-dependencies]"
  , "proptest = \"1\""
  , ""
  , "[lib]"
  , "name = \"" <> moduleName <> "\""
  , "path = \"src/lib.rs\""
  ] ++
  binSection
  where
    rustDeps =
      let crates = [ crate | imp <- imports
                           , RustCrateImport crate <- [classifyImport imp] ]
          unique = nub crates
      in if null unique
           then []
           else
             [ "# FFI dependencies — pin exact versions before building:"
             ] ++ map (\c -> "# " <> c <> " = \"<version>\"  # TODO: replace <version> and uncomment") unique

    httpDeps = case mMode of
      Just (ModeHttp _) ->
        [ "hyper = { version = \"0.14\", features = [\"full\"] }"
        , "tokio = { version = \"1\", features = [\"full\"] }"
        ]
      _ -> []
    binSection
      | hasMain =
        [ ""
        , "[[bin]]"
        , "name = \"" <> moduleName <> "\""
        , "path = \"src/main.rs\""
        ]
      | otherwise = []

-- ---------------------------------------------------------------------------
-- main.rs Harness Generator
-- ---------------------------------------------------------------------------

-- | Generate main.rs if any SDefMain is present in the statements.
generateMain :: Text -> [Statement] -> Maybe Text
generateMain modName stmts =
  case [s | s@SDefMain{} <- stmts] of
    []     -> Nothing
    (dm:_) -> Just (emitMainRs modName dm)

-- | Render a full main.rs for the given SDefMain.
emitMainRs :: Text -> Statement -> Text
emitMainRs modName dm@SDefMain{defMainMode = ModeConsole} = T.unlines
  [ "use std::io::{self, BufRead, Write};"
  , "use " <> modName <> "::*;"
  , ""
  , "fn main() {"
  , initBlock
  , "    let stdin = io::stdin();"
  , "    for line in stdin.lock().lines() {"
  , "        let raw_line = line.unwrap();"
  , "        if raw_line.trim().is_empty() { continue; }"
  , "        let raw_val = LlmllVal::from(raw_line.trim().to_string());"
  , readBlock
  , stepBlock
  , "        print!(\"{}\", second(result.clone()).as_str());"
  , "        io::stdout().flush().unwrap();"
  , doneBlock
  , "    }"
  , onDoneBlock
  , "}"
  ]
  where
    initBlock = case defMainInit dm of
      Nothing -> "    let mut state = LlmllVal::Unit;"
      Just e  ->
        let initExpr = emitExprInline e
        in  "    let init_result = (" <> initExpr <> ");\n" <>
            "    let mut state = first(init_result.clone());\n" <>
            "    print!(\"{}\", second(init_result).as_str());\n" <>
            "    io::stdout().flush().unwrap();"
    readBlock = case defMainRead dm of
      Nothing -> "        let input = raw_val;"
      Just e  -> "        let input = (" <> emitStepCall e "raw_val" <> ");"
    stepBlock =
      "        let result = " <> emitStepCall (defMainStep dm) "state.clone(), input" <> ";\n" <>
      "        state = first(result.clone());"
    doneBlock = case defMainDone dm of
      Nothing -> ""
      Just e  ->
        "        if (" <> emitStepCall e "state.clone()" <> ").as_bool() { break; }"
    onDoneBlock = case defMainOnDone dm of
      Nothing -> ""
      Just e  -> "    print!(\"{}\", (" <> emitStepCall e "state.clone()" <> ").as_str());"

emitMainRs modName dm@SDefMain{defMainMode = ModeCli} = T.unlines
  [ "use " <> modName <> "::*;"
  , ""
  , "fn main() {"
  , "    let args: Vec<LlmllVal> = std::env::args().skip(1)"
  , "        .map(|s| LlmllVal::from(s))"
  , "        .collect();"
  , "    let cmd = " <> emitStepCall (defMainStep dm) "LlmllVal::List(args)" <> ";"
  , "    println!(\"{}\", cmd.as_str());"
  , "}"
  ]

emitMainRs modName dm@SDefMain{defMainMode = ModeHttp{httpPort = port}} = T.unlines
  [ "use std::sync::{Arc, Mutex};"
  , "use std::convert::Infallible;"
  , "use hyper::{Body, Request, Response, Server};"
  , "use hyper::service::{make_service_fn, service_fn};"
  , "use " <> modName <> "::*;"
  , ""
  , "async fn llmll_handle("
  , "    state: Arc<Mutex<LlmllVal>>,"
  , "    req: Request<Body>,"
  , ") -> Result<Response<Body>, Infallible> {"
  , "    let body_bytes = hyper::body::to_bytes(req.into_body()).await.unwrap_or_default();"
  , "    let raw_body   = LlmllVal::from(String::from_utf8_lossy(&body_bytes).to_string());"
  , "    let result = {"
  , "        let st = state.lock().unwrap().clone();"
  , "        " <> emitStepCall (defMainStep dm) "st, raw_body"
  , "    };"
  , "    {"
  , "        let mut guard = state.lock().unwrap();"
  , "        *guard = first(result.clone());"
  , "    }"
  , "    let resp_text = second(result).into_string();"
  , "    Ok(Response::new(Body::from(resp_text)))"
  , "}"
  , ""
  , "#[tokio::main]"
  , "async fn main() {"
  , initStr
  , "    let state = Arc::new(Mutex::new(init_state));"
  , "    let addr  = ([0, 0, 0, 0], " <> T.pack (show port) <> ").into();"
  , "    let make_svc = make_service_fn(move |_| {"
  , "        let state = Arc::clone(&state);"
  , "        async move {"
  , "            Ok::<_, Infallible>(service_fn(move |req| {"
  , "                let state = Arc::clone(&state);"
  , "                async move { llmll_handle(state, req).await }"
  , "            }))"
  , "        }"
  , "    });"
  , "    println!(\"LLMLL HTTP server listening on :{}\", " <> T.pack (show port) <> ");"
  , "    Server::bind(&addr).serve(make_svc).await.unwrap();"
  , "}"
  ]
  where
    initStr = case defMainInit dm of
      Nothing -> "    let init_state = LlmllVal::Unit;"
      Just e  -> "    let init_state = " <> emitExprInline e <> ";"

emitMainRs _ _ = "// (def-main): unsupported mode\n"

-- | Emit a Rust call to either a named function or an inline lambda.
-- Named: foo(args)
-- Lambda: { let f = |params| body; f(args) }
emitStepCall :: Expr -> Text -> Text
emitStepCall (EVar name) args = toRustIdent name <> "(" <> args <> ")"
emitStepCall lambdaExpr  args =
  "{ let __step = " <> emitExprInline lambdaExpr <> "; __step(" <> args <> ") }"

-- ---------------------------------------------------------------------------
-- Main Code Generator
-- ---------------------------------------------------------------------------

runCodegen :: Text -> [Statement] -> ([Text], Text)
runCodegen moduleName stmts =
  let warnings  = concatMap (stmtWarnings moduleName) stmts
      imports   = [imp | SImport imp <- stmts]
      hasFfi    = any (\imp -> case classifyImport imp of RustCrateImport _ -> True; _ -> False) imports
      ffiModDecl = if hasFfi then "pub mod ffi;\n" else ""
      
      -- Import all generated ffi::crate_name::* into lib.rs
      ffiUseLines = if hasFfi
        then let crates = nub [toRustIdent c | imp <- imports, RustCrateImport c <- [classifyImport imp]]
             in T.unlines $ map (\c -> "use crate::ffi::" <> c <> "::*;") crates
        else ""

      header    = T.unlines
        [ "// Generated by LLMLL compiler v0.1.1 (DYNAMIC_RUNTIME)"
        , "// DO NOT EDIT — regenerate with `llmll build`"
        , "#![allow(unused_variables, dead_code, unused_mut, unused_imports, clippy::all)]"
        , ""
        , ffiModDecl
        , ffiUseLines
        , "use std::collections::HashMap;"
        , ""
        , "// ---------------------------------------------------------------------------"
        , "// LlmllVal: dynamic value type for LLMLL v0.1"
        , "// ---------------------------------------------------------------------------"
        , "#[derive(Debug, Clone, PartialEq)]"
        , "pub enum LlmllVal {"
        , "    Int(i64),"
        , "    Float(f64),"
        , "    Text(String),"
        , "    Bool(bool),"
        , "    Unit,"
        , "    List(Vec<LlmllVal>),"
        , "    Pair(Box<LlmllVal>, Box<LlmllVal>),"
        , "    Adt(String, Vec<LlmllVal>),"
        , "}"
        , ""
        , "impl LlmllVal {"
        , "    pub fn as_int(&self) -> i64 { if let Self::Int(n) = self { *n } else { panic!(\"expected Int\") } }"
        , "    pub fn as_str(&self) -> &str { if let Self::Text(s) = self { s } else { panic!(\"expected Text\") } }"
        , "    pub fn as_bool(&self) -> bool { if let Self::Bool(b) = self { *b } else { panic!(\"expected Bool\") } }"
        , "    pub fn into_string(self) -> String { if let Self::Text(s) = self { s } else { panic!(\"expected Text\") } }"
        , "}"
        , ""
        , "impl std::fmt::Display for LlmllVal {"
        , "    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {"
        , "        match self {"
        , "            Self::Int(n) => write!(f, \"{}\", n),"
        , "            Self::Float(n) => write!(f, \"{}\", n),"
        , "            Self::Text(s) => write!(f, \"{}\", s),"
        , "            Self::Bool(b) => write!(f, \"{}\", b),"
        , "            Self::Unit => write!(f, \"()\"),"
        , "            Self::List(l) => write!(f, \"{:?}\", l),"
        , "            Self::Pair(a, b) => write!(f, \"({}, {})\", a, b),"
        , "            Self::Adt(c, args) => write!(f, \"{}({:?})\", c, args),"
        , "        }"
        , "    }"
        , "}"
        , ""
        , "impl From<i64> for LlmllVal { fn from(n: i64) -> Self { Self::Int(n) } }"
        , "impl From<String> for LlmllVal { fn from(s: String) -> Self { Self::Text(s) } }"
        , "impl From<&str> for LlmllVal { fn from(s: &str) -> Self { Self::Text(s.to_string()) } }"
        , "impl From<bool> for LlmllVal { fn from(b: bool) -> Self { Self::Bool(b) } }"
        , "impl<A: Into<LlmllVal>, B: Into<LlmllVal>> From<(A, B)> for LlmllVal {"
        , "    fn from(p: (A, B)) -> Self { Self::Pair(Box::new(p.0.into()), Box::new(p.1.into())) }"
        , "}"
        , ""
        , "impl std::ops::Add for LlmllVal {"
        , "    type Output = Self;"
        , "    fn add(self, rhs: Self) -> Self {"
        , "        match (self, rhs) {"
        , "            (Self::Int(a), Self::Int(b)) => Self::Int(a + b),"
        , "            (Self::Text(a), Self::Text(b)) => Self::Text(a + &b),"
        , "            _ => panic!(\"add: type mismatch\")"
        , "        }"
        , "    }"
        , "}"
        , ""
        , "impl std::ops::Not for LlmllVal {"
        , "    type Output = Self;"
        , "    fn not(self) -> Self { Self::Bool(!self.as_bool()) }"
        , "}"
        , ""
        , "impl PartialOrd for LlmllVal {"
        , "    fn partial_cmp(&self, rhs: &Self) -> Option<std::cmp::Ordering> {"
        , "        match (self, rhs) {"
        , "            (Self::Int(a), Self::Int(b)) => a.partial_cmp(b),"
        , "            (Self::Text(a), Self::Text(b)) => a.partial_cmp(b),"
        , "            _ => None,"
        , "        }"
        , "    }"
        , "}"
        , ""
        , "// ---------------------------------------------------------------------------"
        , "// LLMLL built-in standard library"
        , "// ---------------------------------------------------------------------------"
        , "pub type Command = LlmllVal;"
        , "pub type Word = LlmllVal;"
        , "pub type Letter = LlmllVal;"
        , "pub type GuessCount = LlmllVal;"
        , "pub type PositiveInt = LlmllVal;"
        , ""
        , "pub fn string_length(s: LlmllVal) -> LlmllVal { LlmllVal::Int(s.as_str().chars().count() as i64) }"
        , "pub fn string_char_at(s: LlmllVal, i: LlmllVal) -> LlmllVal {"
        , "    LlmllVal::Text(s.as_str().chars().nth(i.as_int() as usize).map(|c| c.to_string()).unwrap_or_default())"
        , "}"
        , "pub fn string_contains(haystack: LlmllVal, needle: LlmllVal) -> LlmllVal {"
        , "    LlmllVal::Bool(haystack.as_str().contains(needle.as_str()))"
        , "}"
        , "pub fn string_concat(a: LlmllVal, b: LlmllVal) -> LlmllVal { LlmllVal::Text(a.as_str().to_owned() + b.as_str()) }"
        , "pub fn int_to_string(n: LlmllVal) -> LlmllVal { LlmllVal::Text(n.as_int().to_string()) }"
        , "pub fn random_int() -> LlmllVal { LlmllVal::Int(42) }"
        , "pub fn range(from: LlmllVal, to: LlmllVal) -> LlmllVal {"
        , "    LlmllVal::List((from.as_int()..to.as_int()).map(LlmllVal::Int).collect())"
        , "}"
        , "pub fn list_empty() -> LlmllVal { LlmllVal::List(vec![]) }"
        , "pub fn list_append(v: LlmllVal, x: LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::List(mut l) = v { l.push(x); LlmllVal::List(l) } else { panic!(\"list_append: not a list\") }"
        , "}"
        , "pub fn list_map(v: LlmllVal, f: impl Fn(LlmllVal) -> LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::List(l) = v { LlmllVal::List(l.into_iter().map(f).collect()) } else { panic!(\"list_map: not a list\") }"
        , "}"
        , "pub fn list_fold(v: LlmllVal, init: LlmllVal, f: impl Fn(LlmllVal, LlmllVal) -> LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::List(l) = v { l.into_iter().fold(init, |acc, x| f(acc, x)) } else { panic!(\"list_fold: not a list\") }"
        , "}"
        , "pub fn list_contains(v: LlmllVal, x: LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::List(l) = v { LlmllVal::Bool(l.contains(&x)) } else { panic!(\"list_contains: not a list\") }"
        , "}"
        , "pub fn list_length(v: LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::List(l) = v { LlmllVal::Int(l.len() as i64) } else { panic!(\"list_length: not a list\") }"
        , "}"
        , "pub fn first(p: LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::Pair(a, _) = p { *a } else { panic!(\"first: not a pair\") }"
        , "}"
        , "pub fn second(p: LlmllVal) -> LlmllVal {"
        , "    if let LlmllVal::Pair(_, b) = p { *b } else { panic!(\"second: not a pair\") }"
        , "}"
        , "pub fn pair(a: LlmllVal, b: LlmllVal) -> LlmllVal { LlmllVal::Pair(Box::new(a), Box::new(b)) }"
        , "pub fn wasi_io_stdout(s: LlmllVal) -> Command { s }"
        , "pub fn wasi_io_stdout_str(s: &str) -> Command { LlmllVal::Text(s.to_string()) }"
        , "pub fn mod_(a: LlmllVal, b: LlmllVal) -> LlmllVal { LlmllVal::Int(a.as_int() % b.as_int()) }"
        , ""
        , "// ---------------------------------------------------------------------------"
        , "// §13 standard library — string / Result helpers"
        , "// ---------------------------------------------------------------------------"
        , "pub fn string_slice(s: LlmllVal, start: LlmllVal, end: LlmllVal) -> LlmllVal {"
        , "    let st = start.as_int() as usize;"
        , "    let en = end.as_int() as usize;"
        , "    LlmllVal::Text(s.as_str().chars().skip(st).take(en.saturating_sub(st)).collect())"
        , "}"
        , "pub fn string_to_int(s: LlmllVal) -> LlmllVal {"
        , "    match s.as_str().trim().parse::<i64>() {"
        , "        Ok(n)  => LlmllVal::Adt(\"Success\".to_string(), vec![LlmllVal::Int(n)]),"
        , "        Err(e) => LlmllVal::Adt(\"Error\".to_string(),   vec![LlmllVal::Text(e.to_string())]),"
        , "    }"
        , "}"
        , "pub fn ok(v: LlmllVal) -> LlmllVal { LlmllVal::Adt(\"Success\".to_string(), vec![v]) }"
        , "pub fn err(e: LlmllVal) -> LlmllVal { LlmllVal::Adt(\"Error\".to_string(),   vec![e]) }"
        , "pub fn is_ok(r: LlmllVal) -> LlmllVal {"
        , "    match &r { LlmllVal::Adt(c, _) => LlmllVal::Bool(c == \"Success\"), _ => LlmllVal::Bool(false) }"
        , "}"
        , "pub fn unwrap(r: LlmllVal) -> LlmllVal {"
        , "    match r { LlmllVal::Adt(ref c, ref v) if c == \"Success\" => v[0].clone(),"
        , "              _ => panic!(\"unwrap called on Error\") }"
        , "}"
        , "pub fn unwrap_or(r: LlmllVal, default: LlmllVal) -> LlmllVal {"
        , "    match r { LlmllVal::Adt(ref c, ref v) if c == \"Success\" => v[0].clone(),"
        , "              _ => default }"
        , "}"
        , "pub fn seq_commands(a: LlmllVal, b: LlmllVal) -> LlmllVal {"
        , "    if let (LlmllVal::Text(t1), LlmllVal::Text(t2)) = (&a, &b) {"
        , "        LlmllVal::Text(format!(\"{}{}\", t1, t2))"
        , "    } else {"
        , "        panic!(\"seq-commands: expected Text commands\")"
        , "    }"
        , "}"
        , ""
        , "// Generic FFI helpers — used by src/ffi/**/*.rs"
        , "pub fn llmll_to_str(v: &LlmllVal) -> String { v.as_str().to_string() }"
        , "pub fn llmll_to_i64(v: &LlmllVal) -> i64    { v.as_int() }"
        , "pub fn llmll_to_bool(v: &LlmllVal) -> bool  { v.as_bool() }"
        , "pub fn str_to_llmll(s: String)    -> LlmllVal { LlmllVal::Text(s) }"
        , "pub fn i64_to_llmll(i: i64)       -> LlmllVal { LlmllVal::Int(i) }"
        , "pub fn bool_to_llmll(b: bool)     -> LlmllVal { LlmllVal::Bool(b) }"
        , ""
        , "// ---------------------------------------------------------------------------"
        , "// Arithmetic operator traits — Sub, Mul, Div (mirror Add above)"
        , "// ---------------------------------------------------------------------------"
        , "impl std::ops::Sub for LlmllVal {"
        , "    type Output = Self;"
        , "    fn sub(self, rhs: Self) -> Self {"
        , "        match (self, rhs) {"
        , "            (Self::Int(a),   Self::Int(b))   => Self::Int(a - b),"
        , "            (Self::Float(a), Self::Float(b)) => Self::Float(a - b),"
        , "            _ => panic!(\"sub: type mismatch\")"
        , "        }"
        , "    }"
        , "}"
        , "impl std::ops::Mul for LlmllVal {"
        , "    type Output = Self;"
        , "    fn mul(self, rhs: Self) -> Self {"
        , "        match (self, rhs) {"
        , "            (Self::Int(a),   Self::Int(b))   => Self::Int(a * b),"
        , "            (Self::Float(a), Self::Float(b)) => Self::Float(a * b),"
        , "            _ => panic!(\"mul: type mismatch\")"
        , "        }"
        , "    }"
        , "}"
        , "impl std::ops::Div for LlmllVal {"
        , "    type Output = Self;"
        , "    fn div(self, rhs: Self) -> Self {"
        , "        match (self, rhs) {"
        , "            (Self::Int(a),   Self::Int(b))   => Self::Int(a / b),"
        , "            (Self::Float(a), Self::Float(b)) => Self::Float(a / b),"
        , "            _ => panic!(\"div: type mismatch\")"
        , "        }"
        , "    }"
        , "}"
        , ""
        ]
      typeDefs  = T.unlines (map emitStatement (filter isTypeDef stmts))
      ifaces    = T.unlines (map emitStatement (filter isInterface stmts))
      fns       = T.unlines (map emitStatement (filter isFn stmts))
      tests     = emitTestModule moduleName (filter isCheck stmts)
      source    = header <> typeDefs <> ifaces <> fns <> tests
  in (warnings, source)

preDefinedTypeNames :: [Text]
preDefinedTypeNames = ["Word", "Letter", "GuessCount", "PositiveInt"]

isTypeDef, isInterface, isFn, isCheck :: Statement -> Bool
isTypeDef  (STypeDef { typeDefName = name }) = name `notElem` preDefinedTypeNames
isTypeDef  _                                  = False
isInterface (SDefInterface{}) = True
isInterface _             = False
isFn       (SDefLogic{})  = True
isFn       _              = False
isCheck    (SCheck{})     = True
isCheck    _              = False

emitStatement :: Statement -> Text
emitStatement (STypeDef name body) = emitTypeDef name body
emitStatement (SDefInterface name fns) = emitInterface name fns
emitStatement (SDefLogic name params mRet contract body) = emitFunction name params mRet contract body
emitStatement _ = ""

emitTypeDef :: Name -> Type -> Text
emitTypeDef name _ = "pub type " <> toRustIdent name <> " = LlmllVal;\n\n"

emitInterface :: Name -> [(Name, Type)] -> Text
emitInterface name fns = T.unlines $
  [ "pub trait " <> toRustIdent name <> " {" ]
  ++ map emitTraitMethod fns
  ++ [ "}" , "" ]

emitTraitMethod :: (Name, Type) -> Text
emitTraitMethod (fname, _) = "    fn " <> toRustIdent fname <> "(&self, args: Vec<LlmllVal>) -> LlmllVal;"

emitFunction :: Name -> [(Name, Type)] -> Maybe Type -> Contract -> Expr -> Text
emitFunction name params _ contract body = T.unlines
  [ "pub fn " <> toRustIdent name <> "(" <> emitParams params <> ") -> LlmllVal {"
  , preCheck
  , "    let result = LlmllVal::from((" <> emitExprInline body <> ").clone());"
  , "    result"
  , "}"
  ]
  where
    preCheck = case contractPre contract of
      Nothing   -> ""
      Just expr -> "    assert!((" <> emitExprInline expr <> ").clone().as_bool(), \"Pre-contract failed\");"

emitParams :: [(Name, Type)] -> Text
emitParams = T.intercalate ", " . map (\(n, _) -> toRustIdent n <> ": LlmllVal")

-- ---------------------------------------------------------------------------
-- FFI Stub Generation (v0.2)
-- ---------------------------------------------------------------------------

-- | Emits the content for src/ffi/mod.rs
emitFfiModRs :: [Import] -> Text
emitFfiModRs imports =
  let crates = nub [toRustIdent c | imp <- imports, RustCrateImport c <- [classifyImport imp]]
      mods   = map (\c -> "pub mod " <> c <> ";") crates
  in T.unlines $
    [ "// Auto-generated by llmll build. DO NOT EDIT."
    , "// This file tracks active imports and is regenerated every build." ] ++ mods

-- | Emits the content for a specific src/ffi/<crate>.rs
emitFfiCrateFile :: Text -> [Import] -> Text
emitFfiCrateFile crate imports =
  let stubs = concatMap (\imp ->
                if classifyImport imp == RustCrateImport crate
                then maybe [] (map (emitFfiWrapper crate)) (importInterface imp)
                else []
              ) imports
  in T.unlines $
    [ "// FFI Stubs for '" <> crate <> "'. Generated ONCE."
    , "// Edit this file to implement the stubs using the crate API."
    , "// Add the crate as a [dependency] in Cargo.toml before implementing."
    , "#![allow(unused_variables, dead_code)]"
    , "use crate::LlmllVal;"
    , "// use " <> toRustIdent crate <> "; // Uncomment & add to Cargo.toml: " <> toRustIdent crate <> " = \"<version>\""
    , ""
    ] ++ stubs

emitFfiWrapper :: Text -> (Name, Type) -> Text
emitFfiWrapper crate (fname, ftype) =
  let rustFn = toRustIdent fname
      params = emitFfiParams ftype
  in T.unlines
    [ "pub fn " <> rustFn <> "(" <> params <> ") -> LlmllVal {"
    , "    // TODO: implement using " <> crate
    , "    todo!(\"FFI stub: " <> rustFn <> "\")"
    , "}"
    ]

-- | Extract parameter names and type format from the function type inside an interface.
-- LLMLL types like (fn [a: string b: int] -> any) need generic LlmllVal mapping in the stub signature.
emitFfiParams :: Type -> Text
emitFfiParams (TFn argTypes _) =
  T.intercalate ", " $ zipWith (\i _ -> "arg" <> T.pack (show i) <> ": LlmllVal") [0::Int ..] argTypes
emitFfiParams _ = ""

emitTestModule :: Text -> [Statement] -> Text
emitTestModule _ [] = ""
emitTestModule _ checks = T.unlines $ [ "#[cfg(test)]", "mod tests {", "    use super::*;", "}" ]

emitType :: Type -> Text
emitType _ = "LlmllVal"

emitExprInline :: Expr -> Text
emitExprInline (ELit lit)         = emitLit lit
emitExprInline (EVar name)        = toRustIdent name
emitExprInline (EOp op args)      = emitOp op (map (\e -> "(" <> emitExprInline e <> ").clone()") args)
emitExprInline (EApp func args)   = toRustIdent func <> "(" <> T.intercalate ", " (map (\e -> "(" <> emitExprInline e <> ").clone()") args) <> ")"
emitExprInline (EIf cond t f)     = "if (" <> emitExprInline cond <> ").clone().as_bool() { " <> emitExprInline t <> " } else { " <> emitExprInline f <> " }"
emitExprInline (ELet bs body)     = "{ " <> T.intercalate " " (map (\(n, _, e) -> "let " <> toRustIdent n <> " = " <> emitExprInline e <> ";") bs) <> emitExprInline body <> " }"
emitExprInline (EPair a b)        = "LlmllVal::from(((" <> emitExprInline a <> ").clone(), (" <> emitExprInline b <> ").clone()))"
emitExprInline (EMatch scrut cases) = "match (" <> emitExprInline scrut <> ").clone() { " <> T.intercalate " " (map emitCase cases ++ [matchCatchAll]) <> " }"
  where
    emitCase (PConstructor name ps, e) =
      let pattern = "LlmllVal::Adt(ref ctor, ref args) if ctor == \"" <> name <> "\" && args.len() == " <> T.pack (show (length ps))
          bindings = T.concat [ "let " <> toRustIdent v <> " = args[" <> T.pack (show i) <> "].clone(); " | (i, PVar v) <- zip [(0::Int)..] ps ]
      in pattern <> " => { " <> bindings <> emitExprInline e <> " },"
    emitCase (pat, e) = emitPat pat <> " => " <> emitExprInline e <> ","
    matchCatchAll = "_ => panic!(\"non-exhaustive match in LLMLL\")"
emitExprInline (EHole _)          = "todo!()"
emitExprInline (EAwait e)         = emitExprInline e
emitExprInline (ELambda params body) = "| " <> T.intercalate ", " (map (\(n, _) -> toRustIdent n <> ": LlmllVal") params) <> " | " <> emitExprInline body
emitExprInline (EDo steps)        = "{ " <> T.intercalate "; " (map emitStep steps) <> " }"
  where
    emitStep (DoBind n e) = "let " <> toRustIdent n <> " = " <> emitExprInline e
    emitStep (DoExpr e)   = emitExprInline e

emitPat :: Pattern -> Text
emitPat PWildcard              = "_"
emitPat (PVar n)               = toRustIdent n
emitPat (PLiteral l)           = emitLit l
emitPat (PConstructor name ps) = "LlmllVal::Adt(ref ctor, ref args) if ctor == \"" <> name <> "\" && args.len() == " <> T.pack (show (length ps))
  -- Note: Binding variables inside Adt is hard in v0.1 without macro/helper.
  -- For Hangman, we'll use manual extraction if possible, or skip binding.
  -- Actually, the Hangman code uses patterns like (Match state (Adt StartGame [word])).
  -- This is too complex for this simplified generator.

emitLit :: Literal -> Text
emitLit (LitInt n)    = "LlmllVal::from(" <> T.pack (show n) <> "i64)"
emitLit (LitFloat f)  = "LlmllVal::from(" <> T.pack (show f) <> "f64)"
emitLit (LitString s) = "LlmllVal::from(\"" <> T.replace "\"" "\\\"" s <> "\".to_string())"
emitLit (LitBool b)   = "LlmllVal::from(" <> (if b then "true" else "false") <> ")"
emitLit LitUnit       = "LlmllVal::Unit"

emitOp :: Name -> [Text] -> Text
emitOp "="  [a, b] = "LlmllVal::Bool(" <> a <> " == " <> b <> ")"
emitOp "!=" [a, b] = "LlmllVal::Bool(" <> a <> " != " <> b <> ")"
emitOp "+"  [a, b] = "(" <> a <> " + " <> b <> ")"
emitOp "-"  [a, b] = "(" <> a <> " - " <> b <> ")"
emitOp "*"  [a, b] = "(" <> a <> " * " <> b <> ")"
emitOp "/"  [a, b] = "(" <> a <> " / " <> b <> ")"
emitOp "<"  [a, b] = "LlmllVal::Bool(" <> a <> " < " <> b <> ")"
emitOp ">"  [a, b] = "LlmllVal::Bool(" <> a <> " > " <> b <> ")"
emitOp "<=" [a, b] = "LlmllVal::Bool(" <> a <> " <= " <> b <> ")"
emitOp ">=" [a, b] = "LlmllVal::Bool(" <> a <> " >= " <> b <> ")"
emitOp "and" [a, b] = "LlmllVal::Bool(" <> a <> ".as_bool() && " <> b <> ".as_bool())"
emitOp "or"  [a, b] = "LlmllVal::Bool(" <> a <> ".as_bool() || " <> b <> ".as_bool())"
emitOp "not" [a]    = "LlmllVal::Bool(!" <> a <> ".as_bool())"
emitOp name args    = toRustIdent name <> "(" <> T.intercalate ", " args <> ")"

toRustIdent :: Name -> Text
toRustIdent = T.map sanitize
  where
    sanitize '-' = '_'
    sanitize '?' = '_'
    sanitize '.' = '_'
    sanitize  c  = c

stmtWarnings :: Text -> Statement -> [Text]
stmtWarnings _ _ = []

exprWarnings :: Expr -> [Text]
exprWarnings _ = []
