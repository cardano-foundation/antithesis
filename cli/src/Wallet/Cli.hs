{-# LANGUAGE OverloadedRecordDot #-}

module Wallet.Cli
    ( walletCmd
    , WalletCommand (..)
    ) where

import Control.Monad (replicateM)
import Core.Types.Basic (Address, Owner)
import Core.Types.Wallet (Wallet (..))
import Data.Text (Text)
import Lib.JSON.Canonical.Extra (object, (.=))
import Submitting (walletFromMnemonic, writeWallet)
import System.Random (randomRIO)
import Text.JSON.Canonical (JSValue (JSString), ToJSON (..))
import Words (englishWords)

data WalletError
    = WalletPresent
    | WalletMissing

instance Applicative m => ToJSON m WalletError where
    toJSON WalletPresent = pure $ JSString "Wallet is present"
    toJSON WalletMissing = pure $ JSString "Wallet is missing"

instance (ToJSON m a, Monad m) => ToJSON m (Either WalletError a) where
    toJSON (Right a) = toJSON a
    toJSON (Left e) = object ["error" .= e]

data WalletInfo = WalletInfo
    { address :: Address
    , owner :: Owner
    }

instance Monad m => ToJSON m WalletInfo where
    toJSON WalletInfo{address, owner} =
        object
            [ "address" .= address
            , "owner" .= owner
            ]

data WalletCommand a where
    Info
        :: Wallet -> WalletCommand (Either WalletError WalletInfo)
    Create
        :: FilePath
        -> Maybe Text
        -> WalletCommand (Either WalletError WalletInfo)
    Decrypt :: Wallet -> FilePath -> WalletCommand (Either WalletError WalletInfo)
    Encrypt :: Wallet -> FilePath -> Text -> WalletCommand (Either WalletError WalletInfo)

deriving instance Show (WalletCommand a)
deriving instance Eq (WalletCommand a)

walletCmd :: WalletCommand a -> IO a
walletCmd (Info wallet) =
    pure
        $ Right
        $ WalletInfo
            { address = wallet.address
            , owner = wallet.owner
            }
walletCmd (Create walletFile passphrase) = do
    w12 <- replicateM 12 $ element englishWords
    case walletFromMnemonic w12 of
        Left _e -> walletCmd (Create walletFile passphrase)
        Right wallet -> do
            writeWallet walletFile w12 passphrase
            return
                $ Right
                $ WalletInfo
                    { address = wallet.address
                    , owner = wallet.owner
                    }

element :: [a] -> IO a
element xs = do
    idx <- randomRIO (0, length xs - 1)
    return $ xs !! idx
