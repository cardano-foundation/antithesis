{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE NoFieldSelectors #-}

-- | Boilerplate to parse (some) node logs
module Cardano.Antithesis.LogMessage
    ( LogMessage (..)
    , LogMessageData (..)
    , NewTipSelectView (..)
    , Severity (..)
    , mkAmaruLogMessage
    ) where

import qualified Data.Aeson.KeyMap as KeyMap

import Data.Aeson
    ( FromJSON (..)
    , Value (..)
    , object
    , withObject
    , withText
    , (.:)
    , (.:?)
    , (.=)
    )
import Data.Maybe
    ( fromMaybe
    )
import Data.Text
    ( Text
    )
import qualified Data.Text as T
import Data.Time
    ( UTCTime
    )
import GHC.Generics
    ( Generic
    )

type Node = Text

-- details ---------------------------------------------------------------------

-- | The inner payload of a log message, dispatched on the
--   @"kind"@ field in the JSON.
data LogMessageData
    = AddedToCurrentChain
        { newTipSelectView :: NewTipSelectView
        , newtip :: Text
        }
    | -- | A node has switched to a different chain branch. Both
      -- the old and new tips are reported. Used by the
      -- ForkTree consumer to track per-host current-tip
      -- transitions that bypass sequential extension.
      SwitchedToAFork
        { newTipSelectView :: NewTipSelectView
        , newtip :: Text
        , oldTipSelectView :: NewTipSelectView
        }
    | OtherLogMessageData
        { originalObject :: Value
        }
    | ServerError
        { reason :: Text
        }
    | -- | A plain line ingested from an Amaru relay's container
      -- stdout.  Carries the normalized evidence fields from
      -- @contracts/amaru-log-event.md@.
      AmaruStdout
        { amaruSource :: Text
        , amaruMessage :: Text
        }
    deriving (Show, Generic, Eq)

-- | Details of the new tip selection view.
--
-- Cardano-node has shipped two encodings of this object:
--
-- * Older nodes emit @"kind": "PraosChainSelectView"@ with a
--   @"chainLength"@ field.
-- * Newer nodes emit @"kind": "PraosTiebreakerView"@ with a
--   @"blockNo"@ field.
--
-- Both refer to the same value (the tip's chain length /
-- block number), so we accept either field name.  A
-- mixed-version cluster (master testnet pins three different
-- node images today) emits both forms; failing to accept the
-- newer form silently drops every event from those hosts.
data NewTipSelectView = NewTipSelectView
    { chainLength :: Int
    , issueNo :: Int
    , issuerHash :: Text
    , kind :: Text
    , slotNo :: Int
    , tieBreakVRF :: Text
    }
    deriving (Show, Generic, Eq)

instance FromJSON NewTipSelectView where
    parseJSON = withObject "NewTipSelectView" $ \o -> do
        chainLength <-
            o .:? "chainLength" >>= \case
                Just n -> pure n
                Nothing -> o .: "blockNo"
        issueNo <- o .: "issueNo"
        issuerHash <- o .: "issuerHash"
        kind <- o .: "kind"
        slotNo <- o .: "slotNo"
        tieBreakVRF <- o .: "tieBreakVRF"
        pure
            NewTipSelectView
                { chainLength
                , issueNo
                , issuerHash
                , kind
                , slotNo
                , tieBreakVRF
                }

instance FromJSON LogMessageData where
    parseJSON = withObject "LogMessageData" $ \o -> do
        (kind :: Maybe Text) <- o .:? "kind"

        case kind of
            Just "AddedToCurrentChain" ->
                AddedToCurrentChain
                    <$> parseEitherField o "newTipSelectView" "newSuffixSelectView"
                    <*> o .: "newtip"
            Just "TraceAddBlockEvent.SwitchedToAFork" ->
                SwitchedToAFork
                    <$> parseEitherField o "newTipSelectView" "newSuffixSelectView"
                    <*> o .: "newtip"
                    <*> parseEitherField o "oldTipSelectView" "oldSuffixSelectView"
            Just "ServerError" ->
                ServerError
                    <$> o .: "reason"
            -- Fallback: capture the raw object for unknown tags
            _ ->
                pure $ OtherLogMessageData $ Object o
      where
        -- Cardano-node 10.7+ renamed @newTipSelectView@ to
        -- @newSuffixSelectView@ (and @oldTipSelectView@ to
        -- @oldSuffixSelectView@) to match chain-selection
        -- semantics.  master testnet pins three node images
        -- spanning both naming schemes; accept either.
        parseEitherField o oldName newName =
            o .:? oldName >>= \case
                Just v -> pure v
                Nothing -> o .: newName

-- LogMessage ------------------------------------------------------------------

data LogMessage = LogMessage
    { at :: UTCTime
    , ns :: Text
    , details :: LogMessageData -- renamed from 'data'
    , sev :: Severity
    , thread :: Text
    , host :: Node
    , kind :: Text
    , json :: Value
    }
    deriving (Show, Generic)

instance FromJSON LogMessage where
    parseJSON = withObject "LogMessage" $ \o -> do
        at <- o .: "at"
        ns <- o .: "ns"
        details <- o .: "data"
        sev <- o .: "sev"
        thread <- o .: "thread"
        host <- o .: "host"

        detailsJson <- o .: "data"
        kind <- case detailsJson of
            Object hm -> case KeyMap.lookup "kind" hm of
                Just v -> parseJSON v
                Nothing -> pure "" -- for simplicity
            _ -> fail "\"data\" was not a JSON object"

        return
            LogMessage
                { at = at
                , ns = ns
                , details = details
                , sev = sev
                , thread = thread
                , host = host
                , kind = kind
                , json = Object o
                }

-- | Severity levels in your logs
data Severity = Debug | Info | Notice | Warning | SevError | Critical
    deriving (Show, Generic, Eq, Ord)

instance FromJSON Severity where
    parseJSON = withText "Severity" $ \t -> case t of
        "Debug" -> pure Debug
        "Info" -> pure Info
        "Notice" -> pure Notice
        "Warning" -> pure Warning
        "Error" -> pure SevError
        "Critical" -> pure Critical
        _ -> fail $ "Unknown severity: " <> show t

-- Amaru stdout adapter --------------------------------------------------------

-- | Normalize an ingested Amaru relay line into the event
-- pipeline.  The relay filename loses its @.log@ suffix to
-- become the host identity; the trailing newline (if present)
-- is stripped from the message.  Severity is 'Info' so the
-- line cannot trip the existing critical-node-log rule.
mkAmaruLogMessage
    :: UTCTime
    -- ^ ingestion time
    -> Text
    -- ^ relay filename, e.g. @"amaru-relay-1.log"@
    -> Text
    -- ^ complete raw line
    -> LogMessage
mkAmaruLogMessage ingestionTime relayFilename rawLine =
    LogMessage
        { at = ingestionTime
        , ns = "amaru"
        , details =
            AmaruStdout
                { amaruSource = source
                , amaruMessage = line
                }
        , sev = Info
        , thread = "amaru-stdout"
        , host = relayHost
        , kind = "AmaruStdout"
        , json = evidence
        }
  where
    source = "amaru-container-stdout" :: Text
    relayHost =
        fromMaybe relayFilename
            $ T.stripSuffix ".log" relayFilename
    line =
        fromMaybe rawLine
            $ T.stripSuffix "\n" rawLine
    evidence =
        object
            [ "source" .= source
            , "host" .= relayHost
            , "message" .= line
            ]
