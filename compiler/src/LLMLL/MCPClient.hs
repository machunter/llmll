{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.MCPClient
-- Description : MCP JSON-RPC client for Leanstral integration (v0.3.1).
--
-- Provides a mock-first MCP client for theorem proving via @lean-lsp-mcp@.
-- In v0.3.1, only @--leanstral-mock@ mode is functional; the real MCP
-- protocol is STUBBED (not yet implemented) — the non-mock path returns
-- 'LeanstralUnavailable' rather than contacting a live @lean-lsp-mcp@ instance.
--
-- When the real protocol is implemented, every 'ProofFound' it constructs
-- MUST be routed through 'sanitizeProof' so that a @sorry@/@admit@/empty proof
-- term can never launder to a @verified@/@leanstral@ tier downstream
-- (PROOF-ARTIFACT §4.1 LCF anti-laundering invariant).
module LLMLL.MCPClient
  ( MCPConfig(..)
  , MCPResult(..)
  , callLeanstral
  , defaultMCPConfig
  , sanitizeProof
  -- * Test-only
  , mockProofResult
  ) where

import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T

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

-- | Anti-laundering guard (PROOF-ARTIFACT §4.1 LCF invariant).
--
-- Every 'ProofFound' must be constructed via this helper. It maps a degenerate
-- proof term — empty\/whitespace-only, or one using the @sorry@ or @admit@
-- tactic (word-boundary aware, so identifiers like @admittance@ or
-- @sorry_free@ still pass) — to a 'ProofError' instead of accepting it. This
-- ensures a @sorry@\/@admit@\/empty "proof" can never upgrade evidence to a
-- @verified@\/@leanstral@ tier downstream.
sanitizeProof :: Text -> MCPResult
sanitizeProof p
  | T.null (T.strip p)                = rejected
  | any isBanned (identifierTokens p) = rejected
  | otherwise                         = ProofFound p
  where
    isBanned t = t == "sorry" || t == "admit"
    rejected   = ProofError "degenerate proof term (sorry/admit/empty) rejected"

-- | Split a proof term into maximal runs of identifier characters, so that
-- @sorry@\/@admit@ are matched as whole tokens rather than as substrings.
identifierTokens :: Text -> [Text]
identifierTokens = filter (not . T.null) . T.split (not . isIdentChar)
  where
    isIdentChar c = isAlphaNum c || c == '_' || c == '\''

-- | Call Leanstral to prove an obligation.
--   In mock mode, returns 'mockProofResult' (routed through 'sanitizeProof').
--   The real MCP path is STUBBED: it returns 'LeanstralUnavailable' rather than
--   spawning the binary or sending JSON-RPC (not yet implemented).
callLeanstral :: MCPConfig -> Text -> IO MCPResult
callLeanstral config obligation
  | mcpMock config = pure (mockProofResult obligation)
  | otherwise = do
      -- Real MCP protocol: spawn lean-lsp-mcp, JSON-RPC initialize → tools/call → shutdown.
      -- STUBBED: not yet implemented. When implemented, route every ProofFound
      -- through 'sanitizeProof' (PROOF-ARTIFACT §4.1 anti-laundering invariant).
      pure (LeanstralUnavailable "real MCP protocol not yet implemented")

-- | Test-only: mock prover. Emits the degenerate proof term @"by sorry"@,
-- which 'sanitizeProof' rejects — so the mock resolves to 'ProofError', never
-- 'ProofFound'. A mock can therefore never launder a proof hole to @verified@.
-- Gated behind --leanstral-mock. Not used in production builds.
mockProofResult :: Text -> MCPResult
mockProofResult _obligation = sanitizeProof "by sorry"
