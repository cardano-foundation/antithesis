{-# LANGUAGE QuasiQuotes #-}

module User.Agent.PushTest
    ( PushFailure (..)
    , buildConfigImage
    , Registry (..)
    , pushTestToAntithesis
    , collectImagesFromAssets
    , dockerfile
    , pushTestToAntithesisIO
    , PostTestRunRequest (..)
    , Tag (..)
    , AntithesisAuth (..)
    , renderPostToAntithesis
    )
where

import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO (..))
import Core.Context
    ( WithContext
    )
import Core.Types.Basic
    ( Directory (..)
    , Duration (..)
    , TokenId
    )
import Core.Types.Fact (Fact (..))
import Core.Types.Wallet (Wallet (..))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.List (intercalate, nub, sort)
import Data.String.QQ (s)
import Lib.JSON.Canonical.Extra (object, (.=))
import Oracle.Validate.Types
    ( AValidationResult (..)
    )
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcess, readProcessWithExitCode)
import Text.JSON.Canonical
    ( ToJSON (..)
    )
import User.Agent.Lib (resolveTestRunId)
import User.Agent.Types
    ( TestRunId (..)
    )
import User.Types (Phase (..), TestRunState (..))

dockerfile :: String
dockerfile =
    [s|
FROM docker.io/debian:stable-slim AS build

# Set time zone
ENV TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && \
    echo ${TZ} > /etc/timezone

ADD docker-compose.yaml /docker-compose.yaml
ADD testnet.yaml /testnet.yaml

RUN sed -i 's/${INTERNAL_NETWORK}/false/g' /docker-compose.yaml
    |]

data PostTestRunRequest = PostTestRunRequest
    { description :: String
    , duration :: Float
    , config_image :: String
    , images :: [String]
    , recipients :: [String]
    }
    deriving (Show, Eq)

-- FIXME: Add nested object and fix keys
instance Aeson.ToJSON PostTestRunRequest where
    toJSON
        PostTestRunRequest
            { description
            , duration
            , config_image
            , images
            , recipients
            } =
            Aeson.object
                [ "params"
                    Aeson..= Aeson.object
                        [ "antithesis.description" Aeson..= description
                        , "custom.duration" Aeson..= duration
                        , "antithesis.config_image" Aeson..= config_image
                        , "antithesis.images" Aeson..= intercalate ";" images
                        , "antithesis.report.recipient"
                            Aeson..= intercalate ";" recipients
                        ]
                ]

pushTestToAntithesis
    :: Wallet
    -> Directory
    -> TestRunId
    -> WithContext m (AValidationResult PushFailure ())
pushTestToAntithesis = error "Not implemented yet"

pushTestToAntithesisIO
    :: MonadIO m
    => TokenId
    -> Registry
    -> AntithesisAuth
    -> Wallet
    -> Directory
    -> TestRunId
    -> WithContext m (AValidationResult PushFailure ())
pushTestToAntithesisIO
    tk
    registry
    auth
    wallet
    dir
    testRunId@(TestRunId _trId) = do
        tag <- liftIO $ buildConfigImage registry dir testRunId
        liftIO $ pushConfigImage tag
        images <- liftIO $ collectImagesFromAssets dir
        Duration duration <- getDuration tk testRunId
        let body =
                PostTestRunRequest
                    { description = "Test run " ++ show _trId
                    , duration = realToFrac duration
                    , config_image = tagString tag
                    , images
                    , recipients = []
                    }
        void $ liftIO $ curl $ renderPostToAntithesis auth body
        publishAcceptanceToCardano wallet testRunId
        return $ ValidationSuccess ()

collectImagesFromAssets :: Directory -> IO [String]
collectImagesFromAssets (Directory dirname) = do
    output <-
        runCommandAndShowErrorOnExitFailure
            "docker"
            ["compose", "--project-directory", dirname, "config", "--images"]
    let images = nub $ sort $ filter (not . null) $ lines output
    return images

getDuration
    :: Monad m => TokenId -> TestRunId -> WithContext m Duration
getDuration tk testRunId = do
    mts <- resolveTestRunId @'RunningT tk testRunId
    case mts of
        Nothing -> error "TestRunId could not be resolved"
        Just (Fact _ (Accepted (Pending d _))) -> pure d

publishAcceptanceToCardano
    :: Monad m => Wallet -> TestRunId -> WithContext m ()
publishAcceptanceToCardano _ _ = return ()

data AntithesisAuth = AntithesisAuth
    { username :: String
    , password :: String
    }
    deriving (Show, Eq)

renderPostToAntithesis
    :: AntithesisAuth -> PostTestRunRequest -> (String, [String])
renderPostToAntithesis (AntithesisAuth username password) request =
    let curlArgs = (command, args)
        command = "curl"
        args =
            [ "--fail"
            , "-u"
            , username ++ ":" ++ password
            , "-X"
            , "POST"
            , "https://cardano.antithesis.com/api/v1/launch/cardano"
            , "-H"
            , "Content-Type: application/json"
            , "-d"
            , BL.unpack $ Aeson.encode request
            ]
    in  (curlArgs :: (String, [String]))

curl :: (String, [String]) -> IO String
curl (command, args) = readProcess command args ""

newtype Tag = Tag {tagString :: String}
    deriving (Show, Eq)

pushConfigImage :: Tag -> IO ()
pushConfigImage (Tag tag) =
    void
        $ readProcess
            "docker"
            [ "push"
            , tag
            ]
            ""

newtype Registry = Registry {unRegistry :: String}
    deriving (Show, Eq)

runCommandAndShowErrorOnExitFailure :: String -> [String] -> IO String
runCommandAndShowErrorOnExitFailure command args = do
    (exitCode, output, stderr) <-
        readProcessWithExitCode command args ""
    case exitCode of
        ExitFailure _ ->
            error
                $ command
                    ++ " "
                    ++ unwords args
                    ++ " failed: "
                    ++ stderr
                    ++ "\n"
                    ++ output
        ExitSuccess -> pure output

buildConfigImage :: Registry -> Directory -> TestRunId -> IO Tag
buildConfigImage (Registry registry) (Directory context) (TestRunId tag) =
    withSystemTempDirectory
        "anti-cli-test"
        $ \tmpDir -> do
            let dockerfilePath = tmpDir ++ "/Dockerfile"
            writeFile dockerfilePath dockerfile
            void
                $ runCommandAndShowErrorOnExitFailure
                    "docker"
                    [ "build"
                    , "-f"
                    , dockerfilePath
                    , "-t"
                    , tag
                    , context
                    ]
            return $ Tag (registry ++ "/" ++ tag)

data PushFailure = AntithesisNotResponding | PushFailed String
    deriving (Show, Eq)

instance Monad m => ToJSON m PushFailure where
    toJSON AntithesisNotResponding = object ["AntithesisNotResponding" .= ()]
    toJSON (PushFailed msg) = object ["PushFailed" .= msg]
