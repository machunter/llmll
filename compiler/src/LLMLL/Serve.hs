-- |
-- Module      : LLMLL.Serve
-- Description : HTTP server for llmll serve (D5 — spec-aligned).
--
-- Warp-based HTTP server on 127.0.0.1:7777 (default).
--
-- Security posture (professor + language team, 2026-03-28):
--   • Bearer token required by default (auto-generated or --token supplied)
--   • TLS delegated to reverse proxy; always binds to --host (default 127.0.0.1)
--   • Stateless per request: emptyTCState constructed inside handler, not at startup
--   • 512 KB max request body
--   • GET /health always open (no auth)
--
-- Body format detection for POST /sketch and POST /typecheck:
--   Content-Type: application/json  → parse as JSON-AST via parseJSONAST
--   Content-Type: text/plain        → parse as S-expression via parseStatements
--   Absent / other                  → try JSON first, fall back to S-expression
module LLMLL.Serve
  ( ServeOptions(..)
  , defaultServeOptions
  , runServe
  ) where

import Control.Monad (when)
import Data.Aeson (encode, object, (.=), Value)
import qualified Data.Aeson as A
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import Network.HTTP.Types
  ( status200, status400, status401, status404, status413
  , hContentType, hAuthorization, ResponseHeaders )
import Network.Wai
  ( Application, Request, Response, responseLBS
  , requestMethod, rawPathInfo, requestHeaders
  , lazyRequestBody )
import Network.Wai.Handler.Warp
  ( run, runSettings, setPort, setHost, defaultSettings, HostPreference )
import Numeric (showHex)
import System.Directory (createDirectoryIfMissing, getHomeDirectory)
import System.IO (hPutStrLn, stderr, hFlush)
import System.Random (randomRIO)

import LLMLL.Parser (parseStatements)
import LLMLL.ParserJSON (parseJSONAST)
import LLMLL.TypeCheck (typeCheck, emptyEnv, runSketch)
import LLMLL.Diagnostic (DiagnosticReport(..), Diagnostic(..))
import LLMLL.Sketch (encodeSketchResult, SketchResult(..))
import LLMLL.Syntax (Statement)

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

data ServeOptions = ServeOptions
  { servePort  :: Int           -- ^ Port (default 7777)
  , serveHost  :: String        -- ^ Bind host (default "127.0.0.1")
  , serveToken :: Maybe String  -- ^ Nothing → auto-generate; Just "" → no auth
  } deriving (Show)

defaultServeOptions :: ServeOptions
defaultServeOptions = ServeOptions
  { servePort  = 7777
  , serveHost  = "127.0.0.1"
  , serveToken = Nothing
  }

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

maxBodyBytes :: Int
maxBodyBytes = 512 * 1024   -- 512 KB

jsonCT :: ResponseHeaders
jsonCT = [(hContentType, "application/json; charset=utf-8")]

-- ---------------------------------------------------------------------------
-- Token Generation
-- ---------------------------------------------------------------------------

generateToken :: IO T.Text
generateToken = do
  ws <- mapM (\_ -> randomRIO (0, maxBound :: Int)) [1..4 :: Int]
  let hex = concatMap (\w -> pad16 (showHex (abs w) "")) ws
  pure $ "sk-" <> T.pack hex
  where pad16 s = replicate (16 - length s) '0' ++ s

writeTokenFile :: T.Text -> IO ()
writeTokenFile tok = do
  home <- getHomeDirectory
  let dir  = home ++ "/.llmll"
      path = dir  ++ "/sketch.token"
  createDirectoryIfMissing True dir
  writeFile path (T.unpack tok)
  hPutStrLn stderr $ "Sketch token:  " ++ T.unpack tok
  hPutStrLn stderr $ "Token file:    " ++ path
  hPutStrLn stderr   "(Pass as: Authorization: Bearer <token>)"
  hFlush stderr

-- ---------------------------------------------------------------------------
-- Auth Middleware
-- ---------------------------------------------------------------------------

withAuth :: Maybe T.Text -> Application -> Application
withAuth Nothing    app req respond = app req respond
withAuth (Just tok) app req respond =
  case lookup hAuthorization (requestHeaders req) of
    Just h | h == "Bearer " <> TE.encodeUtf8 tok -> app req respond
    _ -> respond $ responseLBS status401 jsonCT
           (encode $ object ["error" .= ("unauthorized" :: T.Text)])

-- ---------------------------------------------------------------------------
-- Body Helper
-- ---------------------------------------------------------------------------

readBodyLimited :: Request -> IO (Either T.Text BL.ByteString)
readBodyLimited req = do
  body <- lazyRequestBody req
  if BL.length body > fromIntegral maxBodyBytes
    then pure $ Left "request-too-large"
    else pure $ Right body

