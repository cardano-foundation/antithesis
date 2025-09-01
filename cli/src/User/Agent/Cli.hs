{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}

module User.Agent.Cli
    ( AgentCommand (..)
    , TestRunId (..)
    , IsReady (..)
    , agentCmd
    )
where

import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Trans.Class (lift)
import Core.Context
    ( WithContext
    , askConfig
    , askMpfs
    , askSubmit
    , askValidation
    , withMPFS
    )
import Core.Types.Basic
    ( Directory
    , Duration
    , Owner
    , Platform
    , Repository
    , TokenId
    )
import Core.Types.Change (Change (..), Key (..))
import Core.Types.Fact (Fact (..), keyHash, parseFacts)
import Core.Types.Operation (Op (..), Operation (..))
import Core.Types.Tx (WithTxHash (..))
import Core.Types.Wallet (Wallet (..))
import Data.Functor (($>), (<&>))
import Data.List (find)
import MPFS.API
    ( MPFS (..)
    , RequestDeleteBody (..)
    , RequestInsertBody (..)
    , RequestUpdateBody (..)
    )
import Oracle.Config.Types (Config (..))
import Oracle.Validate.DownloadAssets
    ( DownloadAssetsFailure
    , validateDownloadAssets
    )
import Oracle.Validate.Requests.ManageWhiteList
    ( UpdateWhiteListFailure (..)
    , validateAddWhiteListed
    , validateRemoveWhiteListed
    )
import Oracle.Validate.Requests.TestRun.Update
    ( UpdateTestRunFailure (..)
    , validateToDoneUpdate
    , validateToRunningUpdate
    )
import Oracle.Validate.Types
    ( AValidationResult (..)
    , ForRole (..)
    , Validate
    , Validated
    , hoistValidate
    , liftMaybe
    , runValidate
    )
import Submitting (Submission (..))
import Text.JSON.Canonical
    ( FromJSON (..)
    , JSValue (..)
    , ToJSON (..)
    )
import User.Agent.PushTest
    ( AntithesisAuth
    , PushFailure
    , Registry
    , pushTestToAntithesisIO
    )
import User.Agent.Types
    ( TestRunId (..)
    , TestRunMap (..)
    , TestRunStatus (..)
    , WhiteListKey (..)
    )
import User.Types
    ( Phase (..)
    , TestRun (..)
    , TestRunRejection
    , TestRunState (..)
    , URL (..)
    )
import Validation (Validation)

type ValidateWithContext m a =
    Validate UpdateTestRunFailure (WithContext m) a

withPreviousTestRunState
    :: (Monad m, FromJSON Maybe (TestRunState phase))
    => TokenId
    -> TestRunId
    -> (Fact TestRun (TestRunState phase) -> ValidateWithContext m a)
    -> ValidateWithContext m a
withPreviousTestRunState tk (TestRunId testRunId) cont = do
    facts <- lift
        $ fmap parseFacts
        $ withMPFS
        $ \mpfs -> mpfsGetTokenFacts mpfs tk
    let match :: Fact TestRun JSValue -> Bool
        match (Fact key _) = case keyHash key of
            Nothing -> False
            Just keyId -> keyId == testRunId
    fact <-
        liftMaybe UpdateTestRunTestRunIdNotResolved
            $ find match facts
    value <-
        liftMaybe UpdateTestRunWrongPreviousState
            $ fromJSON
            $ factValue fact
    cont fact{factValue = value}

updateTestRunState
    :: (Monad m, FromJSON Maybe (TestRunState phase))
    => TokenId
    -> TestRunId
    -> ( Fact TestRun (TestRunState phase)
         -> ValidateWithContext m a
       )
    -> WithContext m (AValidationResult UpdateTestRunFailure a)
updateTestRunState tokenId key =
    runValidate . withPreviousTestRunState tokenId key

agentCmd
    :: MonadIO m
    => AgentCommand NotReady a
    -> WithContext m a
