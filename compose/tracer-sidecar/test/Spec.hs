{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Spec where

import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as BL

import Cardano.Antithesis.LogMessage
import Cardano.Antithesis.Sidecar


import Data.Aeson
    ( Value
    , decodeStrict'
    , encode
    )
import Data.Maybe
    ( mapMaybe
    )
import Test.Hspec
import Test.Hspec.Golden
    ( Golden (..)
    )

spec :: Spec
spec = do
    (msgs :: [LogMessage])
        <- runIO $ mapMaybe decodeStrict' . B8.lines
        <$> B8.readFile "test/data/input.jsonl"

    it "processMessages" $
        let (_finalState, actualVals) = processMessages initialState msgs
        in myGoldenTest actualVals

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
