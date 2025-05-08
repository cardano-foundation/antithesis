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
    -- | N.B. Currently actually checking the last element of the `ns` field,
    -- not the `data.kind` field.
    kinds :: [TraceKind]
    kinds =
        [ "SwitchedToAFork"
        , "PromotedToWarmRemote"
        , "PromotedToHotRemote"
        , "DemotedToColdRemote"
        , "DemotedToWarmRemote"
        ]

processMessage :: State -> LogMessage -> (State, [Value])
processMessage (State scanningFor) LogMessage{ns}
    | Set.member kind scanningFor =
        ( State (Set.delete kind scanningFor)
        , [sometimesTracesReached kind]
        )
    | otherwise = (State scanningFor, [])
  where
    kind = L.last ns

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