agentCmd = \case
    Query tokenId -> queryCommand tokenId
    WhiteList tokenId wallet platform repo ->
        whiteList tokenId wallet platform repo
    BlackList tokenId wallet platform repo ->
        blackList tokenId wallet platform repo
    DownloadAssets tokenId key dir -> downloadAssets tokenId key dir
    Accept tokenId wallet key () ->
        updateTestRunState tokenId key $ \fact ->
            acceptCommand tokenId wallet fact
    Reject tokenId wallet key () reason ->
        updateTestRunState tokenId key $ \fact ->
            rejectCommand tokenId wallet fact reason
    Report tokenId wallet key () duration url ->
        updateTestRunState tokenId key $ \fact ->
            reportCommand tokenId wallet fact duration url
    PushTest tokenId registry auth wallet dir key ->
        pushTestToAntithesisIO
            tokenId
            registry
            auth
            wallet
            dir
            key

data IsReady = NotReady | Ready
    deriving (Show, Eq)

type family IfReady a b where
    IfReady NotReady _ = ()
    IfReady Ready b = b

data Role = Internal | External
    deriving (Show, Eq)

type family ResolveId phase where
    ResolveId NotReady = TestRunId
    ResolveId Ready = TestRun

data AgentCommand (phase :: IsReady) result where
    Accept
        :: TokenId
        -> Wallet
        -> ResolveId phase
        -> IfReady phase (TestRunState PendingT)
        -> AgentCommand
            phase
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState RunningT))
            )
    Reject
        :: TokenId
        -> Wallet
        -> ResolveId phase
        -> IfReady phase (TestRunState PendingT)
        -> [TestRunRejection]
        -> AgentCommand
            phase
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState DoneT))
            )
    Report
        :: TokenId
        -> Wallet
        -> ResolveId phase
        -> IfReady phase (TestRunState RunningT)
        -> Duration
        -> URL
        -> AgentCommand
            phase
            ( AValidationResult
                UpdateTestRunFailure
                (WithTxHash (TestRunState DoneT))
            )
    Query :: TokenId -> AgentCommand phase TestRunMap
    WhiteList
        :: TokenId
        -> Wallet
        -> Platform
        -> Repository
        -> AgentCommand
            phase
            (AValidationResult UpdateWhiteListFailure (WithTxHash ()))
    BlackList
        :: TokenId
        -> Wallet
        -> Platform
        -> Repository
        -> AgentCommand
            phase
            (AValidationResult UpdateWhiteListFailure (WithTxHash ()))
    DownloadAssets
        :: TokenId
        -> TestRunId
        -> Directory
        -> AgentCommand
            phase
            (AValidationResult DownloadAssetsFailure ())
    PushTest
        :: TokenId
        -> Registry
        -> AntithesisAuth
        -> Wallet
        -> Directory
        -> TestRunId
        -> AgentCommand phase (AValidationResult PushFailure ())

deriving instance Show (AgentCommand NotReady result)
deriving instance Eq (AgentCommand NotReady result)
deriving instance Show (AgentCommand Ready result)
deriving instance Eq (AgentCommand Ready result)

whiteList
    :: Monad m
    => TokenId
    -> Wallet
    -> Platform
    -> Repository
    -> WithContext
        m
        ( AValidationResult
            UpdateWhiteListFailure
            (WithTxHash ())
        )
whiteList tokenId wallet platform repo = do
    let key = WhiteListKey platform repo
        change =
            Change
                { key = Key key
                , operation = Insert ()
                }
        requester = owner wallet
    validation <- askValidation $ Just tokenId
    Submission submit <- askSubmit wallet
    mpfs <- askMpfs
    mconfig <- askConfig tokenId
    lift $ runValidate $ do
        Config{configAgent} <- liftMaybe WhiteListConfigNotAvailable mconfig
        void $ validateAddWhiteListed validation requester configAgent change
        wtx <- lift $ submit $ \address -> do
            jkey <- toJSON key
            mpfsRequestInsert mpfs address tokenId
                $ RequestInsertBody{key = jkey, value = JSNull}
        pure $ wtx $> ()

blackList
    :: Monad m
    => TokenId
    -> Wallet
    -> Platform
    -> Repository
    -> WithContext
        m
        ( AValidationResult
            UpdateWhiteListFailure
            (WithTxHash ())
        )
