{-# LANGUAGE StrictData #-}

module Oracle.Types
    ( Request (..)
    , Token (..)
    , TokenState (..)
    , RequestZoo (..)
    , requestZooRefId
    , RequestValidationFailure (..)
    , renderRequestValidationFailure
    ) where

import Control.Applicative (Alternative, (<|>))
import Core.Types.Basic (Owner, RequestRefId)
import Core.Types.Change (Change (..))
import Core.Types.Operation (Op (..), Operation (..))
import Core.Types.Tx (Root)
import Lib.JSON.Canonical.Extra (object, withObject, (.:), (.=))
import Oracle.Validate.Requests.RegisterRole
    ( RegisterRoleFailure (..)
    , UnregisterRoleFailure (..)
    , renderRegisterRoleFailure
    , renderUnregisterRoleFailure
    )
import Oracle.Validate.Requests.RegisterUser
    ( RegisterUserFailure (..)
    , UnregisterUserFailure (..)
    , renderRegisterUserFailure
    , renderUnregisterUserFailure
    )
import Oracle.Validate.Requests.TestRun.Create
    ( CreateTestRunFailure (..)
    , renderCreateTestRunFailure
    )
import Oracle.Validate.Requests.TestRun.Update
    ( UpdateTestRunFailure (..)
    , renderUpdateTestRunFailure
    )
import Text.JSON.Canonical
    ( FromJSON (..)
    , ReportSchemaErrors
    , ToJSON (..)
    )
import User.Types
    ( Phase (..)
    , RegisterRoleKey
    , RegisterUserKey
    , TestRun
    , TestRunState
    )

data Request k op = Request
    { outputRefId :: RequestRefId
    , owner :: Owner
    , change :: Change k op
    }

deriving instance (Show k, Show (Operation op)) => Show (Request k op)
deriving instance (Eq k, Eq (Operation op)) => Eq (Request k op)

instance
    (Monad m, ToJSON m k, ToJSON m (Operation op))
    => ToJSON m (Request k op)
    where
    toJSON (Request refId owner change) =
        object
            [ "outputRefId" .= refId
            , "owner" .= owner
            , "change" .= change
            ]

instance
    (ReportSchemaErrors m, FromJSON m k, FromJSON m (Operation op))
    => FromJSON m (Request k op)
    where
    fromJSON = withObject "Request" $ \v -> do
        refId <- v .: "outputRefId"
        owner <- v .: "owner"
        change <- v .: "change"
        pure
            $ Request
                { outputRefId = refId
                , owner = owner
                , change = change
                }

data TokenState = TokenState
    { tokenRoot :: Root
    , tokenOwner :: Owner
    }

instance Monad m => ToJSON m TokenState where
    toJSON (TokenState root owner) =
        object
            [ "root" .= root
            , "owner" .= owner
            ]

instance ReportSchemaErrors m => FromJSON m TokenState where
    fromJSON = withObject "TokenState" $ \v -> do
        root <- v .: "root"
        owner <- v .: "owner"
        pure $ TokenState{tokenRoot = root, tokenOwner = owner}

data RequestZoo where
    RegisterUserRequest
        :: Request RegisterUserKey (OpI ()) -> RequestZoo
    UnregisterUserRequest
        :: Request RegisterUserKey (OpD ()) -> RequestZoo
    RegisterRoleRequest
        :: Request RegisterRoleKey (OpI ()) -> RequestZoo
    UnregisterRoleRequest
        :: Request RegisterRoleKey (OpD ()) -> RequestZoo
    CreateTestRequest
        :: Request TestRun (OpI (TestRunState PendingT)) -> RequestZoo
    RejectRequest
        :: Request TestRun (OpU (TestRunState PendingT) (TestRunState DoneT))
        -> RequestZoo
    AcceptRequest
        :: Request TestRun (OpU (TestRunState PendingT) (TestRunState RunningT))
        -> RequestZoo
    FinishedRequest
        :: Request TestRun (OpU (TestRunState RunningT) (TestRunState DoneT))
        -> RequestZoo

requestZooRefId :: RequestZoo -> RequestRefId
requestZooRefId (RegisterUserRequest req) = outputRefId req
requestZooRefId (UnregisterUserRequest req) = outputRefId req
requestZooRefId (RegisterRoleRequest req) = outputRefId req
requestZooRefId (UnregisterRoleRequest req) = outputRefId req
requestZooRefId (CreateTestRequest req) = outputRefId req
requestZooRefId (RejectRequest req) = outputRefId req
requestZooRefId (AcceptRequest req) = outputRefId req
requestZooRefId (FinishedRequest req) = outputRefId req

instance (Alternative m, ReportSchemaErrors m) => FromJSON m RequestZoo where
    fromJSON v = do
        (RegisterUserRequest <$> fromJSON v)
            <|> (UnregisterUserRequest <$> fromJSON v)
            <|> (RegisterRoleRequest <$> fromJSON v)
            <|> (UnregisterRoleRequest <$> fromJSON v)
            <|> (CreateTestRequest <$> fromJSON v)
            <|> (RejectRequest <$> fromJSON v)
            <|> (AcceptRequest <$> fromJSON v)
            <|> (FinishedRequest <$> fromJSON v)

instance Monad m => ToJSON m RequestZoo where
    toJSON (RegisterUserRequest req) = toJSON req
    toJSON (UnregisterUserRequest req) = toJSON req
    toJSON (RegisterRoleRequest req) = toJSON req
    toJSON (UnregisterRoleRequest req) = toJSON req
    toJSON (CreateTestRequest req) = toJSON req
    toJSON (RejectRequest req) = toJSON req
    toJSON (AcceptRequest req) = toJSON req
    toJSON (FinishedRequest req) = toJSON req

data Token = Token
    { tokenRefId :: RequestRefId
    , tokenState :: TokenState
    , tokenRequests :: [RequestZoo]
    }

instance Monad m => ToJSON m Token where
    toJSON (Token refId state requests) =
        object
            [ "outputRefId" .= refId
            , "state" .= state
            , "requests" .= requests
            ]

instance
    (Alternative m, ReportSchemaErrors m)
    => FromJSON m Token
    where
    fromJSON = withObject "Token" $ \v -> do
        refId <- v .: "outputRefId"
        state <- v .: "state"
        requests <- v .: "requests"
        pure
            $ Token
                { tokenRefId = refId
                , tokenState = state
                , tokenRequests = requests
                }

data RequestValidationFailure
    = RegisterUserFailure RegisterUserFailure
    | UnregisterUserFailure UnregisterUserFailure
    | RegisterRoleFailure RegisterRoleFailure
    | UnregisterRoleFailure UnregisterRoleFailure
    | CreateTestRunFailure CreateTestRunFailure
    | UpdateTestRunFailure UpdateTestRunFailure
    deriving (Eq, Show)

instance Monad m => ToJSON m RequestValidationFailure where
    toJSON = \case
        RegisterUserFailure failure ->
            object ["RegisterUserFailure" .= failure]
        UnregisterUserFailure failure ->
            object ["UnregisterUserFailure" .= failure]
        RegisterRoleFailure failure ->
            object ["RegisterRoleFailure" .= failure]
        UnregisterRoleFailure failure ->
            object ["UnregisterRoleFailure" .= failure]
        CreateTestRunFailure failure ->
            object ["CreateTestRunFailure" .= failure]
        UpdateTestRunFailure failure ->
            object ["UpdateTestRunFailure" .= failure]

renderRequestValidationFailure
    :: RequestValidationFailure -> String
renderRequestValidationFailure = \case
    RegisterUserFailure failure ->
        "Register User Failure: "
            ++ renderRegisterUserFailure failure
    UnregisterUserFailure failure ->
        "Unregister User Failure: "
            ++ renderUnregisterUserFailure failure
    RegisterRoleFailure failure ->
        "Register Role Failure: "
            ++ renderRegisterRoleFailure failure
    UnregisterRoleFailure failure ->
        "Unregister Role Failure: "
            ++ renderUnregisterRoleFailure failure
    CreateTestRunFailure failure ->
        "Create Test Run Failure: "
            ++ renderCreateTestRunFailure failure
    UpdateTestRunFailure failure ->
        "Update Test Run Failure: "
            ++ renderUpdateTestRunFailure failure
