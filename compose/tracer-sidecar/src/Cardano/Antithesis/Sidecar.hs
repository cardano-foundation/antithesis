{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.Antithesis.Sidecar where

import qualified Data.Text as T

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
import qualified Data.List as L
import Data.Set
    ( Set
    )
import qualified Data.Set as Set
import Data.Text
    ( Text
    )

-- State -----------------------------------------------------------------------

type TraceKind = Text

newtype State = State
  { scanningFor :: Set TraceKind
  }

initialState :: (State, [Value])
initialState =
  (State $ Set.fromList kinds, map sometimesTracesDeclaration kinds)
  where
    kinds :: [TraceKind]
    kinds =
        [ "TraceAddBlockEvent.SwitchedToAFork"
        , "PeerStatusChanged"
        ]

processMessage :: State -> LogMessage -> (State, [Value])
processMessage (State scanningFor) LogMessage{kind}
    | Set.member kind scanningFor =
        ( State (Set.delete kind scanningFor)
        , [sometimesTracesReached kind]
        )
    | otherwise = (State scanningFor, [])

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
