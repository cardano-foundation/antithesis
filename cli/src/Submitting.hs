{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use newtype instead of data" #-}

module Submitting
    ( Submission (..)
    , signAndSubmitMPFS
    , readWallet
    , walletFromMnemonic
    , writeWallet
    , Submitting (..)
    , IfToWait (..)
    , WalletError (..)
    )
where

import Cardano.Address (bech32)
import Cardano.Address.Derivation
    ( Depth (..)
    , deriveAccountPrivateKey
    , deriveAddressPrivateKey
    , genMasterKeyFromMnemonic
    , pubToBytes
    , xpubToPub
    )
import Cardano.Address.Style.Shelley
    ( Credential (PaymentFromExtendedKey)
    , Role (UTxOExternal)
    , Shelley
    , getKey
    , mkNetworkDiscriminant
    , paymentAddress
    )
import Cardano.Crypto.DSIGN.Class qualified as Crypto
import Cardano.Crypto.Hash (HashAlgorithm (..))
import Cardano.Crypto.Hash.Blake2b
import Cardano.Crypto.Util qualified as Crypto
import Cardano.Crypto.Wallet (XPrv)
import Cardano.Crypto.Wallet qualified as Crypto.HD
import Cardano.Ledger.Api
    ( ConwayEra
    , EraTx (Tx)
    , KeyRole (..)
    , WitVKey (..)
    , addrTxWitsL
    , eraProtVerLow
    , txIdTx
    , witsTxL
    )
import Cardano.Ledger.Api qualified as L
import Cardano.Ledger.Api.Tx.In (TxId (..))
import Cardano.Ledger.Binary
    ( DecCBOR (decCBOR)
    , DecoderError
    , decodeFullAnnotator
    )
import Cardano.Ledger.Binary.Encoding qualified as Ledger
import Cardano.Ledger.Core
    ( extractHash
    )
import Cardano.Ledger.Keys
    ( VKey (..)
    , asWitness
    )
import Cardano.Mnemonic (MkSomeMnemonic (mkSomeMnemonic))
import Control.Concurrent (threadDelay)
import Control.Exception (Exception, SomeException, throwIO)
import Control.Lens ((%~))
import Control.Monad (void)
import Control.Monad.Catch (MonadCatch (..))
import Control.Monad.IO.Class (MonadIO (..))
import Core.Encryption (encryptText)
import Core.Types.Basic (Address (..), Owner (..))
import Core.Types.Mnemonics
import Core.Types.Tx
    ( SignTxError (..)
    , SignedTx (..)
    , TxHash
    , UnsignedTx (..)
    , WithTxHash (WithTxHash)
    , WithUnsignedTx (..)
    )
import Core.Types.Wallet
    ( Wallet (..)
    )
import Data.Aeson
    ( encode
    )
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BL
import Data.Function ((&))
import Data.Maybe (fromMaybe)
import Data.Proxy
    ( Proxy (..)
    )
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as T
import MPFS.API (getTransaction, submitTransaction)
import Servant.Client (ClientM)
import Text.JSON.Canonical (JSValue (..))

data IfToWait = Wait Int | NoWait
    deriving (Show, Eq)

data Submitting = Submitting
    { ifToWait :: IfToWait
    , runClient :: forall a. ClientM a -> IO a
    }

newtype Submission m = Submission
    { submit
        :: forall a
         . (Address -> m (WithUnsignedTx a))
        -> m (WithTxHash a)
    }

waitTx :: Submitting -> TxHash -> IO ()
waitTx (Submitting (Wait maxCycles) runClient) txHash = void $ go maxCycles
  where
    go :: Int -> IO JSValue
    go 0 = pure JSNull
    go n =
        runClient (getTransaction txHash)
            `catch` \(_ :: SomeException) -> do
                liftIO $ threadDelay 1000000
                go (n - 1)
waitTx (Submitting NoWait _) _ = return ()

signAndSubmitMPFS
    :: Submitting
    -> Wallet
    -> Submission ClientM
signAndSubmitMPFS sbmt Wallet{address, sign} = Submission $ \action -> do
    WithUnsignedTx unsignedTx value <- action address
    case sign unsignedTx of
        Right (SignedTx signedTx) -> do
            txHash <- submitTransaction $ SignedTx signedTx
            liftIO $ waitTx sbmt txHash
            return $ WithTxHash txHash value
        Left e -> liftIO $ throwIO e

data WalletError
    = InvalidMnemonic String
    | InvalidWalletFile String
    deriving (Show, Eq)

instance Exception WalletError

readWallet
    :: (Bool , Mnemonics 'DecryptedS)
    -> Either WalletError Wallet
readWallet (encryptionState, ClearText mnemonics) = do
    walletFromMnemonic encryptionState $ T.words mnemonics

writeWallet :: FilePath -> [Text] -> Maybe Text -> IO ()
writeWallet walletFile mnemonicWords passphrase = do
    case passphrase of
        Just p -> do
            encrypted <- encryptText p 10 $ T.unwords mnemonicWords
            BL.writeFile walletFile $ encode $ Encrypted encrypted
        Nothing ->
            BL.writeFile walletFile
                $ encode
                $ ClearText
                $ T.unwords mnemonicWords

walletFromMnemonic :: Bool -> [Text] -> Either WalletError Wallet
walletFromMnemonic encryptionState mnemonicWords = do
    mnemonic <-
        either (Left . InvalidMnemonic . show) Right
            $ mkSomeMnemonic @'[9, 12, 15, 18, 24] mnemonicWords

    let
        rootXPrv96 :: Shelley 'RootK XPrv
        rootXPrv96 = genMasterKeyFromMnemonic mnemonic mempty

        accXPrv96 :: Shelley 'AccountK XPrv
        accXPrv96 = deriveAccountPrivateKey rootXPrv96 minBound

        addrXPrv96 :: Shelley 'PaymentK XPrv
        addrXPrv96 = deriveAddressPrivateKey accXPrv96 UTxOExternal minBound
        addrXPub64 = Crypto.HD.toXPub <$> addrXPrv96

        pubBytes32 = pubToBytes $ xpubToPub $ getKey addrXPub64
        tag = either (error . show) id $ mkNetworkDiscriminant 0
        addr =
            Address
                $ bech32
                $ paymentAddress tag
                $ PaymentFromExtendedKey addrXPub64
    pure
        $ Wallet
            { address = addr
            , sign = signTx $ getKey addrXPrv96
            , owner =
                Owner
                    $ BS.unpack
                    $ Base16.encode
                    $ digest (Proxy @Blake2b_224) pubBytes32
            , encryptionState
            }

signTx :: XPrv -> UnsignedTx -> Either SignTxError SignedTx
signTx xprv (UnsignedTx unsignedHex) = do
    rawBytes <- unhex unsignedHex
    tx <- first (const InvalidTx) (deserializeTx rawBytes)

    let signedLedgerTx = signLedgerTx xprv tx

    pure $ SignedTx $ hex $ serializeTx signedLedgerTx
  where
    hex :: ByteString -> Text
    hex = T.decodeUtf8 . Base16.encode

    unhex :: Text -> Either SignTxError ByteString
    unhex = first (const InvalidHex) . Base16.decode . T.encodeUtf8

serializeTx
    :: Tx ConwayEra
    -> ByteString
serializeTx = BL.toStrict . Ledger.serialize (eraProtVerLow @ConwayEra)

deserializeTx
    :: ByteString
    -> Either DecoderError (Tx ConwayEra)
deserializeTx
    bytes = case decodeFullAnnotator
        (eraProtVerLow @ConwayEra)
        "ConwayTx"
        decCBOR
        $ BL.fromStrict bytes of
        Left err -> error $ "Failed to decode full CBOR: " ++ show err
        Right tx' -> Right tx'

signLedgerTx :: XPrv -> L.Tx L.ConwayEra -> L.Tx L.ConwayEra
signLedgerTx xprv tx =
    addKeyWitnesses tx
        $ Set.fromList
            [ mkKeyWitness (txIdTx tx) xprv
            ]

mkKeyWitness :: TxId -> XPrv -> WitVKey 'Witness
mkKeyWitness (TxId hash) xprv =
    WitVKey
        (getShelleyKeyWitnessVerificationKey xprv)
        ( fromXSignature
            $ Crypto.HD.sign
                BS.empty -- passphrase for (unused) in-memory encryption
                xprv
                (Crypto.getSignableRepresentation $ extractHash hash)
        )
  where
    fromXSignature =
        Crypto.SignedDSIGN
            . fromMaybe (error "impossible: rawDeserialiseSigDSIGN failed")
            . Crypto.rawDeserialiseSigDSIGN
            . Crypto.HD.unXSignature

    getShelleyKeyWitnessVerificationKey
        :: XPrv
        -> VKey Witness
    getShelleyKeyWitnessVerificationKey = asWitness . convert . Crypto.HD.toXPub
      where
        convert =
            VKey
                . fromMaybe impossible
                . Crypto.rawDeserialiseVerKeyDSIGN
                . Crypto.HD.xpubPublicKey
          where
            impossible =
                error "rawDeserialiseVerKeyDSIGN failed converting XPub"

addKeyWitnesses
    :: EraTx era => Tx era -> Set (WitVKey 'Witness) -> Tx era
addKeyWitnesses tx newWits = tx & witsTxL . addrTxWitsL %~ Set.union newWits
