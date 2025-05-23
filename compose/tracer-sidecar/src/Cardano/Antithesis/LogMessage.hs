{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Boilerplate to parse (some) node logs
module Cardano.Antithesis.LogMessage
  ( LogMessage (..)
  ) where

import qualified Data.Aeson.KeyMap as KeyMap

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

data LogMessage = LogMessage
  { at     :: UTCTime
  , ns     :: [Text]
  , details  :: Value -- renamed from 'data'
  , sev    :: Severity
  , thread :: Text
  , host   :: Node
  , kind   :: Text
  } deriving (Show, Generic)

instance FromJSON LogMessage where
  parseJSON = withObject "LogMessage" $ \o -> do
    at      <- o .:  "at"
    ns      <- o .:? "ns" .!= []
    details <- o .:  "data"
    sev     <- o .:  "sev"
    thread  <- o .:  "thread"
    host    <- o .:  "host"

    kind <- case details of
      Object hm -> case KeyMap.lookup "kind" hm of
                     Just v  -> parseJSON v
                     Nothing -> pure "" -- for simplicity
      _ -> fail "\"data\" was not a JSON object"

    return LogMessage
      { at      = at
      , ns      = ns
      , details = details
      , sev     = sev
      , thread  = thread
      , host    = host
      , kind    = kind
      }

-- | Severity levels in your logs
data Severity = Debug | Info | Notice | Warning | SevError | Critical
  deriving (Show, Generic)

instance FromJSON Severity where
  parseJSON = withText "Severity" $ \t -> case t of
    "Debug"    -> pure Debug
    "Info"     -> pure Info
    "Notice"   -> pure Notice
    "Warning"  -> pure Warning
    "Error"    -> pure SevError
    "Critical" -> pure Critical
    _         -> fail $ "Unknown severity: " <> show t
