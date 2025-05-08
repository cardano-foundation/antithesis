{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module Cardano.Antithesis.Sidecar where

import Cardano.Antithesis.LogMessage
import Cardano.Antithesis.Sdk


import Control.Arrow
    ( second
    )
import Control.Monad
    ( forM_
    )
import Data.Aeson
    ( Value
    )
import Data.List
    ( mapAccumL
    )

-- State -----------------------------------------------------------------------

newtype State = State
  { hasSeenAFork :: Bool -- whether or not any node has seen a fork
  }

initialState :: (State, [Value])
initialState =
  (State False, [sometimesForksDeclaration])

processMessage :: State -> LogMessage -> (State, [Value])
processMessage state LogMessage{datum} = case (datum, state) of
  (SwitchedToAFork{}, s@(State False)) -> do
    (s { hasSeenAFork = True }, [sometimesForksReached])
  (_, s) -> (s, [])

processMessages :: (State, [Value]) -> [LogMessage] -> (State, [Value])
processMessages st =
    second (concat . (v:))
  . mapAccumL processMessage s
  where
    (s, v) = st

-- IO --------------------------------------------------------------------------

hoistToIO :: (State, [Value]) -> IO State
hoistToIO (s, vals) = forM_ vals writeSdkJsonl >> return s

initialStateIO :: IO State
initialStateIO = hoistToIO initialState

processMessageIO :: State -> LogMessage -> IO State
processMessageIO s msg = hoistToIO $ processMessage s msg
