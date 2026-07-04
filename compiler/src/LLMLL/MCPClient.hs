{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.MCPClient
-- Description : Leanstral proof client — direct chat-completions + Lean kernel check.
--
-- Layer-3 of the Leanstral demo (`docs/design/leanstral-demo-spec.md §3`).
--
-- Trust architecture (T-B, `leanstral-integration-scope.md §4`): the Leanstral
-- __model__ /produces/ a candidate proof (untrusted proof search) and the Lean
-- __kernel__ (+ Mathlib) /checks/ it (the trusted gate). This maps LLMLL's core
-- thesis onto proofs: the model hallucinates a proof; the kernel checks it. The
-- durable, independently re-checkable artifact is the checked @.lean@ file, not
-- the (non-deterministic, black-box) model call.
--
-- Three surfaces:
--
--   * @mock@ (`--leanstral-mock`): 'mockProofResult' emits @by sorry@, which
--     'sanitizeProof' rejects — so a mock can never launder a proof to
--     @verified@ (PROOF-ARTIFACT §4.1 LCF anti-laundering invariant).
--   * @direct@ (`--leanstral`): 'proveWithLeanstral' does a real
--     @POST https://api.mistral.ai/v1/chat/completions@, extracts the ` ```lean `
--     fenced block from @.choices[0].message.content@, runs it through the
--     anti-laundering guard, then kernel-checks it with @lake env lean@.
--   * @legacy@ (@lean-lsp-mcp@): still a stub ('LeanstralUnavailable').
--
-- The API key is read from the environment (@LLMLL_LEANSTRAL_API_KEY@) by the
-- caller and passed to 'proveWithLeanstral' as an argument. It is never stored
-- in the (Show-able) 'MCPConfig', never placed on curl's argv, never persisted
-- to a file, and never logged.
module LLMLL.MCPClient
  ( MCPConfig(..)
  , MCPResult(..)
  , callLeanstral
  , defaultMCPConfig
  , sanitizeProof
    -- * Direct Leanstral pipeline (Layer-3)
  , proveWithLeanstral
  , kernelCheck
    -- * Pure helpers (hermetically testable — no network, no lake)
  , extractLeanFence
  , parseChatContent
  , buildChatRequest
  , ensureImport
    -- * Test-only
  , mockProofResult
  ) where

import Control.Exception (bracket_)
import Data.Aeson (eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Types (parseEither)
import qualified Data.ByteString.Lazy as BL
import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, getTemporaryDirectory, removeFile)
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import System.Process
  ( CreateProcess(cwd)
  , proc
  , readCreateProcessWithExitCode
  , readProcessWithExitCode
  )

-- | Configuration for the proof client. Carries no secret — the API key is an
-- argument to 'proveWithLeanstral', so 'Show' can never leak it.
data MCPConfig = MCPConfig
  { mcpCommand     :: Text            -- ^ Path to lean-lsp-mcp binary (legacy stub path)
  , mcpTimeout     :: Int             -- ^ Timeout in seconds (model call + used for lake)
  , mcpMock        :: Bool            -- ^ If True, use mock proof results
  , mcpLeanstral   :: Bool            -- ^ If True, use the direct Leanstral chat-completions path
  , mcpModel       :: Text            -- ^ Model id (default @labs-leanstral-1-5@)
  , mcpEndpoint    :: Text            -- ^ Chat-completions endpoint
  , mcpLeanProject :: Maybe FilePath  -- ^ Lean 4 + Mathlib project dir for kernel checking
  } deriving (Show, Eq)

-- | Default configuration (mock mode off; direct mode off).
defaultMCPConfig :: MCPConfig
defaultMCPConfig = MCPConfig
  { mcpCommand     = "lean-lsp-mcp"
  , mcpTimeout     = 30
  , mcpMock        = True
  , mcpLeanstral   = False
  , mcpModel       = "labs-leanstral-1-5"
  , mcpEndpoint    = "https://api.mistral.ai/v1/chat/completions"
  , mcpLeanProject = Nothing
  }

-- | Result of a proof attempt.
data MCPResult
  = ProofFound Text              -- ^ A kernel-checkable proof term / checked @.lean@ file
  | ProofTimeout                 -- ^ Prover timed out
  | ProofError Text              -- ^ Prover\/kernel returned an error (fail-closed)
  | LeanstralUnavailable Text    -- ^ Endpoint\/binary\/project not reachable (fail-closed)
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Anti-laundering guard (PROOF-ARTIFACT §4.1 LCF invariant)
-- ---------------------------------------------------------------------------

-- | Every 'ProofFound' must be constructed via this helper. It maps a
-- degenerate proof term — empty\/whitespace-only, or one using the @sorry@ or
-- @admit@ tactic (word-boundary aware, so @admittance@\/@sorry_free@ still
-- pass) — to a 'ProofError'. A @sorry@\/@admit@\/empty "proof" can therefore
-- never upgrade evidence to a @verified@\/@leanstral@ tier downstream.
sanitizeProof :: Text -> MCPResult
sanitizeProof p
  | T.null (T.strip p)                = rejected
  | any isBanned (identifierTokens p) = rejected
  | otherwise                         = ProofFound p
  where
    isBanned t = t == "sorry" || t == "admit"
    rejected   = ProofError "degenerate proof term (sorry/admit/empty) rejected"

-- | Split a proof term into maximal runs of identifier characters, so that
-- @sorry@\/@admit@ are matched as whole tokens rather than substrings.
identifierTokens :: Text -> [Text]
identifierTokens = filter (not . T.null) . T.split (not . isIdentChar)
  where
    isIdentChar c = isAlphaNum c || c == '_' || c == '\''

-- ---------------------------------------------------------------------------
-- Legacy / mock entry point
-- ---------------------------------------------------------------------------

-- | Call the legacy\/mock prover for an obligation.
--
--   * mock mode → 'mockProofResult' (routed through 'sanitizeProof').
--   * otherwise → 'LeanstralUnavailable' (the @lean-lsp-mcp@ transport is a
--     stub; the live path is 'proveWithLeanstral', selected by @--leanstral@).
callLeanstral :: MCPConfig -> Text -> IO MCPResult
callLeanstral config obligation
  | mcpMock config = pure (mockProofResult obligation)
  | otherwise =
      pure (LeanstralUnavailable
              "lean-lsp-mcp transport is a stub; use --leanstral for the direct Leanstral path")

-- | Test-only mock prover. Emits the degenerate proof term @by sorry@, which
-- 'sanitizeProof' rejects — so the mock resolves to 'ProofError', never
-- 'ProofFound'. Gated behind @--leanstral-mock@; not used in production.
mockProofResult :: Text -> MCPResult
mockProofResult _obligation = sanitizeProof "by sorry"

-- ---------------------------------------------------------------------------
-- Direct Leanstral pipeline (Layer-3): call → extract → check → record
-- ---------------------------------------------------------------------------

-- | Prove one obligation via the direct Leanstral chat-completions path, then
-- kernel-check the returned proof. Fail-closed at every step.
--
-- @proveWithLeanstral cfg apiKey name theoremText@ where @theoremText@ is the
-- @sorry@-terminated theorem from 'LLMLL.LeanTranslate.translateObligation'.
--
-- 1. POST to @mcpEndpoint@ (model @mcpModel@, key @apiKey@ — never logged).
-- 2. Extract the ` ```lean ` fenced block from @.choices[0].message.content@.
-- 3. Anti-laundering guard: reject a @sorry@\/@admit@\/empty proof.
-- 4. Kernel-check with @lake env lean@ under @mcpLeanProject@.
--
-- Returns @ProofFound checkedLean@ (the kernel-checked @.lean@ source, ready to
-- persist as the certificate) only on a clean check.
proveWithLeanstral :: MCPConfig -> Text -> Text -> Text -> IO MCPResult
proveWithLeanstral cfg apiKey name theoremText = do
  eContent <- callMistralChat cfg apiKey name theoremText
  case eContent of
    Left err      -> pure (LeanstralUnavailable err)
    Right content -> case extractLeanFence content of
      Left err        -> pure (ProofError ("Leanstral response: " <> err))
      Right leanBlock -> case sanitizeProof leanBlock of
        ProofError e -> pure (ProofError e)          -- sorry/admit/empty → fail-closed
        _            -> case mcpLeanProject cfg of
          Nothing   -> pure (LeanstralUnavailable
                               "no --leanstral-lean-project supplied for the kernel check")
          Just proj -> kernelCheck proj (mcpTimeout cfg) leanBlock

-- | POST the prompt to the Mistral chat-completions endpoint via @curl@ and
-- return @.choices[0].message.content@.
--
-- Secret hygiene: the request body (non-secret) is written to a temp file and
-- referenced with @--data-binary \@file@; the @Authorization@ header (secret)
-- is fed through curl's stdin config (@-K -@), so the key never appears on
-- argv, in a persisted file, or in any LLMLL log line.
callMistralChat :: MCPConfig -> Text -> Text -> Text -> IO (Either Text Text)
callMistralChat cfg apiKey name theoremText = do
  tmpDir <- getTemporaryDirectory
  let bodyPath = tmpDir </> ("llmll-leanstral-req-" <> T.unpack (sanitizeFileName name) <> ".json")
      reqBody  = buildChatRequest (mcpModel cfg) (buildPrompt theoremText)
  bracket_
    (BL.writeFile bodyPath reqBody)
    (removeFileIfExists bodyPath)
    (do
      let curlArgs =
            [ "-sS"
            , "--max-time", show (mcpTimeout cfg)
            , "-X", "POST"
            , T.unpack (mcpEndpoint cfg)
            , "-H", "Content-Type: application/json"
            , "-K", "-"                              -- read the secret header from stdin
            , "--data-binary", "@" <> bodyPath
            ]
          -- The API key travels ONLY through curl's stdin config here.
          curlConfig = "header = \"Authorization: Bearer " <> apiKey <> "\"\n"
      (ec, out, err) <- readProcessWithExitCode "curl" curlArgs (T.unpack curlConfig)
      case ec of
        ExitFailure code | null out ->
          pure (Left ("curl POST failed (exit " <> T.pack (show code) <> "): "
                       <> T.strip (T.pack err)))
        _ -> pure (parseChatContent (textToLbs (T.pack out))))

-- | The user prompt: ask for a complete, self-contained Lean 4 file with a full
-- proof (no @sorry@\/@admit@) in a single ` ```lean ` fenced block.
buildPrompt :: Text -> Text
buildPrompt theoremText = T.unlines
  [ "You are a Lean 4 theorem prover with Mathlib available."
  , "Complete the following theorem by replacing `sorry` with a full proof."
  , "Return the COMPLETE Lean 4 file (including `import Mathlib.Tactic`) in a"
  , "single ```lean fenced code block. Do not use `sorry` or `admit`."
  , ""
  , "```lean"
  , T.stripEnd theoremText
  , "```"
  ]

-- | Build the chat-completions request body.
buildChatRequest :: Text -> Text -> BL.ByteString
buildChatRequest model prompt = encode $ object
  [ "model"       .= model
  , "messages"    .= [ object [ "role" .= ("user" :: Text), "content" .= prompt ] ]
  , "temperature" .= (0.0 :: Double)
  ]

-- | Extract @.choices[0].message.content@ from a chat-completions JSON body.
-- On a Mistral error body, surface @.error.message@ as a @Left@.
parseChatContent :: BL.ByteString -> Either Text Text
parseChatContent raw =
  case eitherDecode raw of
    Left e    -> Left ("could not decode Mistral response as JSON: " <> T.pack e)
    Right val -> case parseEither contentP val of
      Right c -> Right c
      Left _  -> case parseEither errorP val of
        Right msg -> Left ("Mistral API error: " <> msg)
        Left _    -> Left "Mistral response had no choices[0].message.content"
  where
    contentP = withObject "response" $ \o -> do
      choices <- o .: "choices"
      case choices of
        (c0 : _) -> flip (withObject "choice") c0 $ \co -> do
          msg <- co .: "message"
          flip (withObject "message") msg $ \mo -> mo .: "content"
        [] -> fail "empty choices"
    errorP = withObject "response" $ \o -> do
      err <- o .: "error"
      flip (withObject "error") err $ \eo -> eo .: "message"

-- | Extract the ` ```lean ` (or ` ```lean4 `) fenced code block from a
-- prose+fence model response. Fail-closed if absent\/empty.
extractLeanFence :: Text -> Either Text Text
extractLeanFence content =
  let (_, afterMarker) = T.breakOn "```lean" content
  in if T.null afterMarker
       then Left "no ```lean fenced block in response"
       else
         let afterTag   = T.drop (T.length "```lean") afterMarker  -- may start with "4" or newline
             afterLine  = T.drop 1 (T.dropWhile (/= '\n') afterTag)
             (block, _) = T.breakOn "```" afterLine
             trimmed    = T.strip block
         in if T.null trimmed
              then Left "empty ```lean fenced block"
              else Right trimmed

