module User.Agent.Lib
    ( resolveTestRunId
    ) where

import Core.Context (WithContext, withMPFS)
import Core.Types.Basic (TokenId)
import Core.Types.Fact (Fact (..), keyHash, parseFacts)
import Data.Foldable (find)
import MPFS.API (MPFS (..))
import Text.JSON.Canonical (FromJSON (..), JSValue)
import User.Agent.Types (TestRunId (..))
import User.Types (TestRun, TestRunState)

resolveTestRunId
    :: forall s m
     . (Monad m, FromJSON Maybe (TestRunState s))
    => TokenId
    -> TestRunId
    -> WithContext m (Maybe (Fact TestRun (TestRunState s)))
resolveTestRunId tk (TestRunId testRunId) = do
    facts <- fmap parseFacts
        $ withMPFS
        $ \mpfs -> mpfsGetTokenFacts mpfs tk
    let match :: Fact TestRun JSValue -> Bool
        match (Fact key _) = case keyHash key of
            Nothing -> False
            Just keyId -> keyId == testRunId
    pure $ find match facts >>= \(Fact k v) -> Fact k <$> fromJSON v
