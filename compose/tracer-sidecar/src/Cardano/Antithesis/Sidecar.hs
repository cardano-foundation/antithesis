{-# LANGUAGE OverloadedStrings #-}


{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module Cardano.Antithesis.Sidecar where

import Cardano.Antithesis.LogMessage
import Cardano.Antithesis.Sdk


import Control.Arrow
    ( second
    )
import Data.Aeson
    ( Value
    )
import Data.List
    ( mapAccumL
    )
import Data.Maybe
    ( catMaybes
    )

-- State -----------------------------------------------------------------------

newtype State = State
  { hasSeenAFork :: Bool -- whether or not any node has seen a fork
  }


initialState :: (State, Maybe Value)
initialState =
  (State False, Just sometimesForksDeclaration)

processMessage :: State -> LogMessage -> (State, Maybe Value)
processMessage state LogMessage{datum} = case (datum, state) of
  (SwitchedToAFork{}, s@(State False)) -> do
    (s { hasSeenAFork = True }, Just sometimesForksReached)
  (_, s) -> (s, Nothing)

processMessages :: (State, Maybe Value) -> [LogMessage] -> (State, [Value])
processMessages st =
    second (catMaybes . (v:))
  . mapAccumL processMessage s
  where
    (s, v) = st

-- IO --------------------------------------------------------------------------

hoistToIO :: (State, Maybe Value) -> IO State
hoistToIO (s, Just v) = writeSdkJsonl v >> return s
hoistToIO (s, _     ) = return s

initialStateIO :: IO State
initialStateIO = hoistToIO initialState

processMessageIO :: State -> LogMessage -> IO State
processMessageIO s msg = hoistToIO $ processMessage s msg

