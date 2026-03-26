-- |
-- Module      : LLMLL.Hub
-- Description : llmll-hub local cache resolution and tarball installation.
--
-- Phase 2a: local-tarball-only. HTTPS registry fetch is deferred to Phase 2b.
--
-- The hub cache lives at ~/.llmll/modules/<package>/<version>/.
-- Modules are imported with (import hub.<package>.<module>) which routes
-- the resolver to the hub cache before checking the source tree.
--
-- CLI:
--   llmll hub fetch --from-file <tarball>   -- install local tarball into cache
module LLMLL.Hub
  ( resolveHubPath
  , hubFetchLocal
  , hubCacheRoot
  ) where

import System.FilePath ((</>), (<.>), splitFileName, dropExtension)
import System.Directory (getHomeDirectory, createDirectoryIfMissing, doesFileExist)
import qualified Codec.Archive.Tar     as Tar
import qualified Codec.Compression.GZip as GZip
import qualified Data.ByteString.Lazy  as BL
import Data.List (isPrefixOf, isSuffixOf)

import LLMLL.Syntax (ModulePath)
import qualified Data.Text as T

-- ---------------------------------------------------------------------------
-- Cache root
-- ---------------------------------------------------------------------------

-- | Root directory for the local hub cache.
-- ~/.llmll/modules/
hubCacheRoot :: IO FilePath
hubCacheRoot = do
  home <- getHomeDirectory
  pure (home </> ".llmll" </> "modules")

-- ---------------------------------------------------------------------------
-- Path resolution
-- ---------------------------------------------------------------------------

-- | Resolve a hub ModulePath to a concrete FilePath in the local cache.
-- Input: modPath WITHOUT the leading "hub" segment (already stripped by Module.hs).
-- e.g. ["llmll-crypto", "0.1.0", "hash", "bcrypt"]
--      -> ~/.llmll/modules/llmll-crypto/0.1.0/hash/bcrypt.llmll  (tried first)
--      -> ~/.llmll/modules/llmll-crypto/0.1.0/hash/bcrypt.ast.json
--
-- The version segment is optional convention-based — if the second segment looks
-- like a semver (contains '.'), it is treated as a version directory. Otherwise
-- the layout is <package>/<module>... with no version directory.
resolveHubPath :: ModulePath -> IO (Maybe FilePath)
resolveHubPath [] = pure Nothing
resolveHubPath (pkg:rest) = do
  root <- hubCacheRoot
  let (versionAndRest, pkgRoot) = case rest of
        (v:rs) | looksLikeVersion v -> (rs, root </> T.unpack pkg </> T.unpack v)
        rs                          -> (rs, root </> T.unpack pkg)
      stem = foldl (</>) pkgRoot (map T.unpack versionAndRest)
      candidates = [stem <.> "llmll", stem <.> "ast.json"]
  firstExisting candidates
  where
    looksLikeVersion t = '.' `elem` T.unpack t && all (\c -> c == '.' || c `elem` ['0'..'9']) (T.unpack t)
    firstExisting []     = pure Nothing
    firstExisting (f:fs) = doesFileExist f >>= \ex -> if ex then pure (Just f) else firstExisting fs

-- ---------------------------------------------------------------------------
-- Local tarball installation
-- ---------------------------------------------------------------------------

-- | Install a package from a local .tar.gz archive into the hub cache.
--
-- The tarball must have a top-level directory named <package>-<version>/
-- (standard `stack pack` / `cabal sdist` layout). The installer strips that
-- prefix and writes files into ~/.llmll/modules/<package>/<version>/.
--
-- Phase 2a: no network. HTTPS fetch is Phase 2b.
hubFetchLocal :: FilePath               -- ^ path to local .tar.gz
              -> IO (Either String ())
hubFetchLocal tarPath = do
  exists <- doesFileExist tarPath
  if not exists
    then pure (Left $ "File not found: " ++ tarPath)
    else do
      root <- hubCacheRoot
      bs   <- BL.readFile tarPath
      let entries = Tar.read (GZip.decompress bs)
      result <- installEntries root entries
      pure result

-- | Walk Tar entries and write each file to the hub cache.
installEntries :: FilePath -> Tar.Entries Tar.FormatError -> IO (Either String ())
installEntries root entries = go entries
  where
    go Tar.Done        = pure (Right ())
    go (Tar.Fail err)  = pure (Left $ "Tar error: " ++ show err)
    go (Tar.Next e es) = do
      case Tar.entryContent e of
        Tar.NormalFile bs _ -> do
          let rawPath  = Tar.entryPath e
              -- Strip top-level dir (e.g. "llmll-crypto-0.1.0/hash/bcrypt.ast.json")
              destPath = root </> stripTopDir rawPath
          createDirectoryIfMissing True (fst (splitFileName destPath))
          BL.writeFile destPath bs
          go es
        _ -> go es   -- ignore directories, symlinks, etc.

    stripTopDir p =
      case break (== '/') p of
        (_, '/':rest) -> rest
        _             -> p
