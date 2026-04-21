{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}
-- | Minimal effectful program for WASM compatibility spike.
-- Tests: can effectful's Eff monad and IOE effect compile under wasm32-wasi?
module Main where

import Effectful
import Effectful.State.Static.Local

-- | A trivial stateful computation using effectful.
counter :: (State Int :> es) => Eff es Int
counter = do
  modify @Int (+ 1)
  get @Int

main :: IO ()
main = do
  let result = runPureEff $ runState (0 :: Int) counter
  case result of
    (n, _) -> putStrLn $ "Counter: " ++ show n