blackList tokenId wallet platform repo = do
    let key = WhiteListKey platform repo
        change = Change (Key key) (Delete ())
        requester = owner wallet
    validation <- askValidation $ Just tokenId
    Submission submit <- askSubmit wallet
    mpfs <- askMpfs
    mconfig <- askConfig tokenId
    lift $ runValidate $ do
        Config{configAgent} <- liftMaybe WhiteListConfigNotAvailable mconfig
        void
            $ validateRemoveWhiteListed validation requester configAgent change
        wtx <- lift $ submit $ \address -> do
            jkey <- toJSON key
            mpfsRequestDelete mpfs address tokenId
                $ RequestDeleteBody{key = jkey, value = JSNull}
        pure $ wtx $> ()

queryCommand :: Monad m => TokenId -> WithContext m TestRunMap
queryCommand tokenId = do
    facts <- withMPFS $ \mpfs -> mpfsGetTokenFacts mpfs tokenId
    let testRunsPending = parseFacts facts
        testRunsRunning = parseFacts facts
        testRunsDone = parseFacts facts
    pure
        $ TestRunMap
            { pending = testRunsPending <&> StatusPending
            , running = testRunsRunning <&> StatusRunning
            , done = testRunsDone <&> StatusDone
            }

downloadAssets
    :: Monad m
    => TokenId
    -> TestRunId
    -> Directory
    -> WithContext m (AValidationResult DownloadAssetsFailure ())
downloadAssets tokenId testRunId dir = do
    testmap <- queryCommand tokenId
    validation <- askValidation $ Just tokenId
    lift $ runValidate $ do
        void $ validateDownloadAssets validation testmap testRunId dir

signAndSubmitAnUpdate
    :: (ToJSON m key, ToJSON m old, ToJSON m new, Monad m)
    => ( Validation m
         -> Owner
         -> Owner
         -> Change key (OpU old new)
         -> Validate UpdateTestRunFailure m Validated
       )
    -> TokenId
    -> Wallet
    -> Fact key old
    -> new
    -> ValidateWithContext m (WithTxHash new)
signAndSubmitAnUpdate validate tokenId wallet (Fact testRun oldState) newState = do
    let requester = owner wallet
    validation <- lift $ askValidation $ Just tokenId
    mconfig <- lift $ askConfig tokenId
    Submission submit <- lift $ askSubmit wallet
    mpfs <- lift askMpfs
    Config{configAgent} <-
        liftMaybe UpdateTestRunConfigNotAvailable mconfig
    void
        $ hoistValidate lift
        $ validate validation configAgent requester
        $ Change (Key testRun)
        $ Update oldState newState
    wtx <- lift $ lift $ submit $ \address -> do
        key <- toJSON testRun
        oldValue <- toJSON oldState
        newValue <- toJSON newState
        mpfsRequestUpdate mpfs address tokenId
            $ RequestUpdateBody{key, oldValue, newValue}
    pure $ wtx $> newState

reportCommand
    :: Monad m
    => TokenId
    -> Wallet
    -> Fact TestRun (TestRunState RunningT)
    -> Duration
    -> URL
    -> ValidateWithContext
        m
        (WithTxHash (TestRunState DoneT))
reportCommand tokenId wallet fact duration url =
    signAndSubmitAnUpdate
        (`validateToDoneUpdate` ForUser)
        tokenId
        wallet
        fact
        $ Finished (factValue fact) duration url

rejectCommand
    :: Monad m
    => TokenId
    -> Wallet
    -> Fact TestRun (TestRunState PendingT)
    -> [TestRunRejection]
    -> ValidateWithContext
        m
        (WithTxHash (TestRunState DoneT))
rejectCommand tokenId wallet fact reason =
    signAndSubmitAnUpdate
        (`validateToDoneUpdate` ForUser)
        tokenId
        wallet
        fact
        $ Rejected (factValue fact) reason

acceptCommand
    :: Monad m
    => TokenId
    -> Wallet
    -> Fact TestRun (TestRunState PendingT)
    -> ValidateWithContext
        m
        (WithTxHash (TestRunState RunningT))
acceptCommand tokenId wallet fact =
    signAndSubmitAnUpdate
        (`validateToRunningUpdate` ForUser)
        tokenId
        wallet
        fact
        $ Accepted (factValue fact)