-- ---------------------------------------------------------------------------
-- Kernel check
-- ---------------------------------------------------------------------------

-- | Kernel-check a Lean source with @lake env lean@ under the given Mathlib
-- project. Success iff exit 0, no @error:@ diagnostic, and no residual
-- @sorry@\/@admit@ in the output. Returns @ProofFound checkedSource@ on success.
kernelCheck :: FilePath -> Int -> Text -> IO MCPResult
kernelCheck projectDir _timeoutSecs leanSource = do
  let src      = ensureImport leanSource
      leanFile = projectDir </> "LlmllLeanstralCheck.lean"
  projExists <- doesDirectoryExist projectDir
  if not projExists
    then pure (LeanstralUnavailable ("--leanstral-lean-project not found: " <> T.pack projectDir))
    else do
      TIO.writeFile leanFile src
      (ec, out, err) <- readCreateProcessWithExitCode
                          ((proc "lake" ["env", "lean", leanFile]) { cwd = Just projectDir })
                          ""
      let output      = T.pack (out <> err)
          hasError    = "error:" `T.isInfixOf` output
          hasResidual = "sorry" `T.isInfixOf` output || "admit" `T.isInfixOf` output
      case ec of
        ExitSuccess
          | not hasError && not hasResidual -> pure (ProofFound src)
          | otherwise -> pure (ProofError
              ("lean kernel check: residual sorry/error — " <> firstDiagLine output))
        ExitFailure c -> pure (ProofError
          ("lean kernel check failed (lake exit " <> T.pack (show c) <> "): " <> firstDiagLine output))

-- | Ensure the source imports Mathlib.Tactic (idempotent).
ensureImport :: Text -> Text
ensureImport src
  | "import Mathlib" `T.isInfixOf` src = src
  | otherwise                          = "import Mathlib.Tactic\n\n" <> src

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- | First diagnostic-ish line of a compiler output (prefer an @error:@ line).
firstDiagLine :: Text -> Text
firstDiagLine out =
  let ls = filter (not . T.null . T.strip) (T.lines out)
  in case filter ("error:" `T.isInfixOf`) ls of
       (e : _) -> T.strip e
       []      -> case ls of
                    (l : _) -> T.strip l
                    []      -> "(no output)"

-- | Sanitize a name for use in a temp filename.
sanitizeFileName :: Text -> Text
sanitizeFileName = T.map (\c -> if isAlphaNum c then c else '_')

-- | Text → lazy ByteString (UTF-8), for feeding aeson.
textToLbs :: Text -> BL.ByteString
textToLbs = BL.fromStrict . TE.encodeUtf8

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists fp = do
  exists <- doesFileExist fp
  if exists then removeFile fp else pure ()
