{-# LANGUAGE ScopedTypeVariables #-}
-- | VERIFY-BUDGET-1: run the solver under a memory limit and a time limit.
--
-- liquid-fixpoint starts z3 as a child process, and the two together can use
-- several gigabytes (VERIFY-MEMORY-1: 4.7-6.8 GB on one example). macOS does
-- not enforce RLIMIT memory limits, so an rlimit cannot stop it. This module
-- starts the solver in its own process group, adds up the resident memory of
-- every process in that group about twice a second, and kills the whole group
-- when it goes over a limit or runs too long. It also kills every live group
-- when llmll itself gets SIGINT or SIGTERM, so no solver outlives the run.
--
-- The limits are global for one llmll run ('setSolverLimits' at start-up),
-- because seven call sites start the solver and all of them must use them.
module LLMLL.SolverGuard
  ( SolverLimits(..)
  , defaultSolverLimits
  , setSolverLimits
  , getSolverLimits
  , renderLimits
  , parseLimits
  , StopKind(..)
  , renderStopKind
  , ResourceStop(..)
  , runSolverGuarded
  , QualSyntax(..)
  , decideQualSyntax
  , sumGroupRssKb
  , installSolverSignalHandlers
  ) where

import Control.Concurrent (forkIO, myThreadId, threadDelay, throwTo)
import Control.Concurrent.MVar
import Control.Exception (AsyncException(UserInterrupt), SomeException, evaluate, onException, try, mask, throwIO)
import Control.Monad (forM_, void, when)
import qualified Data.ByteString as BS
import Data.IORef
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as TE
import System.Directory (doesFileExist, getTemporaryDirectory, removeFile)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Clock (getMonotonicTime)
import System.Exit (ExitCode(..))
import System.IO
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Signals (installHandler, Handler(..), sigTERM, sigINT, sigKILL, signalProcessGroup)
import System.Posix.Types (CPid)
import System.Process
import System.Timeout (timeout)
import Text.Read (readMaybe)

import LLMLL.FixpointIR (qualifiersToBraces)

-- | The two limits. 0 turns a limit off.
data SolverLimits = SolverLimits
  { slMemMb    :: Int   -- ^ resident memory of the whole solver group, MB
  , slTimeSecs :: Int   -- ^ wall-clock seconds
  } deriving (Show, Eq)

-- | 2 GB and 120 s. The largest committed example needs 4.7-6.8 GB
-- (VERIFY-MEMORY-1); every other file of the 577-file corpus solves in
-- under 4 s.
defaultSolverLimits :: SolverLimits
defaultSolverLimits = SolverLimits { slMemMb = 2048, slTimeSecs = 120 }

{-# NOINLINE limitsRef #-}
limitsRef :: IORef SolverLimits
limitsRef = unsafePerformIO (newIORef defaultSolverLimits)

setSolverLimits :: SolverLimits -> IO ()
setSolverLimits = writeIORef limitsRef

getSolverLimits :: IO SolverLimits
getSolverLimits = readIORef limitsRef

-- | The form recorded in a proof artifact's @resource_limits@.
renderLimits :: SolverLimits -> Text
renderLimits l = "mem=" <> T.pack (show (slMemMb l)) <> "MB;time=" <> T.pack (show (slTimeSecs l)) <> "s"

-- | Inverse of 'renderLimits'.
parseLimits :: Text -> Maybe SolverLimits
parseLimits t = case T.splitOn ";" t of
  [m, s] -> SolverLimits <$> num "mem=" "MB" m <*> num "time=" "s" s
  _      -> Nothing
  where
    num pre suf x = do
      a <- T.stripPrefix pre x
      b <- T.stripSuffix suf a
      n <- readMaybe (T.unpack b)
      if n >= 0 then Just n else Nothing

data StopKind = StopMemory | StopTime
  deriving (Show, Eq)

renderStopKind :: StopKind -> Text
renderStopKind StopMemory = "memory"
renderStopKind StopTime   = "time"

-- | Why and when the guard stopped a solver run.
data ResourceStop = ResourceStop
  { rsKind     :: StopKind
  , rsLimits   :: SolverLimits
  , rsPeakMb   :: Int     -- ^ the highest group memory the guard saw
  , rsElapsedS :: Double
  } deriving (Show, Eq)

-- | The process groups of the solver runs that are live now.
{-# NOINLINE liveGroups #-}
liveGroups :: IORef (Set.Set CPid)
liveGroups = unsafePerformIO (newIORef Set.empty)

killGroup :: CPid -> IO ()
killGroup g = void (try (signalProcessGroup sigKILL g) :: IO (Either SomeException ()))

-- | On SIGINT or SIGTERM, kill every live solver group first. SIGINT then
-- raises 'UserInterrupt' in the main thread, as GHC's own handler does, so
-- the REPL and @run@ behave as before; SIGTERM stops the main thread with
-- exit 143. Without this, the solvers of an interrupted run keep running
-- (and keep their memory) after llmll has gone.
installSolverSignalHandlers :: IO ()
installSolverSignalHandlers = do
  mainTid <- myThreadId
  let killAll = do
        gs <- atomicModifyIORef' liveGroups (\s -> (Set.empty, s))
        mapM_ killGroup (Set.toList gs)
  void (installHandler sigINT  (Catch (killAll >> throwTo mainTid UserInterrupt)) Nothing)
  void (installHandler sigTERM (Catch (killAll >> throwTo mainTid (ExitFailure 143))) Nothing)

-- | The total RSS (KB) of the processes in group @g@, from the output of
-- @ps -A -o pgid=,rss=@. Lines that do not parse are skipped.
sumGroupRssKb :: Int -> String -> Int
sumGroupRssKb g out = sum
  [ kb | l <- lines out
       , [a, b] <- [words l]
       , Just pg <- [readMaybe a :: Maybe Int]
       , pg == g
       , Just kb <- [readMaybe b] ]

-- | A failure to run @ps@ reads as 0: the memory limit then does not fire,
-- and the time limit still does.
groupRssKb :: CPid -> IO Int
groupRssKb g = do
  r <- try (readProcessWithExitCode "ps" ["-A", "-o", "pgid=,rss="] "")
  pure $ case r of
    Right (ExitSuccess, out, _) -> sumGroupRssKb (fromIntegral g) out
    Right _                     -> 0
    Left (_ :: SomeException)   -> 0

-- | Run the solver under the current limits. 'Right' is the exit code,
-- stdout and stderr, as 'readProcessWithExitCode' gives them. 'Left' means
-- the guard stopped the run, and no output is returned: a killed solver has
-- no verdict.
runSolverGuarded :: FilePath -> [String] -> IO (Either ResourceStop (ExitCode, String, String))
runSolverGuarded bin args = do
  adaptQualifiers bin args
  runGuardedRaw bin args

-- | FIXPOINT-UPGRADE-1: which qualifier syntax the solver reads.
-- 'QualColon' is @qualif N(v : int): (p)@ (liquid-fixpoint up to 0.9.6.3.3),
-- 'QualBraces' is @qualif N(v : int) { p }@ (0.9.6.3.4 and later).
data QualSyntax = QualColon | QualBraces
  deriving (Show, Eq)

-- | The probe file holds one qualifier in the brace form and nothing else. A
-- solver that reads braces answers Safe with exit 0. A solver that reads only
-- the colon form exits with a parse error. Anything else (a crash, a stop)
-- gives no answer: 'Nothing', and the caller keeps the colon form, which is
-- the form the compiler writes.
decideQualSyntax :: Either ResourceStop (ExitCode, String, String) -> Maybe QualSyntax
decideQualSyntax (Right (ExitSuccess, _, _)) = Just QualBraces
decideQualSyntax (Right (ExitFailure _, out, err))
  | "unexpected '{'" `T.isInfixOf` T.pack (out <> err) = Just QualColon
decideQualSyntax _ = Nothing

probeFqText :: Text
probeFqText = "qualif LlmllProbe(v : int) { (v >= 0) }\n"

-- | The probe answer for each solver path, found once per llmll run.
{-# NOINLINE qualSyntaxRef #-}
qualSyntaxRef :: IORef (Map.Map FilePath QualSyntax)
qualSyntaxRef = unsafePerformIO (newIORef Map.empty)

qualSyntaxFor :: FilePath -> IO QualSyntax
qualSyntaxFor bin = do
  cached <- Map.lookup bin <$> readIORef qualSyntaxRef
  case cached of
    Just q  -> pure q
    Nothing -> do
      dir <- getTemporaryDirectory
      (path, h) <- openTempFile dir "llmll-qualprobe.fq"
      hSetEncoding h utf8
      hPutStr h (T.unpack probeFqText)
      hClose h
      r <- runGuardedRaw bin ["-q", "--json", path]
      removeFile path `catchAny` pure ()
      q <- case decideQualSyntax r of
        Just q  -> pure q
        Nothing -> do
          hPutStrLn stderr $ "llmll: could not tell which qualifier syntax " <> bin
            <> " reads; writing the colon form (liquid-fixpoint 0.9.6.3.3 and earlier)"
          pure QualColon
      atomicModifyIORef' qualSyntaxRef (\m -> (Map.insert bin q m, ()))
      pure q
  where
    catchAny act h = do
      r <- try act
      case r of
        Left (_ :: SomeException) -> h
        Right x                   -> pure x

-- | Rewrite each file argument into the solver's qualifier syntax.
--
-- Every argument that is not a flag and names an existing file is a candidate,
-- whatever its extension: @verify --fq-out@ takes any path, and a filter on
-- @.fq@ left @--fq-out out.bin@ in the colon form, which 0.9.6.3.4 and later
-- cannot parse (the CI gate on 0.9.6.3.7 caught it). Only a UTF-8 file that
-- holds a qualifier line is touched. The probe runs only then, so a
-- qualifier-free solve costs no extra solver start.
adaptQualifiers :: FilePath -> [String] -> IO ()
adaptQualifiers bin args =
  forM_ (filter (not . ("-" `isPrefixOf`)) args) $ \path -> do
    ok <- doesFileExist path
    when ok $ do
      bytes <- BS.readFile path
      case TE.decodeUtf8' bytes of
        Left _    -> pure ()
        Right txt -> when (hasQualifier txt) $ do
          q <- qualSyntaxFor bin
          let txt' = qualifiersToBraces txt
          when (q == QualBraces && txt' /= txt) $
            BS.writeFile path (TE.encodeUtf8 txt')
  where
    hasQualifier t = "qualif " `T.isPrefixOf` t || "\nqualif " `T.isInfixOf` t

-- | The guard itself, with no change to the @.fq@ file.
runGuardedRaw :: FilePath -> [String] -> IO (Either ResourceStop (ExitCode, String, String))
runGuardedRaw bin args = do
  lim <- getSolverLimits
  t0  <- getMonotonicTime
  let cp = (proc bin args)
             { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe
             , create_group = True }
  mask $ \restore -> do
    (Just hin, Just hout, Just herr, ph) <- createProcess cp
    mpid <- getPid ph
    -- 'create_group' makes the child a group leader, so its pid is the pgid.
    let grp = mpid
    forM_ grp $ \g -> atomicModifyIORef' liveGroups (\s -> (Set.insert g s, ()))
    let cleanup = do
          forM_ grp killGroup
          forM_ grp $ \g -> atomicModifyIORef' liveGroups (\s -> (Set.delete g s, ()))
    flip onException cleanup $ restore $ do
      hClose hin
      mapM_ (`hSetEncoding` utf8) [hout, herr]
      outV  <- newEmptyMVar
      errV  <- newEmptyMVar
      doneV <- newEmptyMVar
      let drain h v = void $ forkIO $ do
            r <- try (hGetContents h >>= \s -> evaluate (length s) >> pure s)
            putMVar v (either (\(_ :: SomeException) -> "") id r)
      drain hout outV
      drain herr errV
      -- The executable is not built -threaded, so 'waitForProcess' would block
      -- every Haskell thread, this loop included. 'getProcessExitCode' does
      -- not block; it is polled every 50 ms.
      let poll = do
            r <- try (getProcessExitCode ph)
            case r of
              Left e          -> putMVar doneV (Left e)
              Right (Just c)  -> putMVar doneV (Right c)
              Right Nothing   -> threadDelay 50000 >> poll
      void $ forkIO poll
      let memKb = slMemMb lim * 1024
          secs  = fromIntegral (slTimeSecs lim) :: Double
          stop k peak = do
            cleanup
            void (readMVar doneV)
            el <- subtract t0 <$> getMonotonicTime
            pure (Left (ResourceStop k lim (peak `div` 1024) el))
          loop peak = do
            r <- timeout 500000 (readMVar doneV)
            case r of
              Just (Left (e :: SomeException)) -> throwIO e
              Just (Right code) -> do
                -- Whatever the solver left in its group (a z3 that did not
                -- exit) still holds the output pipes open; kill it first.
                forM_ grp killGroup
                o <- takeMVar outV
                e <- takeMVar errV
                forM_ grp $ \g -> atomicModifyIORef' liveGroups (\s -> (Set.delete g s, ()))
                pure (Right (code, o, e))
              Nothing -> do
                el <- subtract t0 <$> getMonotonicTime
                kb <- if memKb > 0 then maybe (pure 0) groupRssKb grp else pure 0
                let peak' = max peak kb
                if memKb > 0 && kb > memKb then stop StopMemory peak'
                else if slTimeSecs lim > 0 && el > secs then stop StopTime peak'
                else loop peak'
      loop 0
