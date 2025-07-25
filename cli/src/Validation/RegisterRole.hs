{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Validation.RegisterRole
    ( RepositoryRoleFailure (..)
    , inspectRepoRoleForUserTemplate
    , inspectRepoRoleForUser
    , renderRepositoryRoleFailure
    ) where

import Core.Types.Basic (Repository, Username (..))
import Data.List qualified as L
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Lib.GitHub (githubGetCodeOwnersFile)

data RepositoryRoleFailure
    = NoRoleEntryInCodeowners
    | NoUsersAssignedToRoleInCodeowners
    | NoUserInCodeowners
    deriving (Eq, Show)

renderRepositoryRoleFailure :: RepositoryRoleFailure -> String
renderRepositoryRoleFailure = \case
    NoRoleEntryInCodeowners -> "CODEOWNERS in the repository does not contain the role entry."
    NoUsersAssignedToRoleInCodeowners ->
        "CODEOWNERS in the repository does not contain any users assigned to the role."
    NoUserInCodeowners -> "CODEOWNERS in the repository does not contain the user."

-- In order to verify the role of the userX CODEOWNERS file is downloaded with
-- the expectation there a line:
-- role: user1 user2 .. userX .. userN
analyzeResponseCodeownersFile
    :: Username -> Text -> Maybe RepositoryRoleFailure
analyzeResponseCodeownersFile (Username user) file
    | null lineWithRole = Just NoRoleEntryInCodeowners
    | users == [Nothing] = Just NoUsersAssignedToRoleInCodeowners
    | foundUser == [[]] = Just NoUserInCodeowners
    | otherwise = Nothing
  where
    fileLines = T.lines file
    strBS = "antithesis"
    lineWithRole = L.filter (T.isPrefixOf strBS) fileLines
    colon = "antithesis" <> ": "
    getUsersWithRole = T.stripPrefix colon
    users =
        getUsersWithRole
            <$> L.take 1 lineWithRole
    foundUser =
        L.filter (== ("@" <> T.pack user)) . T.words
            <$> catMaybes users

inspectRepoRoleForUserTemplate
    :: Username
    -> Repository
    -> (Repository -> IO Text)
    -> IO (Maybe RepositoryRoleFailure)
inspectRepoRoleForUserTemplate username repo downloadCodeownersFile = do
    resp <- downloadCodeownersFile repo
    pure $ analyzeResponseCodeownersFile username resp

inspectRepoRoleForUser
    :: Username
    -> Repository
    -> IO (Maybe RepositoryRoleFailure)
inspectRepoRoleForUser username repo =
    inspectRepoRoleForUserTemplate
        username
        repo
        githubGetCodeOwnersFile