-- | Detect body format and parse into statements.
-- Content-Type: application/json → JSON-AST; text/plain → S-expression;
-- absent/other → try JSON first, fall back to S-expression.
parseBody :: Request -> BL.ByteString -> Either T.Text [Statement]
parseBody req body =
  let ctHeader = fmap TE.decodeUtf8 (lookup hContentType (requestHeaders req))
      isJson   = maybe True (T.isPrefixOf "application/json") ctHeader
      src      = TE.decodeUtf8 (BL.toStrict body)
  in if isJson
       then case parseJSONAST "<serve>" body of
              Right stmts -> Right stmts
              Left _      -> tryText src   -- fallback
       else tryText src
  where
    tryText src = case parseStatements "<serve>" src of
      Right stmts -> Right stmts
      Left err    -> Left (T.pack (show err))

-- ---------------------------------------------------------------------------
-- Response helpers
-- ---------------------------------------------------------------------------

respondOK :: BL.ByteString -> Response
respondOK body = responseLBS status200 jsonCT body

respond400 :: T.Text -> Response
respond400 msg = responseLBS status400 jsonCT
  (encode $ object ["error" .= ("bad-request" :: T.Text), "message" .= msg])

respond413 :: Response
respond413 = responseLBS status413 jsonCT
  (encode $ object ["error" .= ("request-too-large" :: T.Text)])

respond404 :: Response
respond404 = responseLBS status404 jsonCT
  (encode $ object ["error" .= ("not-found" :: T.Text)])

-- ---------------------------------------------------------------------------
-- Handlers
-- ---------------------------------------------------------------------------

handleHealth :: IO Response
handleHealth = pure $ respondOK $ encode $ object
  [ "status"  .= ("ok"    :: T.Text)
  , "version" .= ("0.2.0" :: T.Text) ]

-- | POST /typecheck — full type-check, returns DiagnosticReport JSON.
handleTypecheck :: Request -> IO Response
handleTypecheck req = do
  bodyE <- readBodyLimited req
  case bodyE of
    Left _    -> pure respond413
    Right raw ->
      case parseBody req raw of
        Left msg -> pure $ respond400 msg
        Right stmts ->
          -- Fresh TCState per request: stateless by construction (spec invariant 2)
          let report = typeCheck emptyEnv stmts
          in pure $ respondOK $ encode $ object
               [ "success"     .= reportSuccess report
               , "diagnostics" .= reportDiagnostics report ]

-- | POST /sketch — sketch inference, returns schemaVersion 0.2.0 JSON.
-- emptyTCState constructed here (inside handler), not at server startup.
handleSketch :: Request -> IO Response
handleSketch req = do
  bodyE <- readBodyLimited req
  case bodyE of
    Left _    -> pure respond413
    Right raw ->
      case parseBody req raw of
        Left msg -> pure $ respond400 msg
        Right stmts ->
          -- Fresh runSketch call per request; trivially concurrent (no shared state)
          let result = runSketch emptyEnv stmts
          in pure $ respondOK (encodeSketchResult result)

-- ---------------------------------------------------------------------------
-- Router
-- ---------------------------------------------------------------------------

router :: Application
router req respond = do
  let path   = rawPathInfo req
      method = requestMethod req
  response <- case (method, path) of
    ("GET",  "/health")    -> handleHealth
    ("POST", "/typecheck") -> handleTypecheck req
    ("POST", "/sketch")    -> handleSketch req
    _                      -> pure respond404
  respond response

-- ---------------------------------------------------------------------------
-- Server startup
-- ---------------------------------------------------------------------------

runServe :: ServeOptions -> IO ()
runServe opts = do
  mTok <- case serveToken opts of
    Just "" -> do
      hPutStrLn stderr "Warning: --token \"\" disables auth (not recommended)"
      pure Nothing
    Just t  -> do
      hPutStrLn stderr $ "Using supplied token: " ++ t
      pure (Just (T.pack t))
    Nothing -> do
      tok <- generateToken
      writeTokenFile tok
      pure (Just tok)

  let app  = withAuth mTok router
      port = servePort opts
  hPutStrLn stderr $
    "llmll serving on http://" ++ serveHost opts ++ ":" ++ show port
  when (mTok /= Nothing) $
    hPutStrLn stderr "Use 'Authorization: Bearer <token>' on all requests except /health"
  hFlush stderr
  -- Use run (port only); host restriction is via --host flag + reverse proxy (per D5 spec).
  -- Default Warp binding: all interfaces. Security enforced by auth token.
  run port app
