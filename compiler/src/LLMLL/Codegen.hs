-- |
-- Module      : LLMLL.Codegen
-- Description : [DEPRECATED] Legacy Rust codegen shim — do not use in new code.
--
-- This module is a backwards-compatibility shim for v0.1.1 Rust codegen.
-- The canonical Haskell emitter is 'LLMLL.CodegenHs.generateHaskell'.
-- This file will be deleted in v0.2.
module LLMLL.Codegen
  ( generateRust
  , CodegenResult(..)
  , ImportKind(..)
  , classifyImport
  -- kept for any call sites that used the old Rust-specific helpers:
  , emitFfiModRs
  , emitFfiCrateFile
  , CodegenError(..)
  ) where

import Data.Text (Text)
import LLMLL.Syntax (Statement, Import)
import LLMLL.CodegenHs
  ( generateHaskell
  , CodegenResult(..)
  , ImportKind(..)
  , classifyImport
  )

-- | Deprecated alias — delegates to 'generateHaskell'.
generateRust :: Text -> [Statement] -> CodegenResult
generateRust = generateHaskell

-- | Kept for API compatibility; no longer meaningful (Haskell backend has no mod.rs).
emitFfiModRs :: [Import] -> Text
emitFfiModRs _ = "-- DEPRECATED: FFI output now in src/FFI/*.hs (Haskell backend)\n"

-- | Kept for API compatibility; no longer meaningful.
emitFfiCrateFile :: Text -> [Import] -> Text
emitFfiCrateFile _ _ = "-- DEPRECATED: FFI output now in src/FFI/*.hs (Haskell backend)\n"

data CodegenError
  = UnsupportedFeature Text
  | UnresolvedHole Text
  | CodegenInternalError Text
  deriving (Show, Eq)
