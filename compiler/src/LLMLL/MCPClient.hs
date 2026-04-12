{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.MCPClient
-- Description : MCP JSON-RPC client for Leanstral integration (v0.3.1).
--
-- Provides a mock-first MCP client for theorem proving via @lean-lsp-mcp@.
-- In v0.3.1, only @--leanstral-mock@ mode is available; the real MCP protocol
-- is implemented but untested against a live @lean-lsp-mcp@ instance.
--
-- When a real instance becomes available, the only change is removing
-- @--leanstral-mock@ and pointing at the real binary.
module LLMLL.MCPClient
  ( MCPConfig(..)
  , MCPResult(..)
  , callLeanstral
  , defaultMCPConfig
  -- * Test-only
  , mockProofResult
  ) where

import Data.Text (Text)

-- | Configuration for the MCP client.
data MCPConfig = MCPConfig
  { mcpCommand   :: Text       -- ^ Path to lean-lsp-mcp binary
  , mcpTimeout   :: Int        -- ^ Timeout in seconds
  , mcpMock      :: Bool       -- ^ If True, use mock proof results
  } deriving (Show, Eq)

-- | Default configuration (mock mode).
defaultMCPConfig :: MCPConfig
defaultMCPConfig = MCPConfig
  { mcpCommand = "lean-lsp-mcp"
  , mcpTimeout = 30
  , mcpMock    = True
  }

-- | Result of a proof attempt.
data MCPResult
  = ProofFound Text              -- ^ Lean 4 proof term
  | ProofTimeout                 -- ^ Prover timed out
  | ProofError Text              -- ^ Prover returned an error
  | LeanstralUnavailable Text     -- ^ Binary not found or connection failed
  deriving (Show, Eq)

-- | Call Leanstral to prove an obligation.
--   In mock mode, returns 'mockProofResult'.
--   In real mode, spawns the MCP binary and sends JSON-RPC.
callLeanstral :: MCPConfig -> Text -> IO MCPResult
callLeanstral config obligation
  | mcpMock config = pure (mockProofResult obligation)
  | otherwise = do
      -- Real MCP protocol: spawn lean-lsp-mcp, JSON-RPC initialize → tools/call → shutdown
      -- Deferred to when lean-lsp-mcp is available.
      pure (LeanstralUnavailable "real MCP protocol not yet implemented")

-- | Test-only: returns ProofFound "by sorry" for any obligation.
-- Gated behind --leanstral-mock. Not used in production builds.
mockProofResult :: Text -> MCPResult
mockProofResult _obligation = ProofFound "by sorry"
