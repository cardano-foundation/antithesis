{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Boilerplate to parse (some) node logs
module Cardano.Antithesis.LogMessage
  ( LogMessage (..)
  , MessageData (..)
  ) where

import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Text
import GHC.Generics (Generic)
import Data.Time    (UTCTime)

type Node = Text

-- | Top?level record for each log line
data LogMessage = LogMessage
  { at     :: UTCTime
  , ns     :: [Text]
  , datum  :: MessageData  -- renamed from 'data'
  , sev    :: Severity
  , thread :: Text
  , host   :: Node
  } deriving (Show, Generic)

instance FromJSON LogMessage where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \f -> case f of
        "datum" -> "data"
        other   -> other
    }

instance ToJSON LogMessage where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = \f -> if f == "datum" then "data" else f
    }

-- | Severity levels in your logs
data Severity = Debug | Info | Notice | Warning | SevError
  deriving (Show, Generic)

instance FromJSON Severity where
  parseJSON = withText "Severity" $ \t -> case t of
    "Debug"   -> pure Debug
    "Info"    -> pure Info
    "Notice"  -> pure Notice
    "Warning" -> pure Warning
    "Error"   -> pure SevError
    _         -> fail $ "Unknown severity: " <> show t

instance ToJSON Severity where
  toJSON = String . \case
    Debug   -> "Debug"
    Info    -> "Info"
    Notice  -> "Notice"
    Warning -> "Warning"
    SevError   -> "Error"

data MessageData
  = TraceNodeNotLeader
      { slot :: Word }
  | TraceStartLeadershipCheck
      { chainDensity :: Double
      , delegMapSize :: Int
      , slot         :: Word
      , utxoSize     :: Int
      }
  | KESInfo
      { credentials :: Text
      , endPeriod   :: Int
      , evolution    :: Int
      , startPeriod :: Int
      }
  | SwitchedToAFork
      { newTipSelectView :: ChainSelectView
      , newtip           :: Text
      , oldTipSelectView :: ChainSelectView
      }
  deriving (Show)

instance FromJSON MessageData where
  parseJSON = withObject "MessageData" $ \o -> do
    kind <- o .: "kind" :: Parser Text
    case kind of
      "TraceNodeNotLeader" ->
        TraceNodeNotLeader
          <$> o .: "slot"

      "TraceStartLeadershipCheck" ->
        TraceStartLeadershipCheck
          <$> o .: "chainDensity"
          <*> o .: "delegMapSize"
          <*> o .: "slot"
          <*> o .: "utxoSize"

      "KESInfo" ->
        KESInfo
          <$> o .: "credentials"
          <*> o .: "endPeriod"
          <*> o .: "evolution"
          <*> o .: "startPeriod"

      "TraceAddBlockEvent.SwitchedToAFork" ->
        SwitchedToAFork
          <$> o .: "newTipSelectView"
          <*> o .: "newtip"
          <*> o .: "oldTipSelectView"

      other ->
        fail $ "Unknown MessageData kind: " ++ show other

instance ToJSON MessageData where
  toJSON = \case
    TraceNodeNotLeader sl ->
      object
        [ "kind" .= String "TraceNodeNotLeader"
        , "slot" .= sl
        ]

    TraceStartLeadershipCheck cd dm sl utxo ->
      object
        [ "kind"         .= String "TraceStartLeadershipCheck"
        , "chainDensity" .= cd
        , "delegMapSize" .= dm
        , "slot"         .= sl
        , "utxoSize"     .= utxo
        ]

    KESInfo creds end evo startP ->
      object
        [ "kind"        .= String "KESInfo"
        , "credentials" .= creds
        , "endPeriod"   .= end
        , "evolution"   .= evo
        , "startPeriod" .= startP
        ]

    SwitchedToAFork newV newTip oldV ->
      object
        [ "kind"              .= String "TraceAddBlockEvent.SwitchedToAFork"
        , "newTipSelectView"  .= newV
        , "newtip"            .= newTip
        , "oldTipSelectView"  .= oldV
        ]

-- | The nested view object in the SwitchedToAFork event
data ChainSelectView
  = PraosChainSelectView
      { chainLength :: Int
      , issueNo     :: Int
      , issuerHash  :: Text
      , slotNo      :: Int
      , tieBreakVRF :: Text
      }
  deriving (Show)

instance FromJSON ChainSelectView where
  parseJSON = withObject "ChainSelectView" $ \o -> do
    kind <- o .: "kind"
    case (kind :: Text) of
      "PraosChainSelectView" ->
        PraosChainSelectView
          <$> o .: "chainLength"
          <*> o .: "issueNo"
          <*> o .: "issuerHash"
          <*> o .: "slotNo"
          <*> o .: "tieBreakVRF"
      other ->
        fail $ "Unknown ChainSelectView kind: " ++ show other

instance ToJSON ChainSelectView where
  toJSON (PraosChainSelectView cl inum ih sn vrf) =
    object
      [ "kind"         .= String "PraosChainSelectView"
      , "chainLength"  .= cl
      , "issueNo"      .= inum
      , "issuerHash"   .= ih
      , "slotNo"       .= sn
      , "tieBreakVRF"  .= vrf
      ]
