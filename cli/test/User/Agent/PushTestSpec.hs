module User.Agent.PushTestSpec
    ( spec
    )
where

import Core.Types.Basic (Directory (..))
import Test.Hspec
import User.Agent.Cli (TestRunId (..))
import User.Agent.PushTest
    ( AntithesisAuth (..)
    , PostTestRunRequest (..)
    , Registry (..)
    , Tag (..)
    , buildConfigImage
    , collectImagesFromAssets
    , renderPostToAntithesis
    )

spec :: Spec
spec = do
    describe "collectImagesFromAssets" $ do
        it "should collect images from a docker-compose file" $ do
            -- Here you would write tests for the collectImagesFromAssets function
            collectImagesFromAssets (Directory "test/data")
                `shouldReturn` [ "ghcr.io/cardano-foundation/antithesis/configurator:latest"
                               , "ghcr.io/cardano-foundation/antithesis/sidecar:latest"
                               , "ghcr.io/cardano-foundation/antithesis/tracer-sidecar:latest"
                               , "ghcr.io/cardano-foundation/antithesis/tracer:latest"
                               , "ghcr.io/intersectmbo/cardano-node:latest"
                               ]
    describe "buildConfigImage" $ do
        it "should build the Dockerfile for the cardano_node_master" $ do
            buildConfigImage
                (Registry "registry")
                (Directory "test/data")
                (TestRunId "dummy")
                `shouldReturn` Tag "registry/dummy"
    describe "renderPostToAntithesis" $ do
        it "should render the curl command for pushing to Antithesis" $ do
            images <-
                collectImagesFromAssets (Directory "test/data")
            configTag <-
                buildConfigImage
                    (Registry "registry")
                    (Directory "test/data")
                    (TestRunId "dummy")
            let auth = AntithesisAuth "user" "pass"
                body =
                    PostTestRunRequest
                        { description = "Test Run"
                        , duration = 3600
                        , config_image = tagString configTag
                        , images = images
                        , recipients = ["hal@cardanofoundation.org"]
                        }
                (cmd, args) = renderPostToAntithesis auth body
            cmd `shouldBe` "curl"
            args
                `shouldBe` [ "--fail"
                           , "-u"
                           , "user:pass"
                           , "-X"
                           , "POST"
                           , "https://cardano.antithesis.com/api/v1/launch/cardano"
                           , "-H"
                           , "Content-Type: application/json"
                           , "-d"
                           , "{\"params\":{\"antithesis.config_image\":\"registry/dummy\",\"antithesis.description\":\"Test Run\",\"antithesis.images\":\"ghcr.io/cardano-foundation/antithesis/configurator:latest;ghcr.io/cardano-foundation/antithesis/sidecar:latest;ghcr.io/cardano-foundation/antithesis/tracer-sidecar:latest;ghcr.io/cardano-foundation/antithesis/tracer:latest;ghcr.io/intersectmbo/cardano-node:latest\",\"antithesis.report.recipient\":\"hal@cardanofoundation.org\",\"custom.duration\":3600}}"
                           ]
