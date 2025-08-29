module Core.Types.Mnemonics.Options
    ( mnemonicsParser
    , walletPassphraseCommon
    , walletFileOption
    , queryConsole
    ) where

import Control.Exception (try)
import Core.Encryption (decryptText)
import Core.Types.Mnemonics (Mnemonics (..), MnemonicsPhase (..))
import Data.Aeson
    ( Object
    )
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as BL
import Data.Functor (($>))
import Data.Text (Text)
import Data.Text qualified as T
import OptEnvConf
    ( Alternative ((<|>))
    , Parser
    , checkEither
    , checkMapIO
    , conf
    , env
    , help
    , long
    , mapIO
    , metavar
    , option
    , reader
    , setting
    , short
    , str
    , switch
    , withConfig
    )
import System.Console.Haskeline

mnemonicsClearTextOption :: Parser Text
mnemonicsClearTextOption =
    setting
        [ help "The mnemonics for the wallet in clear text"
        , conf "mnemonics"
        , metavar "MNEMONICS"
        ]

mnemonicsEncryptedOption :: Parser Text
mnemonicsEncryptedOption =
    setting
        [ help "The encrypted mnemonics for the wallet"
        , conf "encryptedMnemonics"
        , metavar "ENCRYPTED_MNEMONICS"
        ]

walletPassphraseCommon :: Parser Text
walletPassphraseCommon =
    mapIO id
        $ setting
            [ help "Prompt for the passphrase for the encrypted mnemonics"
            , env "ANTI_INTERACTIVE_SECRETS"
            , metavar "NONE"
            , reader
                $ str @String $> queryConsole "Enter passphrase for encrypted mnemonics"
            ]
        <|> setting
            [ help "Prompt for the passphrase for the encrypted mnemonics"
            , metavar "NONE"
            , long "ask-wallet-passphrase"
            , switch
                $ queryConsole "Enter passphrase for encrypted mnemonics"
            ]
        <|> setting
            [ env "ANTI_WALLET_PASSPHRASE"
            , metavar "PASSPHRASE"
            , help "The passphrase for the encrypted mnemonics"
            , reader $ fmap (pure . T.pack) str
            ]

queryConsole :: String -> IO Text
queryConsole prompt = runInputT defaultSettings $ do
    pw <- getPassword (Just '*') (prompt <> ": ")
    case pw of
        Nothing -> pure ""
        Just pw' -> pure $ T.pack pw'

walletFileOption :: Parser FilePath
walletFileOption =
    setting
        [ env "ANTI_WALLET_FILE"
        , metavar "FILEPATH"
        , help "The file path to the wallet secret mnemonics"
        , long "wallet"
        , short 'w'
        , reader str
        , option
        ]

coreMnemonicsParser :: Parser (Bool, Mnemonics 'DecryptedS)
coreMnemonicsParser =
         (False ,) . ClearText <$> mnemonicsClearTextOption
        <|> (True ,) . ClearText <$> checkEither
            id
            (decryptText <$> walletPassphraseCommon <*> mnemonicsEncryptedOption)

readJSONFile :: FilePath -> IO (Either String Object)
readJSONFile fp = do
    econtent <- try $ BL.readFile fp
    case econtent of
        Left (e :: IOError) -> return $ Left $ show e
        Right content -> return $ Aeson.eitherDecode content

mnemonicsObject :: Parser Object
mnemonicsObject = checkMapIO readJSONFile walletFileOption

mnemonicsParser :: Parser (Bool, Mnemonics 'DecryptedS )
mnemonicsParser = withConfig (Just <$> mnemonicsObject) coreMnemonicsParser
