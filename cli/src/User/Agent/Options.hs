{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DerivingStrategies #-}

module User.Agent.Options
    ( agentCommandParser
    , testRunIdOption
    ) where

import Core.Options
    ( downloadAssetsDirectoryOption
    , platformOption
    , repositoryOption
    , tokenIdOption
    , walletOption
    )
import Core.Types.Basic (Duration (..))
import Core.Types.Tx (WithTxHash)
import Lib.Box (Box (..))
import OptEnvConf
    ( Alternative (..)
    , Parser
    , auto
    , command
    , commands
    , eitherReader
    , help
    , long
    , metavar
    , option
    , reader
    , setting
    , short
    , str
    )
import Oracle.Validate.DownloadAssets (DownloadAssetsFailure)
import Oracle.Validate.Requests.ManageWhiteList
    ( UpdateWhiteListFailure
    )
import Oracle.Validate.Requests.TestRun.Update (UpdateTestRunFailure)
import Oracle.Validate.Types (AValidationResult)
import User.Agent.Cli
    ( AgentCommand (..)
    , IsReady (NotReady)
    , TestRunId (..)
    )
import User.Agent.PushTest (PushFailure)
import User.Agent.Types (TestRunMap)
import User.Types
    ( Phase (..)
    , TestRunRejection (..)
    , TestRunState
    , URL (..)
    )

agentCommandParser
    :: Parser (Box (AgentCommand NotReady))
agentCommandParser =
    commands
        [ command "accept-test" "Request a test on a specific platform"
            $ Box <$> acceptTestOptions
        , command "reject-test" "Reject a test with a reason"
            $ Box <$> rejectTestOptions
        , command "report-test" "Report the result of a test run"
            $ Box <$> reportTestOptions
        , command "query" "Query the status of test runs"
            $ Box <$> queryOptions
        , command "white-list" "Whitelist a repository for test-runs"
            $ Box <$> whitelistRepositoryOptions
        , command "black-list" "Blacklist a repository for test-runs"
            $ Box <$> blacklistRepositoryOptions
        , command "download-assets" "Download test run assets"
            $ Box <$> downloadAssetsOptions
        , command "push-test" "Push a test run to Antithesis"
            $ Box <$> pushTestOptions
        ]

pushTestOptions
    :: Parser
        ( AgentCommand
            NotReady
            (AValidationResult PushFailure ())
        )
pushTestOptions =
    PushTest
        <$> tokenIdOption
        <*> _
        <*> _
        <*> walletOption
        <*> downloadAssetsDirectoryOption
        <*> testRunIdOption "push assets from"

downloadAssetsOptions
    :: Parser
        ( AgentCommand
            NotReady
            ( AValidationResult
                DownloadAssetsFailure
                ()
            )
        )
downloadAssetsOptions =
    DownloadAssets
        <$> tokenIdOption
        <*> testRunIdOption "download assets from"
        <*> downloadAssetsDirectoryOption

whitelistRepositoryOptions
    :: Parser
        ( AgentCommand
            phase
            ( AValidationResult
                UpdateWhiteListFailure
                (WithTxHash ())
            )
        )
whitelistRepositoryOptions =
    WhiteList
        <$> tokenIdOption
        <*> walletOption
        <*> platformOption
        <*> repositoryOption

blacklistRepositoryOptions
    :: Parser
        ( AgentCommand
            phase
            ( AValidationResult
                UpdateWhiteListFailure
                (WithTxHash ())
            )
        )
blacklistRepositoryOptions =
    BlackList
        <$> tokenIdOption
        <*> walletOption
        <*> platformOption
        <*> repositoryOption

queryOptions
    :: Parser (AgentCommand NotReady TestRunMap)
queryOptions = Query <$> tokenIdOption

testRunIdOption
    :: String -> Parser TestRunId
testRunIdOption what =
    TestRunId
        <$> setting
            [ long "test-run-id"
            , short 'i'
            , metavar "TEST_RUN_ID"
            , help $ "An ID of a test-run to " ++ what
            , option
            , reader str
            ]

acceptTestOptions
    :: Parser
        ( AgentCommand
            NotReady
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState RunningT))
            )
        )
acceptTestOptions =
    Accept
        <$> tokenIdOption
        <*> walletOption
        <*> testRunIdOption "accept"
        <*> pure ()

testRejectionParser :: Parser TestRunRejection
testRejectionParser =
    setting
        [ long "reason"
        , help "Reason for rejecting the test run"
        , metavar "REJECTION_REASON"
        , reader (eitherReader readReason)
        , option
        , reader (eitherReader readReason)
        ]
  where
    readReason :: String -> Either String TestRunRejection
    readReason "broken-instructions" = Right BrokenInstructions
    readReason "unclear-intent" = Right UnclearIntent
    readReason _ = Left "Unknown reason for rejection"

rejectTestOptions
    :: Parser
        ( AgentCommand
            NotReady
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState DoneT))
            )
        )
rejectTestOptions = do
    testRunId <- testRunIdOption "reject"
    reason <- many testRejectionParser
    tokenId <- tokenIdOption
    wallet <- walletOption
    pure $ Reject tokenId wallet testRunId () reason

reportTestOptions
    :: Parser
        ( AgentCommand
            NotReady
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState DoneT))
            )
        )
reportTestOptions = do
    tokenId <- tokenIdOption
    testRunId <- testRunIdOption "report"
    wallet <- walletOption
    duration <-
        Duration
            <$> setting
                [ long "duration"
                , help "Duration of the test run in hours"
                , metavar "DURATION_HOURS"
                , reader auto
                , option
                ]
    url <-
        URL
            <$> setting
                [ long "url"
                , help "URL of the test report"
                , metavar "REPORT_URL"
                , reader str
                , option
                ]
    pure $ Report tokenId wallet testRunId () duration url
