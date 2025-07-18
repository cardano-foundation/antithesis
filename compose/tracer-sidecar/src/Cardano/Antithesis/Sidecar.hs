{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.Antithesis.Sidecar where

import Cardano.Antithesis.LogMessage
import Cardano.Antithesis.Sdk

import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as BL
import qualified Data.Set as Set
import qualified Data.Text as T

import Control.Arrow
    ( second
    )
import Control.Monad
    ( forM_
    )
import Control.Monad.Trans.Writer.Strict
    ( Writer
    , execWriter
    , tell
    )
import Data.Aeson
    ( Value
    , encode
    , toJSON
    )
import Data.Foldable
    ( foldl'
    )
import Data.List
    ( mapAccumL
    )
import Data.Maybe
    ( fromJust
    , mapMaybe
    )
import Data.Set
    ( Set
    )
import Data.Text
    ( Text
    )

-- spec ------------------------------------------------------------------------

mkSpec :: Int -> Spec
mkSpec nPools = do
    mapM_ sometimesTraces
        [ "TraceAddBlockEvent.SwitchedToAFork"
        , "PeerStatusChanged"
        ]

    forM_ [1 :: Int .. nPools] $ \i -> do
        let pool = "p" <> T.pack (show i)
        sometimes ("Any " <> pool <> " log") $ \_s LogMessage{host} ->
            fromJust (T.stripSuffix ".example" host) == pool

    alwaysOrUnreachable "no critical logs" $ \_s LogMessage{sev} ->
        sev < Critical

    observe forwardAddedToCurrentChain
  where
    forwardAddedToCurrentChain :: State -> LogMessage -> [Output]
    forwardAddedToCurrentChain
        _s
        LogMessage
            { host
            , details = AddedToCurrentChain{newtip}
            }
        = (:[]) $ StdOut $ unwords
            [ T.unpack host
            , "added"
            , T.unpack newtip
            , "to current chain"
            ]
    forwardAddedToCurrentChain _ _ = []

-- State -----------------------------------------------------------------------

newtype State = State
  { unreachedAssertions :: Set Text
  }

initialState :: Spec -> (State, [Output])
initialState spec =
  ( foldl (\a f -> f a) s0 setupFns
  , declarations spec
  )
  where
    s0 = State mempty
    setupFns = stateInitFunctions spec

-- Spec ------------------------------------------------------------------------

type Spec = SpecWith ()

newtype SpecWith a = Spec (Writer [Rule] a)
  deriving (Functor, Applicative, Monad) via (Writer [Rule])

data Rule = Rule
    { ruleProcess     :: State -> LogMessage -> (State, [Output])
    , ruleDeclaration :: Maybe Value -- ^ Makes it possible to declare the assertion to the antithesis sdk
    , ruleInit        :: State -> State -- ^ Makes it possible to initialize the 'State'
    }

data Output
    = StdOut String
    | AntithesisSdk Value

-- Properties ------------------------------------------------------------------

-- | Declare an antithesis 'sometimes' assertion.
--
-- Will cause a test failure if the provided function ever returns 'False'.
alwaysOrUnreachable
  :: Text -- ^ Name and identifier
  -> (State -> LogMessage -> Bool)
  -> Spec
alwaysOrUnreachable name f =
  Spec $ tell [ Rule process  (Just (alwaysOrUnreachableDeclaration name)) initState]
  where
    initState s = s { unreachedAssertions = Set.insert name (unreachedAssertions s) }

    process :: State -> LogMessage -> (State, [Output])
    process s@(State scanningFor) msg@LogMessage{json} = case f s msg of
        False
            | Set.member name scanningFor ->
                ( State (Set.delete name scanningFor)
                , [AntithesisSdk $ alwaysOrUnreachableFailed name json]
                )
            | otherwise -> (State scanningFor, [])
        True  -> (State scanningFor, [])

observe :: (State -> LogMessage -> [Output]) -> Spec
observe process = do
    Spec $ tell [ Rule (\s msg -> (s, process s msg)) Nothing id]


-- | Declare an antithesis 'sometimes' assertion.
--
-- Will cause a test failure unless the provided function returns 'True' once.
sometimes
  :: Text -- ^ Name and identifier
  -> (State -> LogMessage -> Bool)
  -> Spec
sometimes name f =
  Spec $ tell [ Rule process  (Just (sometimesTracesDeclaration name)) initState]
  where
    initState s = s { unreachedAssertions = Set.insert name (unreachedAssertions s) }

    process :: State -> LogMessage -> (State, [Output])
    process s@(State scanningFor) msg
        | Set.member name scanningFor && f s msg =
            ( State (Set.delete name scanningFor)
            , [AntithesisSdk $ sometimesTracesReached name]
            )
        | otherwise = (State scanningFor, [])

sometimesTraces :: Text -> Spec
sometimesTraces text = sometimes text $ \_s LogMessage{kind} -> kind == text

declarations :: Spec -> [Output]
declarations (Spec s) = mapMaybe (fmap AntithesisSdk . ruleDeclaration) $ execWriter s

stateInitFunctions :: Spec -> [State -> State]
stateInitFunctions (Spec s) = map ruleInit $ execWriter s

processMessage :: Spec -> State -> LogMessage -> (State, [Output])
processMessage (Spec w) =
  let rules = execWriter w
  in \s0 logMsg ->
       let step (s, vals) (Rule f _ _) =
             let (s', newVals) = f s logMsg
             in  (s', vals ++ newVals)
           (finalState, collected) = foldl' step (s0, []) rules
       in  (finalState, reverse collected)

processMessages :: Spec -> (State, [Output]) -> [LogMessage] -> (State, [Output])
processMessages spec st =
    second (concat . (v:))
  . mapAccumL (processMessage spec) s
  where
    (s, v) = st

-- IO --------------------------------------------------------------------------

hoistToIO :: (State, [Output]) -> IO State
hoistToIO (s, vals) = do
    forM_ vals $ \case
        AntithesisSdk v -> writeSdkJsonl v
        StdOut t        -> putStrLn t
    return s

initialStateIO :: Spec -> IO State
initialStateIO spec = hoistToIO $ initialState spec

processMessageIO :: Spec -> State -> LogMessage -> IO State
processMessageIO spec s msg = hoistToIO $ processMessage spec s msg
