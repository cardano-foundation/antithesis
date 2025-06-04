{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns        #-}
{-# LANGUAGE OverloadedStrings     #-}

module Cardano.Antithesis.Sidecar where

import qualified Data.Text                     as T

import           Cardano.Antithesis.LogMessage
import           Cardano.Antithesis.Sdk

import           Control.Arrow                 (second)
import           Control.Monad                 (forM_)
import           Data.Aeson                    (Value)
import           Data.List                     (mapAccumL)
import qualified Data.List                     as L
import           Data.Maybe                    (fromJust)
import           Data.Set                      (Set)
import qualified Data.Set                      as Set
import           Data.Text                     (Text)

-- State -----------------------------------------------------------------------

type TraceKind = Text

-- TODO: Could probably be written in some nice way like
-- data Seen a = Seen a | Unseen a
-- seen :: Foldable f => f (Seen a) -> a
-- unseen :: Foldable f => f (Seen a) -> a
-- found ::
--
-- kinds :: [Seen TraceKind]
-- nodes :: [Seen HostName]
data State = State
  { scanningFor      :: Set TraceKind
  , scanningForNodes :: Set Text
  }

initialState :: (State, [Value])
initialState =
  (State (Set.fromList kinds) (Set.fromList nodes)
  , map sometimesTracesDeclaration kinds ++ map (sometimesTracesDeclaration . anyMessageFromNode) nodes)
  where
    kinds :: [TraceKind]
    kinds =
        [ "TraceAddBlockEvent.SwitchedToAFork"
        , "PeerStatusChanged"
        ]

    nodes = map (\i -> T.pack $ "p" <> show i <> ".example") [1 :: Int .. 3]

anyMessageFromNode :: Text -> Text
anyMessageFromNode node = "Any " <> fromJust (T.stripSuffix ".example" node) <> " log"

processMessage :: State -> LogMessage -> (State, [Value])
processMessage s m =
    let
        (s', o) = processKind s m  -- FIXME use monad
        (s'', o') = processHost s' m
    in (s'', o <> o')
  where
    processKind :: State -> LogMessage -> (State, [Value])
    processKind (State scanningFor nodes) LogMessage{kind}
        | Set.member kind scanningFor =
            ( State (Set.delete kind scanningFor) nodes
            , [sometimesTracesReached kind]
            )
        | otherwise = (State scanningFor nodes, [])

    processHost :: State -> LogMessage -> (State, [Value])
    processHost (State scanningFor nodes) LogMessage{host}
        | Set.member host nodes =
            ( State scanningFor (Set.delete host nodes)
            , [sometimesTracesReached $ anyMessageFromNode host]
            )
        | otherwise = (State scanningFor nodes, [])

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
