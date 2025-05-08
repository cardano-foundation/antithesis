{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
module Cardano.Antithesis.Sdk where

import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T

import Data.Aeson
    ( Value (Null)
    , encode
    , object
    , (.=)
    )
import Data.Aeson.QQ
    ( aesonQQ
    )
import Data.Maybe
    ( fromMaybe
    )
import Data.Text
    ( Text
    )
import GHC.Stack
    ( HasCallStack
    , SrcLoc (..)
    , callStack
    , getCallStack
    )
import System.Environment
    ( lookupEnv
    )
import System.IO
    ( IOMode (AppendMode)
    , withFile
    )


-- | Append a JSON Value as one line to $ANTITHESIS_OUTPUT_DIR/sdk.jsonl
writeSdkJsonl :: Value -> IO ()
writeSdkJsonl v = do
  dir <- fromMaybe "/tmp"<$> lookupEnv "ANTITHESIS_OUTPUT_DIR"
  let outFile = dir ++ "/sdk.jsonl"
  -- open in AppendMode and write the JSON + newline
  withFile outFile AppendMode $ \h ->
    BL.hPutStr h (encode v <> "\n")


-- Hard code values for now

sometimesTracesDeclaration :: Text -> Value
sometimesTracesDeclaration label = [aesonQQ|
{
  "antithesis_assert": {
    "id":           #{label},
    "message":      #{label},
    "condition":    false,
    "display_type": "Sometimes",
    "hit":          false,
    "must_hit":     true,
    "assert_type":  "sometimes",
    "location": {
      "file":         "",
      "function":     "",
      "class":        "",
      "begin_line":   0,
      "begin_column": 0
    },
    "details": null
  }
}
|]

sometimesTracesReached :: HasCallStack => Text -> Value
sometimesTracesReached label =
  let
      ((funcName, loc) : _) = getCallStack callStack

      file   = T.pack (srcLocFile      loc)
      modName = T.pack (srcLocModule    loc)
      func   = T.pack funcName
      line   = srcLocStartLine loc
      column = srcLocStartCol  loc

      locObj = object
        [ "file"         .= file
        , "function"     .= func
        , "class"        .= modName
        , "begin_line"   .= line
        , "begin_column" .= column
        ]

  in object
     [ "antithesis_assert" .= object
       [ "id"           .= label
       , "message"      .= label
       , "condition"    .= True
       , "display_type" .= ("Sometimes"     :: Text)
       , "hit"          .= True
       , "must_hit"     .= True
       , "assert_type"  .= ("sometimes"     :: Text)
       , "location"     .= locObj
       , "details"      .= Null
       ]
     ]

