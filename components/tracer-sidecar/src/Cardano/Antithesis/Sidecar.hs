{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

module Cardano.Antithesis.Sidecar
    ( mkSpec
    , initialStateIO
    , processMessageIO
    , Output (..)
    , processMessages
    , initialState
    )
where

import Cardano.Antithesis.ForkTree
    ( ForkTreeState
    , Tip (..)
    , clusterForkDepth
    , initialForkTreeState
    , recordExtension
    , setTip
    )
import Cardano.Antithesis.LogMessage
    ( LogMessage (..)
    , LogMessageData (..)
    , NewTipSelectView (..)
    , Severity (Critical)
    )
import Cardano.Antithesis.Sdk
    ( alwaysOrUnreachableDeclaration
    , alwaysOrUnreachableFailed
    , sometimesOptionalDeclaration
    , sometimesOptionalReached
    , sometimesTracesDeclaration
    , sometimesTracesReached
    , writeSdkJsonl
    )
import qualified Data.Set as Set
import qualified Data.Text as T

import Control.Applicative
    ( (<|>)
    )
import Control.Arrow
    ( second
    )
import Control.Monad
    ( forM_
    , when
    )
import Control.Monad.Trans.Writer.Strict
    ( Writer
    , execWriter
    , tell
    )
import Data.Aeson
    ( Value
    )
import qualified Data.ByteString.Lazy as BL
import Data.Foldable
    ( foldl'
    )
import Data.List
    ( mapAccumL
    )
import Data.Maybe
    ( fromMaybe
    , mapMaybe
    )
import Data.Set
    ( Set
    )
import Data.Text
    ( Text
    )
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TL
import System.Environment (lookupEnv)
import System.IO (IOMode (AppendMode), withFile)

-- spec ------------------------------------------------------------------------

-- | Praos security parameter for the master testnet (k = 432).
-- Forks shorter than this heal by definition; any cluster-wide
-- divergence at this depth or beyond is unrecoverable.
defaultK :: Int
defaultK = 432

-- | Cap on per-host ancestry walks when computing common
-- ancestors.  Set generously above 'defaultK' so the walk can
-- still detect a common ancestor at the boundary.
defaultDepthCap :: Int
defaultDepthCap = defaultK * 2

mkSpec :: Int -> Maybe Text -> Bool -> Spec
mkSpec nPools consumerHost amaruEnabled = do
    mapM_
        sometimesTraces
        [ "TraceAddBlockEvent.SwitchedToAFork"
        , "PeerStatusChanged"
        ]

    forM_ [1 :: Int .. nPools] $ \i -> do
        let pool = "p" <> T.pack (show i)
        sometimes ("Any " <> pool <> " log") $ \_s LogMessage{host} ->
            fromMaybe host (T.stripSuffix ".example" host) == pool

    alwaysOrUnreachable "no critical logs" $ \_s msg@LogMessage{sev} ->
        justANodeKill msg || sev < Critical

    observe forwardAddedToCurrentChain
    observe recordAllChainPoints

    -- Cluster-wide fork-depth probe (#119).
    forkTreeProbe defaultK defaultDepthCap

    forM_ consumerHost $ \host ->
        amaruConsumerConvergenceProbe nPools host

    when amaruEnabled $ do
        sometimes "amaru stdout observed" $ \_s LogMessage{details} ->
            case details of
                AmaruStdout{} -> True
                _ -> False
        alwaysOrUnreachable "no fatal amaru consensus logs"
            $ \_s LogMessage{details} ->
                case details of
                    AmaruStdout{amaruMessage} ->
                        not
                            $ T.isInfixOf "Consensus died" amaruMessage
                                || T.isInfixOf
                                    "attempted roll back in the future"
                                    amaruMessage
                    _ -> True
  where
    -- Issue #123, Layer 2 was here — a "did the adversary appear in
    -- some producer's InboundGovernor stream" probe via substring
    -- match on @adversary.example@. Verified empirically that
    -- cardano-tracer emits InboundGovernor.Remote events with
    -- peer IP (192.168.x.y) not hostname, so the substring check
    -- never fires. Re-implementing this needs the tracer-side
    -- hostname↔IP mapping, which is non-trivial. Removed for now.

    recordAllChainPoints :: State -> LogMessage -> [Output]
    recordAllChainPoints
        _s
        LogMessage
            { details = AddedToCurrentChain{newtip}
            } =
            pure $ RecordChainPoint $ T.unpack newtip
    recordAllChainPoints _ _ = []

    forwardAddedToCurrentChain :: State -> LogMessage -> [Output]
    forwardAddedToCurrentChain
        _s
        LogMessage
            { host
            , details = AddedToCurrentChain{newtip}
            } =
            pure
                $ StdOut
                $ unwords
                    [ T.unpack host
                    , "added"
                    , T.unpack newtip
                    , "to current chain"
                    ]
    forwardAddedToCurrentChain _ _ = []

justANodeKill :: LogMessage -> Bool
justANodeKill LogMessage{details} =
    details == ServerError{reason = "AsyncCancelled"}

-- State -----------------------------------------------------------------------

data State = State
    { unreachedAssertions :: Set Text
    , forkTree :: !ForkTreeState
    , forkObserved :: !Bool
    -- ^ Cluster-wide fork depth has been observed > 0 at least
    -- once.  Used to fire the @\"cluster fork observed\"@
    -- 'sometimes' assertion.
    , forkExceededK :: !Bool
    -- ^ Cluster-wide fork depth has crossed the @k@ boundary.
    -- Used to fail the @\"cluster fork depth < k\"@
    -- 'alwaysOrUnreachable' assertion.
    , maxForkDepth :: !Int
    -- ^ Largest cluster-wide fork depth observed during the run.
    -- Surfaces as discrete Sometimes assertions per threshold so
    -- the report renders a depth-by-depth checklist of how deep
    -- the perturbation pushed the cluster.  Issue #123, Layer 3.
    , producerTipHashes :: !(Set Text)
    -- ^ Tip hashes observed on producer hosts.  Used by the
    -- amaru-consumer convergence property.
    , consumerFirstLen :: !(Maybe Int)
    -- ^ First observed amaru-consumer chain length.  The
    -- convergence property only fires after the consumer advances
    -- beyond this baseline.
    }

initialState :: Spec -> (State, [Output])
initialState spec =
    ( foldl (\a f -> f a) s0 setupFns
    , declarations spec
    )
  where
    s0 =
        State
            { unreachedAssertions = mempty
            , forkTree = initialForkTreeState
            , forkObserved = False
            , forkExceededK = False
            , maxForkDepth = 0
            , producerTipHashes = mempty
            , consumerFirstLen = Nothing
            }
    setupFns = stateInitFunctions spec

-- Spec ------------------------------------------------------------------------

type Spec = SpecWith ()

newtype SpecWith a = Spec (Writer [Rule] a)
    deriving (Functor, Applicative, Monad) via (Writer [Rule])

data Rule = Rule
    { _ruleProcess :: State -> LogMessage -> (State, [Output])
    , ruleDeclaration :: Maybe Value
    -- ^ Makes it possible to declare the assertion to the antithesis sdk
    , ruleInit :: State -> State
    -- ^ Makes it possible to initialize the 'State'
    }

data Output
    = StdOut String
    | AntithesisSdk Value
    | RecordChainPoint String

-- Properties ------------------------------------------------------------------

-- | Declare an antithesis 'sometimes' assertion.
--
-- Will cause a test failure if the provided function ever returns 'False'.
alwaysOrUnreachable
    :: Text
    -- ^ Name and identifier
    -> (State -> LogMessage -> Bool)
    -> Spec
alwaysOrUnreachable name f =
    Spec
        $ tell
            [ Rule process (Just (alwaysOrUnreachableDeclaration name)) initState
            ]
  where
    initState s = s{unreachedAssertions = Set.insert name (unreachedAssertions s)}

    process :: State -> LogMessage -> (State, [Output])
    process s@State{unreachedAssertions = scanningFor} msg@LogMessage{json} =
        case f s msg of
            False
                | Set.member name scanningFor ->
                    ( s{unreachedAssertions = Set.delete name scanningFor}
                    , [AntithesisSdk $ alwaysOrUnreachableFailed name json]
                    )
                | otherwise -> (s, [])
            True -> (s, [])

observe :: (State -> LogMessage -> [Output]) -> Spec
observe process = do
    Spec $ tell [Rule (\s msg -> (s, process s msg)) Nothing id]

-- | Declare an antithesis 'sometimes' assertion.
--
-- Will cause a test failure unless the provided function returns 'True' once.
sometimes
    :: Text
    -- ^ Name and identifier
    -> (State -> LogMessage -> Bool)
    -> Spec
sometimes name f =
    Spec
        $ tell
            [Rule process (Just (sometimesTracesDeclaration name)) initState]
  where
    initState s = s{unreachedAssertions = Set.insert name (unreachedAssertions s)}

    process :: State -> LogMessage -> (State, [Output])
    process s@State{unreachedAssertions = scanningFor} msg
        | Set.member name scanningFor && f s msg =
            ( s{unreachedAssertions = Set.delete name scanningFor}
            , [AntithesisSdk $ sometimesTracesReached name]
            )
        | otherwise = (s, [])

sometimesTraces :: Text -> Spec
sometimesTraces text = sometimes text $ \_s LogMessage{kind} -> kind == text

-- | Optional Sometimes assertion ('must_hit' = false). The runtime
-- doesn't flag a finding if the predicate never returns true — the
-- report just shows the property as unhit. Use for coverage
-- gradients: the depth-threshold checklist treats each unreached
-- threshold as informational, not a bug (Issue #123 Layer 3).
sometimesOptional
    :: Text
    -> (State -> LogMessage -> Bool)
    -> Spec
sometimesOptional name f =
    Spec
        $ tell
            [Rule process (Just (sometimesOptionalDeclaration name)) initState]
  where
    initState s = s{unreachedAssertions = Set.insert name (unreachedAssertions s)}
    process :: State -> LogMessage -> (State, [Output])
    process s@State{unreachedAssertions = scanningFor} msg
        | Set.member name scanningFor && f s msg =
            ( s{unreachedAssertions = Set.delete name scanningFor}
            , [AntithesisSdk $ sometimesOptionalReached name]
            )
        | otherwise = (s, [])

-- Fork-tree probe (#119) ------------------------------------------------------

-- | Cluster-wide fork-depth probe.  Three rules:
--
--   1. State updater: parse @AddedToCurrentChain@ /
--      @SwitchedToAFork@ events, feed them into the
--      'ForkTreeState', and recompute cluster fork depth.
--      Sets 'forkObserved' once depth > 0; sets
--      'forkExceededK' once depth >= @k@.
--   2. @Sometimes: cluster fork observed@ — fires once
--      'forkObserved' becomes 'True'.  Proves that fault
--      injection actually exercises the fork-handling path,
--      otherwise the @Always@ below is vacuous.
--   3. @AlwaysOrUnreachable: cluster fork depth < k@ — fires
--      once 'forkExceededK' becomes 'True'.  An unrecoverable
--      divergence by Praos's definition.
forkTreeProbe :: Int -> Int -> Spec
forkTreeProbe k depthCap = do
    Spec
        $ tell
            [ Rule
                { _ruleProcess = updateForkTree k depthCap
                , ruleDeclaration = Nothing
                , ruleInit = id
                }
            ]
    sometimes "cluster fork observed" $ \s _ -> forkObserved s
    alwaysOrUnreachable "cluster fork depth < k" $ \s _ ->
        not (forkExceededK s)
    -- Issue #123, Layer 3 — perturbation depth checklist.  One
    -- discrete Sometimes assertion per meaningful fork-depth
    -- threshold.  The highest passed threshold in the report tells
    -- you how deep the cluster forked under fault injection without
    -- drilling into per-event details.  Thresholds are sparse on
    -- purpose (k = 432 makes per-integer rows wasteful and floods
    -- the report).
    forM_ depthThresholds $ \threshold ->
        sometimesOptional
            ( "cluster_fork_depth_"
                <> T.pack (show threshold)
                <> "_observed"
            )
            $ \s _ -> maxForkDepth s >= threshold

-- | Sparse depth thresholds — covers "anything", "small fork",
-- "medium fork", "large fork" without one row per integer.  k=432
-- is the failure ceiling; thresholds beyond ~k/2 are uninteresting
-- because crossing k is already its own AlwaysOrUnreachable
-- assertion.
depthThresholds :: [Int]
depthThresholds = [2, 3, 5, 10, 50, 100, 200]

-- | Parse a @"hash@slot"@ tip string into a 'Tip' record.
parseTip :: NewTipSelectView -> Text -> Tip
parseTip
    NewTipSelectView{chainLength = clen, slotNo = sno}
    newtipStr =
        Tip
            { tipHash = T.takeWhile (/= '@') newtipStr
            , tipChainLength = clen
            , tipSlotNo = sno
            }

-- | Apply a single trace event to the 'ForkTreeState' and
-- update derived flags.  No SDK output here — the
-- 'sometimes' / 'alwaysOrUnreachable' rules above turn the
-- flags into observable assertions.
updateForkTree
    :: Int -> Int -> State -> LogMessage -> (State, [Output])
updateForkTree k depthCap s LogMessage{host, details} =
    case details of
        AddedToCurrentChain{newTipSelectView, newtip} ->
            let newTip = parseTip newTipSelectView newtip
                forkTree' = recordExtension host newTip (forkTree s)
            in  (refresh s{forkTree = forkTree'}, [])
        SwitchedToAFork{newTipSelectView, newtip} ->
            let newTip = parseTip newTipSelectView newtip
                forkTree' = setTip host newTip (forkTree s)
            in  (refresh s{forkTree = forkTree'}, [])
        _ -> (s, [])
  where
    refresh st = case clusterForkDepth depthCap (forkTree st) of
        Nothing -> st
        Just d ->
            st
                { forkObserved = forkObserved st || d > 0
                , forkExceededK = forkExceededK st || d >= k
                , maxForkDepth = max d (maxForkDepth st)
                }

-- Amaru consumer convergence probe (#180) -------------------------------------

amaruConsumerConvergenceProbe :: Int -> Text -> Spec
amaruConsumerConvergenceProbe nPools consumerHost = do
    Spec
        $ tell
            [ Rule
                { _ruleProcess = updateAmaruConsumerConvergence nPools consumerHost
                , ruleDeclaration = Nothing
                , ruleInit = id
                }
            ]
    sometimes "amaru-served consumer reached producer tip"
        $ \State{producerTipHashes, consumerFirstLen} LogMessage{host, details} ->
            case details of
                AddedToCurrentChain{newTipSelectView, newtip}
                    | sameHost consumerHost host ->
                        let newTip = parseTip newTipSelectView newtip
                        in  maybe
                                False
                                ( \firstLen ->
                                    tipChainLength newTip > firstLen
                                        && Set.member
                                            (tipHash newTip)
                                            producerTipHashes
                                )
                                consumerFirstLen
                _ -> False

updateAmaruConsumerConvergence
    :: Int -> Text -> State -> LogMessage -> (State, [Output])
updateAmaruConsumerConvergence nPools consumerHost s LogMessage{host, details} =
    case details of
        AddedToCurrentChain{newTipSelectView, newtip}
            | isProducerHost nPools host ->
                let newTip = parseTip newTipSelectView newtip
                in  ( s
                        { producerTipHashes =
                            Set.insert (tipHash newTip) (producerTipHashes s)
                        }
                    , []
                    )
            | sameHost consumerHost host ->
                let newTip = parseTip newTipSelectView newtip
                in  ( s
                        { consumerFirstLen =
                            consumerFirstLen s
                                <|> Just (tipChainLength newTip)
                        }
                    , []
                    )
        _ -> (s, [])

isProducerHost :: Int -> Text -> Bool
isProducerHost nPools host =
    let stem = hostStem host
    in  stem
            `Set.member` Set.fromList
                ( ["p" <> T.pack (show i) | i <- [1 :: Int .. nPools]]
                    ++ ["relay" <> T.pack (show i) | i <- [1 :: Int .. nPools]]
                    ++ ["amaru-relay-" <> T.pack (show i) | i <- [1 :: Int .. nPools]]
                    ++ ["bootstrap-producer"]
                )

sameHost :: Text -> Text -> Bool
sameHost configured observed =
    hostStem configured == hostStem observed

hostStem :: Text -> Text
hostStem host =
    fromMaybe host (T.stripSuffix ".example" host)

declarations :: Spec -> [Output]
declarations (Spec s) = mapMaybe (fmap AntithesisSdk . ruleDeclaration) $ execWriter s

stateInitFunctions :: Spec -> [State -> State]
stateInitFunctions (Spec s) = map ruleInit $ execWriter s

processMessage :: Spec -> State -> LogMessage -> (State, [Output])
processMessage (Spec w) =
    let rules = execWriter w
    in  \s0 logMsg ->
            let step (s, vals) (Rule f _ _) =
                    let (s', newVals) = f s logMsg
                    in  (s', vals ++ newVals)
                (finalState, collected) = foldl' step (s0, []) rules
            in  (finalState, reverse collected)

processMessages
    :: Spec -> (State, [Output]) -> [LogMessage] -> (State, [Output])
processMessages spec st =
    second (concat . (v :))
        . mapAccumL (processMessage spec) s
  where
    (s, v) = st

-- IO --------------------------------------------------------------------------

hoistToIO :: (State, [Output]) -> IO State
hoistToIO (s, vals) = do
    forM_ vals $ \case
        AntithesisSdk v -> writeSdkJsonl v
        StdOut t -> putStrLn t
        RecordChainPoint p -> writeChainPoint p
    return s
  where
    writeChainPoint :: String -> IO ()
    writeChainPoint v = do
        file <-
            fromMaybe "/tmp/chainPoints.log" <$> lookupEnv "CHAINPOINT_FILEPATH"
        withFile file AppendMode $ \h ->
            BL.hPutStr h (TL.encodeUtf8 (TL.pack v) <> "\n")

initialStateIO :: Spec -> IO State
initialStateIO spec = hoistToIO $ initialState spec

processMessageIO :: Spec -> State -> LogMessage -> IO State
processMessageIO spec s msg = hoistToIO $ processMessage spec s msg
