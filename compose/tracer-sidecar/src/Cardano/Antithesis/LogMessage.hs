{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Boilerplate to parse (some) node logs
module Cardano.Antithesis.LogMessage
  ( LogMessage (..)
  ) where

import Data.Aeson
import Data.Aeson.Types
    ( Parser
    )
import Data.Text
import Data.Time
    ( UTCTime
    )
import GHC.Generics
    ( Generic
    )

type Node = Text

-- | Top?level record for each log line
data LogMessage = LogMessage
  { at     :: UTCTime
  , ns     :: [Text]
  , details  :: Value -- renamed from 'data'
  , sev    :: Severity
  , thread :: Text
  , host   :: Node
  } deriving (Show, Generic)

instance FromJSON LogMessage where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \f -> case f of
        "details" -> "data"
        other   -> other
    }

instance ToJSON LogMessage where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = \f -> if f == "details" then "data" else f
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
