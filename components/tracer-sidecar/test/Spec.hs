{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Spec (spec)
where

import App (tailAmaruLogDir, tailJsonLinesFromTracerLogDir)
import Cardano.Antithesis.LogMessage
    ( LogMessage (..)
    , LogMessageData (..)
    , NewTipSelectView (..)
    , Severity (..)
    , mkAmaruLogMessage
    )
import Cardano.Antithesis.Sidecar
    ( Output (..)
    , initialState
    , mkSpec
    , processMessages
    )
import Control.Concurrent
    ( MVar
    , modifyMVar_
    , newMVar
    , readMVar
    , threadDelay
    )
import Control.Concurrent.Async (async, cancel)
import Data.Aeson
    ( ToJSON (toJSON)
    , Value
    , decodeStrict'
    , eitherDecodeStrict
    , encode
    , object
    , (.=)
    )
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Either
    ( partitionEithers
    )
import Data.Foldable (forM_)
import Data.List
    ( sort
    )
import Data.Maybe
    ( mapMaybe
    )
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time
import ForkTreeSpec qualified
import System.FilePath ((</>))
import System.IO.Temp
    ( withSystemTempDirectory
    )
import System.Process (system)
import Test.Hspec
import Test.Hspec.Golden
    ( Golden (..)
    )

spec :: Spec
spec = do
    ForkTreeSpec.spec
    (input :: [B8.ByteString]) <-
        runIO $ B8.lines <$> B8.readFile "test/data/input.jsonl"
    let runSynthetic propSpec msgs =
            snd $ processMessages propSpec (initialState propSpec) msgs

    describe "amaru consumer convergence property" $ do
        it "hits when the consumer advances to a producer tip" $ do
            let outputs =
                    sdkAssertions
                        $ runSynthetic
                            (mkSpec 1 (Just "amaru-consumer.example") False)
                            [ addedToCurrentChain "amaru-consumer.example" 10 "seed"
                            , addedToCurrentChain "p1.example" 11 "producer-tip"
                            , addedToCurrentChain "amaru-consumer.example" 11 "producer-tip"
                            ]
            outputs `shouldSatisfy` any (assertionHit convergencePropertyName)

        it "hits when the consumer advances to an Amaru producer tip" $ do
            let outputs =
                    sdkAssertions
                        $ runSynthetic
                            (mkSpec 1 (Just "amaru-consumer.example") False)
                            [ addedToCurrentChain "amaru-consumer.example" 10 "seed"
                            , addedToCurrentChain "amaru-relay-1.example" 11 "producer-tip"
                            , addedToCurrentChain "amaru-consumer.example" 11 "producer-tip"
                            ]
            outputs `shouldSatisfy` any (assertionHit convergencePropertyName)

        it "is declared but not hit when the consumer stays at its first tip" $ do
            let outputs =
                    sdkAssertions
                        $ runSynthetic
                            (mkSpec 1 (Just "amaru-consumer.example") False)
                            [ addedToCurrentChain "amaru-consumer.example" 10 "seed"
                            , addedToCurrentChain "p1.example" 11 "producer-tip"
                            , addedToCurrentChain "amaru-consumer.example" 10 "seed"
                            ]
            outputs
                `shouldSatisfy` any (assertionDeclared convergencePropertyName)
            outputs `shouldNotSatisfy` any (assertionHit convergencePropertyName)

        it "is not declared when no consumer is configured" $ do
            let outputs =
                    sdkAssertions
                        $ runSynthetic
                            (mkSpec 1 Nothing False)
                            [ addedToCurrentChain "p1.example" 11 "producer-tip"
                            ]
            outputs
                `shouldNotSatisfy` any (assertionDeclared convergencePropertyName)

    describe "amaru stdout scored properties" $ do
        it "P1: Consensus died fails the fatal invariant with full evidence" $ do
            let line = "ERROR amaru::cmd::node::run: Consensus died, restarting"
                outputs = runAmaru [amaruEvent "amaru-relay-1" line]
                failures = filter (assertionFailed "no fatal amaru consensus logs") outputs
            failures `shouldSatisfy` (not . null)
            case failures of
                (f : _) ->
                    assertionField "details" f
                        `shouldBe` Just
                            ( object
                                [ "source" .= ("amaru-container-stdout" :: Text)
                                , "host" .= ("amaru-relay-1" :: Text)
                                , "message" .= line
                                ]
                            )
                [] -> expectationFailure "no invariant failure emitted"

        it
            "P2: attempted roll back in the future fails on relay-2 with evidence"
            $ do
                let line = "WARN attempted roll back in the future by 3 slots"
                    outputs = runAmaru [amaruEvent "amaru-relay-2" line]
                    failures = filter (assertionFailed "no fatal amaru consensus logs") outputs
                failures `shouldSatisfy` (not . null)
                case failures of
                    (f : _) ->
                        assertionField "details" f
                            `shouldBe` Just
                                ( object
                                    [ "source" .= ("amaru-container-stdout" :: Text)
                                    , "host" .= ("amaru-relay-2" :: Text)
                                    , "message" .= line
                                    ]
                                )
                    [] -> expectationFailure "no invariant failure emitted"

        it "P3: case-sensitive variant casings do not fail the invariant" $ do
            let outputs =
                    runAmaru
                        [ amaruEvent "amaru-relay-1" "consensus died"
                        , amaruEvent "amaru-relay-1" "CONSENSUS DIED"
                        , amaruEvent "amaru-relay-1" "Attempted Roll Back In The Future"
                        ]
            outputs
                `shouldNotSatisfy` any
                    (assertionFailed "no fatal amaru consensus logs")

        it "P3b: near-miss words do not fail the invariant" $ do
            let outputs =
                    runAmaru
                        [ amaruEvent "amaru-relay-1" "consensus layer started"
                        , amaruEvent "amaru-relay-1" "rollback not needed"
                        ]
            outputs
                `shouldNotSatisfy` any
                    (assertionFailed "no fatal amaru consensus logs")

        it
            "P4: ordinary line hits liveness; invariant declared but not failed"
            $ do
                let outputs =
                        runAmaru [amaruEvent "amaru-relay-1" "INFO starting amaru node"]
                outputs `shouldSatisfy` any (assertionHit "amaru stdout observed")
                outputs
                    `shouldSatisfy` any
                        (assertionDeclared "no fatal amaru consensus logs")
                outputs
                    `shouldNotSatisfy` any
                        (assertionFailed "no fatal amaru consensus logs")

        it "P5: enabled mode declares both properties" $ do
            let outputs =
                    runAmaru [amaruEvent "amaru-relay-1" "INFO startup"]
            outputs
                `shouldSatisfy` any
                    (assertionDeclared "amaru stdout observed")
            outputs
                `shouldSatisfy` any
                    (assertionDeclared "no fatal amaru consensus logs")

        it "P6: disabled mode declares neither property" $ do
            let outputs =
                    sdkAssertions
                        $ runSynthetic
                            (mkSpec 1 Nothing False)
                            [addedToCurrentChain "p1.example" 11 "tip"]
            outputs
                `shouldNotSatisfy` any
                    (assertionDeclared "amaru stdout observed")
            outputs
                `shouldNotSatisfy` any
                    (assertionDeclared "no fatal amaru consensus logs")

        it "P7: two fatal lines emit exactly one invariant failure" $ do
            let outputs =
                    runAmaru
                        [ amaruEvent "amaru-relay-1" "Consensus died"
                        , amaruEvent "amaru-relay-2" "Consensus died again"
                        ]
                failures =
                    filter (assertionFailed "no fatal amaru consensus logs") outputs
            length failures `shouldBe` 1

        it "P8: amaru fatal line does not pollute existing properties" $ do
            let outputs =
                    runAmaru
                        [ amaruEvent
                            "amaru-relay-1"
                            "ERROR Consensus died"
                        ]
            outputs
                `shouldNotSatisfy` any
                    (assertionFailed "no critical logs")
            outputs
                `shouldNotSatisfy` any
                    (assertionFailed "cluster fork depth < k")

    describe "amaru stdout adapter" $ do
        it
            "P10: adapter normalizes filename to host, strips newline, sets source"
            $ do
                let msg =
                        mkAmaruLogMessage
                            (UTCTime (fromGregorian 2026 7 28) 0)
                            "amaru-relay-1.log"
                            "INFO starting\n"
                case msg of
                    LogMessage{host = h, details = AmaruStdout{amaruSource, amaruMessage}} -> do
                        h `shouldBe` "amaru-relay-1"
                        amaruSource `shouldBe` "amaru-container-stdout"
                        amaruMessage `shouldBe` "INFO starting"
                    _ -> expectationFailure "expected AmaruStdout details"

        it "P11: adapter severity does not manufacture a critical-log finding" $ do
            let msg =
                    mkAmaruLogMessage
                        (UTCTime (fromGregorian 2026 7 28) 0)
                        "amaru-relay-1.log"
                        "ERROR something bad\n"
                amaruSpec = mkSpec 1 Nothing True
                outputs =
                    sdkAssertions
                        $ snd
                        $ processMessages
                            amaruSpec
                            (initialState amaruSpec)
                            [msg]
            outputs
                `shouldNotSatisfy` any
                    (assertionFailed "no critical logs")

    describe "amaru stdout file ingestion" $ do
        it
            "P12: file created after watcher startup is discovered and normalized"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir dir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 500000
                writeFile (dir </> "amaru-relay-1.log") "INFO starting amaru\n"
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                case msgs of
                    [LogMessage{host = h, details = AmaruStdout{amaruMessage}}] -> do
                        amaruMessage `shouldBe` "INFO starting amaru"
                        h `shouldBe` "amaru-relay-1"
                    _ ->
                        expectationFailure
                            $ "expected exactly one AmaruStdout message, got "
                                <> show (length msgs)

        it "P13: line appended to already-followed file is ingested"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                let fp = dir </> "amaru-relay-1.log"
                writeFile fp "INFO first line\n"
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir dir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 1500000
                _ <- system $ "echo 'INFO second line' >> " <> fp
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                let lines_ =
                        [ line
                        | LogMessage{details = AmaruStdout{amaruMessage = line}} <-
                            msgs
                        ]
                lines_ `shouldBe` ["INFO first line", "INFO second line"]

        it "P14: pre-existing file is ingested from the beginning"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                writeFile (dir </> "amaru-relay-1.log") "INFO already here\n"
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir dir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                length msgs `shouldBe` 1

        it "P15: both relay identities accepted with distinct hosts"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                writeFile (dir </> "amaru-relay-1.log") "INFO relay one\n"
                writeFile (dir </> "amaru-relay-2.log") "INFO relay two\n"
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir dir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                let hosts = sort [h | LogMessage{host = h} <- msgs]
                hosts `shouldBe` ["amaru-relay-1", "amaru-relay-2"]

        it "P17: missing directory does not terminate the watcher"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                let watchDir = dir </> "not-yet-created"
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir watchDir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 1500000
                _ <- system $ "mkdir -p " <> watchDir
                writeFile
                    (watchDir </> "amaru-relay-1.log")
                    "INFO recovered\n"
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                length msgs `shouldBe` 1

        it "P16: non-relay files are ignored"
            $ withSystemTempDirectory "amaru-logs"
            $ \dir -> do
                writeFile (dir </> "other.log") "INFO not a relay\n"
                writeFile (dir </> "amaru-relay-3.log") "INFO wrong relay\n"
                r <- newMVar []
                thread <-
                    async
                        $ tailAmaruLogDir dir
                        $ \msg -> modifyMVar_ r $ \msgs -> pure (msgs <> [msg])
                threadDelay 1500000
                cancel thread
                msgs <- readMVar r
                length msgs `shouldBe` 0

    it "processMessages"
        $ let
            propSpec = mkSpec 3 Nothing False
            (_finalState, actualVals) = processMessages propSpec (initialState propSpec) msgs
            msgs = mapMaybe decodeStrict' input
          in
            myGoldenTest (map jsonifyOutput actualVals)

    it "all test data messages can be decoded" $ do
        let (errs, _res) = partitionEithers $ map (eitherDecodeStrict @LogMessage) input
        case errs of
            ["Unexpected end-of-input, expecting record key literal or }"] -> pure ()
            [] -> pure ()
            _ ->
                expectationFailure
                    $ "Some messages couldn't be decoded: " <> show errs

    describe "tailJsonLinesFromTracerLogDir" $ do
        it "works on 10 files with 10 values"
            $ withSystemTempDirectory "tracer-log-dir"
            $ \dir -> do
                r <- newMVar []
                thread <-
                    async
                        $ tailJsonLinesFromTracerLogDir False dir
                        $ collectAllInts r
                let nFiles = 10
                let nValues = 130
                threadDelay 500000
                simulateRestartingNodeTracer nFiles nValues dir
                threadDelay 500000
                cancel thread
                vals <- readMVar r
                sort vals `shouldBe` sort (concat $ replicate nFiles [1 .. nValues])

collectAllInts :: MVar [Int] -> Int -> IO ()
collectAllInts xs newInt = do
    modifyMVar_ xs $ \ints -> pure (ints <> [newInt])

convergencePropertyName :: Text
convergencePropertyName = "amaru-served consumer reached producer tip"

sdkAssertions :: [Output] -> [Value]
sdkAssertions = mapMaybe $ \case
    AntithesisSdk v -> Just v
    _ -> Nothing

assertionDeclared :: Text -> Value -> Bool
assertionDeclared = assertionIdIs

assertionHit :: Text -> Value -> Bool
assertionHit name v =
    assertionIdIs name v && assertionBool "hit" v == Just True

assertionFailed :: Text -> Value -> Bool
assertionFailed name v =
    assertionIdIs name v
        && assertionBool "hit" v == Just True
        && assertionBool "condition" v == Just False

assertionIdIs :: Text -> Value -> Bool
assertionIdIs name v =
    assertionText "id" v == Just name

assertionText :: Text -> Value -> Maybe Text
assertionText field v = case assertionField field v of
    Just (Aeson.String t) -> Just t
    _ -> Nothing

assertionBool :: Text -> Value -> Maybe Bool
assertionBool field v = case assertionField field v of
    Just (Aeson.Bool b) -> Just b
    _ -> Nothing

assertionField :: Text -> Value -> Maybe Value
assertionField field (Aeson.Object outer) = do
    Aeson.Object assertion <-
        KeyMap.lookup (Key.fromString "antithesis_assert") outer
    KeyMap.lookup (Key.fromText field) assertion
assertionField _ _ = Nothing

addedToCurrentChain :: Text -> Int -> Text -> LogMessage
addedToCurrentChain host chainLength hash =
    LogMessage
        { at = UTCTime (fromGregorian 2025 11 1) 0
        , ns = "ChainDB"
        , details =
            AddedToCurrentChain
                { newTipSelectView =
                    NewTipSelectView
                        { chainLength
                        , issueNo = 0
                        , issuerHash = "issuer"
                        , kind = "PraosChainSelectView"
                        , slotNo = chainLength * 2
                        , tieBreakVRF = "vrf"
                        }
                , newtip = hash <> "@" <> T.pack (show (chainLength * 2))
                }
        , sev = Info
        , thread = "test"
        , host
        , kind = "AddedToCurrentChain"
        , json = object []
        }

jsonifyOutput :: Output -> Value
jsonifyOutput (StdOut msg) = toJSON $ "### STDOUT: " <> msg
jsonifyOutput (AntithesisSdk v) = v
jsonifyOutput (RecordChainPoint msg) = toJSON $ "### chainPoints.log: " <> msg

myGoldenTest :: [Value] -> Golden [Value]
myGoldenTest actualOutput =
    Golden
        { output = actualOutput
        , encodePretty = B8.unpack . encodeJsonl
        , writeToFile = \fp -> B8.writeFile fp . encodeJsonl
        , readFromFile = fmap (mapMaybe decodeStrict' . B8.lines) . B8.readFile
        , goldenFile = "test/data/output.jsonl"
        , actualFile = Just "test/data/output-actual.jsonl"
        , failFirstTime = False
        }
  where
    encodeJsonl = B8.intercalate "\n" . map (BL.toStrict . encode)

generateAFileWithJSONLines :: FilePath -> [Int] -> IO ()
generateAFileWithJSONLines fp xs = do
    forM_ xs $ \x -> do
        let value = BL8.unpack $ encode x
        _ <- system $ "echo " <> value <> " >> " <> fp
        threadDelay 1000

generateIncreasingUTCTimes
    :: Int -> UTCTime -> NominalDiffTime -> [UTCTime]
generateIncreasingUTCTimes n start delta =
    take n $ iterate (addUTCTime delta) start

renderFilenameWithUTCTime :: UTCTime -> FilePath
renderFilenameWithUTCTime =
    (<> ".json")
        . ("node-" <>)
        . formatTime defaultTimeLocale "%Y-%m-%dT%H-%M-%S"

-- less than 10000 files may be generated
generateFilenamesInLexicalOrder :: FilePath -> Int -> [FilePath]
generateFilenamesInLexicalOrder dir n =
    [dir </> renderFilenameWithUTCTime t | t <- times]
  where
    times =
        generateIncreasingUTCTimes
            n
            (UTCTime (fromGregorian 2025 11 1) (secondsToDiffTime 0))
            3890

generateStreamOfFiles :: [FilePath] -> (FilePath -> IO ()) -> IO ()
generateStreamOfFiles files action = do
    forM_ files $ \file -> do
        action file
        threadDelay 100000

simulateRestartingNodeTracer
    :: Int -- number of files
    -> Int -- number of values per file
    -> FilePath -- directory to write files into
    -> IO ()
simulateRestartingNodeTracer nFiles nValues dir = do
    let files = generateFilenamesInLexicalOrder dir nFiles
    generateStreamOfFiles files $ \fp -> do
        generateAFileWithJSONLines fp [1 .. nValues]

-- Amaru stdout RED-A surrogate helpers ----------------------------------------

-- | Build a normalized Amaru stdout event for testing.
amaruEvent :: Text -> Text -> LogMessage
amaruEvent relay line =
    LogMessage
        { at = UTCTime (fromGregorian 2026 7 28) 0
        , ns = "amaru"
        , details =
            AmaruStdout
                { amaruSource = "amaru-container-stdout"
                , amaruMessage = line
                }
        , sev = Info
        , thread = "test"
        , host = relay
        , kind = "AmaruStdout"
        , json = evidence
        }
  where
    evidence =
        object
            [ "source" .= ("amaru-container-stdout" :: Text)
            , "host" .= relay
            , "message" .= line
            ]

-- | Run amaru events through the enabled spec and collect SDK
-- assertions.
runAmaru :: [LogMessage] -> [Value]
runAmaru msgs =
    sdkAssertions $ snd $ processMessages spec (initialState spec) msgs
  where
    spec = mkSpec 1 Nothing True
