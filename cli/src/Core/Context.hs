{-# LANGUAGE DeriveFunctor #-}

module Core.Context
    ( WithContext
    , Context
    , withContext
    , askMpfs
    , askTestRunConfig
    , askAgentPKH
    , askValidation
    , askSubmit
    , withMPFS
    , askConfig
    ) where

import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Trans.Class (MonadTrans, lift)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Core.Types.Basic (Owner, TokenId)
import Core.Types.Fact (Fact (..), parseFacts)
import Core.Types.Wallet (Wallet)
import MPFS.API (MPFS (..))
import Oracle.Config.Types
    ( Config (configAgent, configTestRun)
    , ConfigKey
    )
import Oracle.Validate.Requests.TestRun.Config
    ( TestRunValidationConfig
    )
import Submitting (Submission)
import Validation (Validation)

-- it would be nice to modulate it a bit depending con the command but we do not
-- have a type for each command
data Context m = Context
    { ctxMPFS :: MPFS m
    , ctxMkValidation :: Maybe TokenId -> Validation m
    , ctxSubmit :: Wallet -> Submission m
    }

newtype WithContext m a = WithContext
    { _getWithContext :: ReaderT (Context m) m a
    }
    deriving (Functor, Applicative, Monad, MonadIO)

instance MonadTrans WithContext where
    lift = WithContext . lift

askMpfs :: Monad m => WithContext m (MPFS m)
askMpfs = ctxMPFS <$> WithContext ask

withMPFS :: Monad m => (MPFS m -> m a) -> WithContext m a
withMPFS f = do
    mpfs <- askMpfs
    lift $ f mpfs

withConfig
    :: Monad m => TokenId -> (Config -> a) -> WithContext m (Maybe a)
withConfig tokenId f = do
    mpfs <- askMpfs
    facts :: [Fact ConfigKey Config] <-
        fmap parseFacts
            $ lift
            $ mpfsGetTokenFacts mpfs tokenId
    pure $ case facts of
        [Fact _ c] -> Just $ f c
        _ -> Nothing

askConfig :: Monad m => TokenId -> WithContext m (Maybe Config)
askConfig tokenId = withConfig tokenId id

askTestRunConfig
    :: Monad m => TokenId -> WithContext m (Maybe TestRunValidationConfig)
askTestRunConfig tokenId = withConfig tokenId configTestRun

askAgentPKH :: Monad m => TokenId -> WithContext m (Maybe Owner)
askAgentPKH tokenId = withConfig tokenId configAgent

askValidation
    :: Monad m => Maybe TokenId -> WithContext m (Validation m)
askValidation tokenId = do
    ctx <- WithContext ask
    return $ ctxMkValidation ctx tokenId

askSubmit :: Monad m => Wallet -> WithContext m (Submission m)
askSubmit w = flip ctxSubmit w <$> WithContext ask

withContext
    :: MPFS m
    -> (MPFS m -> Maybe TokenId -> Validation m)
    -> (Wallet -> Submission m)
    -> WithContext m a
    -> m a
withContext mpfs mkValidation submit (WithContext action) =
    runReaderT
        action
        Context
            { ctxMPFS = mpfs
            , ctxMkValidation = mkValidation mpfs
            , ctxSubmit = submit
            }
