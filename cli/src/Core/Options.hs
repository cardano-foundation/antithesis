{-# LANGUAGE DerivingStrategies #-}

module Core.Options
    ( platformOption
    , repositoryOption
    , commitOption
    , directoryOption
    , usernameOption
    , pubkeyhashOption
    , outputReferenceParser
    , durationOption
    , tryOption
    )
where

import Core.Types.Basic
    ( Commit (..)
    , Directory (..)
    , Duration (..)
    , Platform (..)
    , PublicKeyHash (..)
    , Repository (..)
    , RequestRefId (..)
    , Try (..)
    , Username (..)
    )
import Data.Text qualified as T
import Options.Applicative
    ( Parser
    , ReadM
    , auto
    , help
    , long
    , maybeReader
    , metavar
    , option
    , short
    , strOption
    , value
    )
import Options.Applicative.Types (readerAsk)

platformOption :: Parser Platform
platformOption =
    Platform
        <$> strOption
            ( long "platform"
                <> short 'p'
                <> metavar "PLATFORM"
                <> help "The platform to use"
            )

parseRepository :: String -> Maybe Repository
parseRepository repoStr = case break (== '/') repoStr of
    (org, '/' : proj) -> Just $ Repository org proj
    _ -> Nothing

repositoryOption :: Parser Repository
repositoryOption =
    option
        (maybeReader parseRepository)
        ( long "repository"
            <> short 'r'
            <> metavar "ORGANIZATION/PROJECT"
            <> help "The repository in the format 'organization/project'"
        )

commitOption :: Parser Commit
commitOption =
    Commit
        <$> strOption
            ( long "commit"
                <> short 'c'
                <> metavar "COMMIT"
                <> help "The commit hash or reference"
            )

directoryOption :: Parser Directory
directoryOption =
    Directory
        <$> strOption
            ( long "directory"
                <> short 'd'
                <> metavar "DIRECTORY"
                <> value "."
                <> help "The directory to run in (defaults to \".\")"
            )

usernameOption :: Parser Username
usernameOption =
    Username
        <$> strOption
            ( long "username"
                <> short 'u'
                <> metavar "USERNAME"
                <> help "The username to register"
            )

pubkeyhashOption :: Parser PublicKeyHash
pubkeyhashOption =
    PublicKeyHash
        <$> strOption
            ( long "pubkeyhash"
                <> short 'k'
                <> metavar "PUBKEYHASH"
                <> help "The public key hash for the user"
            )

outputReferenceParser :: Parser RequestRefId
outputReferenceParser =
    option parseOutputReference
        $ short 'o'
            <> long "outref"
            <> metavar "OUTPUT_REF"
            <> help "The transaction hash and index for the output reference"

parseOutputReference :: ReadM RequestRefId
parseOutputReference = do
    s <- readerAsk
    case break (== '-') s of
        (_txHash, '-' : indexStr) -> do
            _index :: Int <- case reads indexStr of
                [(i, "")] -> pure i
                _ ->
                    fail
                        "Invalid index format. Use 'txHash-index' where index is an integer."
            pure
                $ RequestRefId
                $ T.pack s
        _ -> fail "Invalid output reference format. Use 'txHash-index'"

durationOption :: Parser Duration
durationOption =
    Duration
        <$> option
            auto
            ( long "duration"
                <> short 't'
                <> metavar "DURATION"
                <> help "The duration in hours for the test-run"
            )

tryOption :: Parser Try
tryOption =
    Try
        <$> option
            auto
            ( long "try"
                <> short 'y'
                <> metavar "TRY"
                <> help "The current attempt number for this commit"
            )
