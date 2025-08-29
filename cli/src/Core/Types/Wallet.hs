{-# LANGUAGE StrictData #-}

module Core.Types.Wallet
    ( Wallet (..)
    ) where

import Core.Types.Basic
import Core.Types.Tx

data Wallet = Wallet
    { address :: Address
    , owner :: Owner
    , sign :: UnsignedTx -> Either SignTxError SignedTx
    , encryptionState :: Bool
    }

instance Show Wallet where
    show (Wallet addr owner _ _) =
        "Wallet { address: " ++ show addr ++ ", owner: " ++ show owner ++ " }"

instance Eq Wallet where
    (Wallet addr1 owner1 _ _) == (Wallet addr2 owner2 _ _) =
        addr1 == addr2 && owner1 == owner2
