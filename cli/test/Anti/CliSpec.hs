{-# LANGUAGE QuasiQuotes #-}

module Anti.CliSpec
    ( spec
    , runDummyServer
    , anti
    )
where

import Anti.Server (appDummy)
import App (server)
import Cli (Command (..))
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async)
import Core.Types
    ( Directory (..)
    , Platform (..)
    , PublicKeyHash (..)
    , Repository (..)
    , RequestRefId (..)
    , SHA1 (..)
    , Username (..)
    )
import Data.Aeson (encodeFile)
import Data.Aeson.QQ
import Lib.JSON (object, (.=))
import Network.Wai.Handler.Warp (run)
import Options (Options (..))
import Oracle.Cli (OracleCommand (..))
import Oracle.Token.Cli (TokenCommand (..))
import System.Environment (setEnv, withArgs)
import Test.Hspec
    ( Spec
    , beforeAll_
    , it
    , shouldReturn
    , xit
    )
import Text.JSON.Canonical (JSValue (JSArray, JSNull))
import User.Cli (UserCommand (..))
import User.Requester.Cli (RequesterCommand (..))
import User.Types
    ( Direction (..)
    , Duration (..)
    , RegisterPublicKey (..)
    , RegisterRoleKey (..)
    , TestRun (..)
    )

runDummyServer :: IO ()
runDummyServer = do
    _ <- async $ do
        run 8084 appDummy
    threadDelay 1000000

    let walletFile = "/tmp/anti-test-wallet.json"
    encodeFile
        walletFile
        [aesonQQ| {
        "mnemonic": ["very", "actress", "black", "another", "choice", "cry", "consider", "agree", "sudden", "garage", "error", "transfer"]
        } |]

    setEnv "ANTI_MPFS_HOST" "http://localhost:8084"
    setEnv "ANTI_TOKEN_ID" "dummyTokenId"
    setEnv "ANTI_WALLET_FILE" walletFile
    return ()

anti :: [String] -> IO (Options, JSValue)
anti args = do
    -- Simulate the command line arguments
    -- Call the main function with the simulated arguments
    ev <- withArgs args server
    case ev of
        (_, Left err) -> error $ "Error: " ++ show err
        (o, Right result) -> return (o, result)

dummyTxHash :: Monad m => m JSValue
dummyTxHash =
    object
        ["txHash" .= ("dummyTransactionId" :: String), "value" .= JSNull]

spec :: Spec
spec = beforeAll_ runDummyServer $ do
    dummyTxHashJSON <- dummyTxHash
    xit "can request user registration" $ do
        let args =
                [ "user"
                , "request"
                , "register-public-key"
                , "--platform"
                , "github"
                , "--username"
                , "paolino"
                , "--pubkeyhash"
                , "AAAAC3NzaC1lZDI1NTE5AAAAIO773JHqlyLm5XzOjSe+Q5yFJyLFuMLL6+n63t4t7HR8"
                ]
        let opts =
                Options
                    { optionsCommand =
                        UserCommand
                            $ UserRequesterCommand
                            $ RegisterUser
                                RegisterPublicKey
                                    { platform = Platform "github"
                                    , username = Username "paolino"
                                    , pubkeyhash =
                                        PublicKeyHash
                                            "AAAAC3NzaC1lZDI1NTE5AAAAIO773JHqlyLm5XzOjSe+Q5yFJyLFuMLL6+n63t4t7HR8"
                                    , direction = Insert
                                    }
                    }

        anti args
            `shouldReturn` (opts, dummyTxHashJSON)
    xit "can request user unregistration" $ do
        let args =
                [ "user"
                , "request"
                , "unregister-public-key"
                , "--platform"
                , "github"
                , "--username"
                , "bob"
                , "--pubkeyhash"
                , "607a0d8a64616a407537edf0d9b59cf4cb509c556f6d2de4250ce15df2"
                ]

        let opts =
                Options
                    { optionsCommand =
                        UserCommand
                            $ UserRequesterCommand
                            $ RegisterUser
                                RegisterPublicKey
                                    { platform = Platform "github"
                                    , username = Username "bob"
                                    , pubkeyhash =
                                        PublicKeyHash
                                            "607a0d8a64616a407537edf0d9b59cf4cb509c556f6d2de4250ce15df2"
                                    , direction = Delete
                                    }
                    }
        anti args `shouldReturn` (opts, dummyTxHashJSON)

    xit "can request removing user from a project" $ do
        let args =
                [ "user"
                , "request"
                , "unregister-role"
                , "--platform"
                , "github"
                , "--repository"
                , "cardano-foundation/antithesis"
                , "--role"
                , "maintainer"
                , "--username"
                , "bob"
                ]
        let opts =
                Options
                    { optionsCommand =
                        UserCommand
                            $ UserRequesterCommand
                            $ RegisterRole
                            $ RegisterRoleKey
                                { platform = Platform "github"
                                , repository = Repository "cardano-foundation" "antithesis"
                                , username = Username "bob"
                                , direction = Delete
                                }
                    }

        anti args `shouldReturn` (opts, dummyTxHashJSON)

    xit "can request antithesis run" $ do
        let args =
                [ "user"
                , "request"
                , "test"
                , "--platform"
                , "github"
                , "--repository"
                , "cardano-foundation/antithesis"
                , "--username"
                , "bob"
                , "--commit"
                , "9114528e2343e6fcf3c92de71364275227e6b16d"
                ]
        let opts =
                Options
                    { optionsCommand =
                        UserCommand
                            $ UserRequesterCommand
                            $ RequestTest
                                TestRun
                                    { platform = Platform "github"
                                    , repository = Repository "cardano-foundation" "antithesis"
                                    , requester = Username "bob"
                                    , commitId = SHA1 "9114528e2343e6fcf3c92de71364275227e6b16d"
                                    , directory = Directory "."
                                    , testRunIndex = 0
                                    }
                            $ Duration 4
                    }
        anti args `shouldReturn` (opts, dummyTxHashJSON)

    xit "can retract a request" $ do
        let args =
                [ "user"
                , "request"
                , "retract"
                , "--outref"
                , "9114528e2343e6fcf3c92de71364275227e6b16d-0"
                ]
        let opts =
                Options
                    { optionsCommand =
                        UserCommand
                            $ RetractRequest
                                { outputReference =
                                    RequestRefId
                                        "9114528e2343e6fcf3c92de71364275227e6b16d-0"
                                }
                    }
        anti args `shouldReturn` (opts, dummyTxHashJSON)

    it "can get a token" $ do
        let args =
                [ "oracle"
                , "token"
                , "get"
                ]
        let opts =
                Options
                    { optionsCommand =
                        OracleCommand $ OracleTokenCommand GetToken
                    }
        anti args
            `shouldReturn` ( opts
                           , JSArray []
                           )
