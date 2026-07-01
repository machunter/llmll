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
  , scaffoldCacheRoot
  , resolveScaffold
  ) where

import System.FilePath ((</>), (<.>), splitFileName, dropExtension)
import System.Directory (getHomeDirectory, createDirectoryIfMissing, doesFileExist)
import qualified Codec.Archive.Tar     as Tar
import qualified Codec.Compression.GZip as GZip
import qualified Data.ByteString.Lazy  as BL
import Data.List (isPrefixOf, isSuffixOf, intercalate)

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

-- | Return the first file path that exists, or Nothing.
firstExisting :: [FilePath] -> IO (Maybe FilePath)
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
--
-- Each entry path arrives as "<package>-<version>/rest/of/path" (the
-- `stack pack` / `cabal sdist` layout). The top-level directory is NOT a
-- bare prefix to discard: it encodes both the package name and version,
-- which must be reconstituted into the cache's <package>/<version>/...
-- directory structure (see hubCacheRoot / resolveHubPath). Simply
-- stripping the top-level segment (dropping it entirely) would flatten
-- every package's files into the shared cache root, colliding across
-- packages and losing the version directory.
installEntries :: FilePath -> Tar.Entries Tar.FormatError -> IO (Either String ())
installEntries root entries = go entries
  where
    go Tar.Done        = pure (Right ())
    go (Tar.Fail err)  = pure (Left $ "Tar error: " ++ show err)
    go (Tar.Next e es) = do
      case Tar.entryContent e of
        Tar.NormalFile bs _ -> do
          let rawPath = Tar.entryPath e
          case destPathFor root rawPath of
            Nothing       -> go es  -- entry has no top-level dir; skip (malformed tarball)
            Just destPath -> do
              createDirectoryIfMissing True (fst (splitFileName destPath))
              BL.writeFile destPath bs
              go es
        _ -> go es   -- ignore directories, symlinks, etc.

-- | Compute the cache-relative destination for a tar entry. The entry's
-- top-level directory ("<package>-<version>") is rewritten to
-- "<package>/<version>/" instead of being dropped, so a file at
-- "llmll-demo-pkg-0.1.0/math/add.llmll" lands at
-- ~/.llmll/modules/llmll-demo-pkg/0.1.0/math/add.llmll, matching
-- resolveHubPath's expected layout.
destPathFor :: FilePath -> FilePath -> Maybe FilePath
destPathFor root rawPath =
  case break (== '/') rawPath of
    (topDir, '/':rest) | not (null rest) ->
      let (pkg, ver) = splitPkgVersion topDir
      in Just $ if null ver
                  then root </> pkg </> rest
                  else root </> pkg </> ver </> rest
    _ -> Nothing  -- no top-level directory in this entry path

-- | Split a "<package>-<version>" directory name into (package, version).
-- The version is taken to be the last '-'-separated segment if it looks
-- like a semver (contains a '.' and is otherwise digits/dots) — matching
-- the version-shape heuristic resolveHubPath already uses. If no segment
-- looks like a version, the whole name is treated as the package with no
-- version directory.
splitPkgVersion :: String -> (String, String)
splitPkgVersion name =
  case reverse (splitOnDash name) of
    (lastSeg : rest@(_:_)) | looksLikeVersion lastSeg ->
      (intercalate "-" (reverse rest), lastSeg)
    _ -> (name, "")
  where
    looksLikeVersion t = '.' `elem` t && all (\c -> c == '.' || c `elem` ['0'..'9']) t

    splitOnDash s = case break (== '-') s of
      (seg, '-':rest) -> seg : splitOnDash rest
      (seg, "")       -> [seg]
      (seg, _)        -> [seg]

-- ---------------------------------------------------------------------------
-- Scaffold template resolution
-- ---------------------------------------------------------------------------

-- | Root directory for scaffold templates.
-- ~/.llmll/templates/
scaffoldCacheRoot :: IO FilePath
scaffoldCacheRoot = do
  home <- getHomeDirectory
  pure (home </> ".llmll" </> "templates")

-- | Resolve a scaffold template name to a file path.
-- Looks in ~/.llmll/templates/<template>/scaffold.ast.json (or .llmll).
resolveScaffold :: T.Text -> IO (Maybe FilePath)
resolveScaffold template = do
  root <- scaffoldCacheRoot
  let dir = root </> T.unpack template
      candidates = [dir </> "scaffold.ast.json", dir </> "scaffold.llmll"]
  firstExisting candidates
