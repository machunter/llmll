-- |
-- Module      : LLMLL.RuntimePure
-- Description : PBT-EVAL-PARITY-1. The pure runtime builtins, compiled into
--               the compiler so the test-path evaluator runs the SAME code
--               the generated program runs.
--
-- The generated program does not import this module: it carries its own copy
-- of each definition in 'LLMLL.CodegenHs.runtimePreamble'. The two copies are
-- kept equal by a test, not by construction. Every blank-line-separated block
-- between the BEGIN and END markers below must appear, line for line, as a
-- contiguous run of 'runtimePreamble' (Spec.hs, "PBT-EVAL-PARITY-1: every
-- RuntimePure block is in the preamble verbatim"). Edit one copy and that test
-- fails and names the block.
--
-- Why it matters: 'LLMLL.Contracts.evalBuiltinApp' answers a property sample
-- with these functions, and a passing property writes `tested` evidence
-- (LLMLL.md §4.4.5). An evaluator that disagreed with the built program would
-- write evidence about a program nobody runs.
--
-- The imports use the preamble's qualified aliases (LRX, LChar, LFold, LList, Map) so the
-- region is the preamble's text exactly. Leaf module: no LLMLL imports.
module LLMLL.RuntimePure where

import Data.List (isPrefixOf, intercalate, foldl')
import qualified Text.Regex.TDFA as LRX
import qualified Data.Char as LChar
import qualified Data.Foldable as LFold
import qualified Data.List as LList
import qualified Data.Map.Strict as Map
import Control.Exception (try, evaluate, SomeException)
import System.IO.Unsafe (unsafePerformIO)
import qualified GHC.Arr as LArr
import qualified System.Mem.StableName as LSN
import qualified Data.IORef as LRef

-- BEGIN RUNTIME-PURE
llmll_uW :: a -> ()
llmll_uW x = x `seq` ()

llmll_uL :: (a -> ()) -> [a] -> ()
llmll_uL _ []     = ()
llmll_uL r (y:ys) = r y `seq` llmll_uL r ys

llmll_uS :: [a] -> ()
llmll_uS = llmll_uL llmll_uW

list_contains :: Eq a => [a] -> a -> Bool
list_contains = flip elem

list_nth :: [a] -> Int -> Either String a
list_nth xs i
  | i < 0 || i >= length xs = Left ("list_nth: index " ++ show i ++ " out of range")
  | otherwise               = Right (xs !! i)

range :: Integer -> Integer -> [Integer]
range from to = [from .. to - 1]

list_sort :: Ord a => [a] -> [a]
list_sort = LList.sort

list_sort_by :: Ord k => [a] -> (a -> k) -> [a]
list_sort_by xs key = LList.sortOn key xs

list_reverse :: [a] -> [a]
list_reverse = reverse

map_keys :: Map.Map k v -> [k]
map_keys = Map.keys

map_entries :: Map.Map k v -> [(k, v)]
map_entries = Map.toAscList

string_contains :: String -> String -> Bool
string_contains haystack needle = any (needle `isPrefixOf`) (tails haystack)
  where tails [] = [[]]; tails s@(_:xs) = s : tails xs

string_concat :: String -> String -> String
string_concat a b = llmll_appendS a b

llmll_appendS :: [a] -> [a] -> [a]
llmll_appendS [] b     = b
llmll_appendS (c:cs) b = let r = llmll_appendS cs b in r `seq` (c : r)

string_slice :: String -> Int -> Int -> String
-- Out-of-range endpoints CLAMP, matching the out-of-range convention
-- string_char_at already implements below (return the empty result rather
-- than index off the end). `from` and `to` are each clamped into [0, n],
-- and the result is the half-open [from, to) window of what survives; a
-- transposed pair (to <= from) still yields "", as the spec's string
-- builtin table documents.
-- The clamp on `from` is what keeps the LENGTH right: the unclamped form
-- `take (to - from) (drop from s)` fed a negative `from` into the take
-- count while `drop` no-opped on it, so string_slice "abc" (-1) 1
-- returned "ab" -- two characters for a one-character window.
-- STR-INDEX-LINEAR-1: a window that starts at 32 or later reads the cached
-- array of s (llmll_strIx below), so a scan of windows over one string is
-- linear rather than quadratic. Same result as the list walk for every input.
string_slice s from to
  | max 0 from < 32 =
      let n  = length s
          lo = min n (max 0 from)
          hi = min n (max 0 to)
      in if hi <= lo then "" else take (hi - lo) (drop lo s)
  | otherwise =
      let (a, n) = llmll_strIx s
          lo = min n (max 0 from)
          hi = min n (max 0 to)
      in if hi <= lo then "" else [ a LArr.! k | k <- [lo .. hi - 1] ]

-- STR-INDEX-LINEAR-1: an index below 32 walks the list, which costs i steps
-- and allocates nothing; a larger index reads the cached array of s. The
-- documented decomposition (list-map (range 0 n) (fn [i] (string-char-at s i)))
-- was quadratic through `s !! i` and is linear now.
string_char_at :: String -> Int -> String
string_char_at s i
  | i < 0     = ""
  | i < 32    = case drop i s of { (c:_) -> [c]; [] -> "" }
  | otherwise = let (a, n) = llmll_strIx s in if i < n then [a LArr.! i] else ""

-- STR-INDEX-LINEAR-1. A random-access copy of each of the last four strings
-- indexed past 32, keyed by StableName. Equal StableNames are one heap object,
-- so the cached array always holds that string's characters: a hit cannot
-- answer for a different string, and a miss only costs one O(n) copy. The
-- answer never depends on the cache, so the builtin stays a pure function and
-- codegen_semantics_version does not change. EVAL-STRICT-1 has already forced
-- s to a value, which is what keeps its StableName stable across calls.
llmll_strCache :: LRef.IORef [(LSN.StableName String, LArr.Array Int Char, Int)]
llmll_strCache = unsafePerformIO (LRef.newIORef [])
{-# NOINLINE llmll_strCache #-}

llmll_strIx :: String -> (LArr.Array Int Char, Int)
llmll_strIx s = unsafePerformIO $ do
  sn <- LSN.makeStableName $! s
  es <- LRef.readIORef llmll_strCache
  case [ (a, n) | (sn', a, n) <- es, sn' == sn ] of
    (hit : _) -> return hit
    [] -> do
      let n = length s
          a = LArr.listArray (0, n - 1) s
      a `seq` LRef.atomicModifyIORef' llmll_strCache (\cur -> (take 4 ((sn, a, n) : cur), ()))
      return (a, n)
{-# NOINLINE llmll_strIx #-}

string_split :: String -> String -> [String]
string_split _   []  = [""]
string_split []  str = [str]
string_split sep str = go str
  where
    n = length sep
    go s = case brk [] s of
      (w, Nothing)   -> [w]
      (w, Just rest) -> w : go rest
    brk acc t
      | sep `isPrefixOf` t = (reverse acc, Just (drop n t))
      | otherwise = case t of
          []     -> (reverse acc, Nothing)
          (c:cs) -> brk (c:acc) cs

string_trim :: String -> String
string_trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
  where isSpace c = c `elem` (" \t\n\r" :: String)

-- | PREAMBLE COMPROMISE (v0.7): unsafePerformIO preserves the pure type
-- of each regex builtin while catching invalid patterns at run time.
-- Do NOT remove the try/evaluate wrapper — it prevents partiality.
--
-- REGEX-CAPTURE-1: the wrapper forces the WHOLE result (the forcer is the
-- builtin's esResultForcers entry) inside the try. evaluate alone reaches
-- weak head normal form, and a pattern error found after the try returned
-- would crash the program instead of answering the fallback.
llmll_rxTotal :: (a -> ()) -> a -> a -> a
llmll_rxTotal force fallback v =
  case unsafePerformIO (try (evaluate (force v `seq` v))) of
    Right x -> x
    Left e  -> const fallback (e :: SomeException)

-- | REGEX-CASE-1: a leading (?i) compiles the rest without regard to case.
-- (?i) anywhere else stays in the pattern, where regex-tdfa rejects it.
-- LLMLL.RegexPattern.splitCaseFlag is the same rule at check time.
llmll_rxCompile :: String -> LRX.Regex
llmll_rxCompile ('(':'?':'i':')':rest) =
  LRX.makeRegexOpts LRX.defaultCompOpt { LRX.caseSensitive = False } LRX.defaultExecOpt rest
llmll_rxCompile pattern =
  LRX.makeRegexOpts LRX.defaultCompOpt LRX.defaultExecOpt pattern

llmll_uP :: (a, b) -> ()
llmll_uP (a, b) = a `seq` b `seq` ()

regex_match :: String -> String -> Bool
regex_match pattern subject =
  llmll_rxTotal llmll_uW False (LRX.matchTest (llmll_rxCompile pattern) subject)

-- | The leftmost match as [whole, group 1 .. group N]; [] for no match. A
-- group that took no part in the match reads "".
regex_find :: String -> String -> [String]
regex_find pattern subject = llmll_rxTotal (llmll_uL llmll_uS) [] $
  case LRX.matchOnceText (llmll_rxCompile pattern) subject of
    Nothing        -> []
    Just (_, m, _) -> map fst (LFold.toList m)

-- | Every non-overlapping match, left to right, each shaped as regex_find's.
regex_find_all :: String -> String -> [[String]]
regex_find_all pattern subject = llmll_rxTotal (llmll_uL (llmll_uL llmll_uS)) [] $
  map (map fst . LFold.toList) (LRX.matchAllText (llmll_rxCompile pattern) subject)

-- | The (start, end) half-open character span of each regex_find_all match.
regex_spans :: String -> String -> [(Integer, Integer)]
regex_spans pattern subject = llmll_rxTotal (llmll_uL llmll_uP) [] $
  [ (fromIntegral o, fromIntegral (o + l))
  | m <- LRX.matchAllText (llmll_rxCompile pattern) subject
  , (_, (o, l)) <- take 1 (LFold.toList m) ]

regex_replace_all :: String -> String -> String -> String
regex_replace_all pattern subject replacement = go 0 subject (regex_spans pattern subject)
  where
    go _ rest [] = rest
    go pos rest ((s, e) : more) =
      let (kept, rest') = splitAt (fromIntegral (s - pos)) rest
      in kept ++ replacement ++ go e (drop (fromIntegral (e - s)) rest') more

-- | REGEX-CASE-1: per-character simple case mapping; keeps the length.
string_lower :: String -> String
string_lower = map LChar.toLower

string_upper :: String -> String
string_upper = map LChar.toUpper

string_compare :: String -> String -> Integer
string_compare a b = case compare a b of
  LT -> -1
  EQ -> 0
  GT -> 1

path_normalize :: String -> String
path_normalize "" = "."
path_normalize p =
  let absP = "/" `isPrefixOf` p
      segs = filter (\x -> x /= "" && x /= ".") (llmll_splitSlash p)
      step acc ".." = case acc of
        (x:xs) | x /= ".." -> xs
        _ | absP      -> acc
          | otherwise -> ".." : acc
      step acc x = x : acc
      body = intercalate "/" (reverse (foldl' step [] segs))
  in if absP then '/' : body else (if null body then "." else body)

llmll_splitSlash :: String -> [String]
llmll_splitSlash str = case break (== '/') str of
  (a, [])       -> [a]
  (a, _ : rest) -> a : llmll_splitSlash rest

string_to_int :: String -> Either String Integer
string_to_int s = case reads s of
  [(n, "")] -> Right n
  _         -> Left ("string_to_int: cannot parse '" ++ s ++ "'")

llmll_abs :: Integer -> Integer
llmll_abs = abs

llmll_min :: Integer -> Integer -> Integer
llmll_min = min

llmll_max :: Integer -> Integer -> Integer
llmll_max = max
-- END RUNTIME-PURE

-- STR-INDEX-LINEAR-1: the list-walk definitions the cached ones replaced. Not
-- emitted; Spec.hs checks the emitted definitions against these with
-- QuickCheck, so the cache cannot change an answer unnoticed.
string_slice_ref :: String -> Int -> Int -> String
string_slice_ref s from to =
  let n  = length s
      lo = min n (max 0 from)
      hi = min n (max 0 to)
  in if hi <= lo then "" else take (hi - lo) (drop lo s)

string_char_at_ref :: String -> Int -> String
string_char_at_ref s i = if i >= 0 && i < length s then [s !! i] else ""
