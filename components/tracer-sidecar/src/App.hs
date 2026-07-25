{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use when" #-}

module App
    ( main
    , tailJsonLinesFromTracerLogDir
    )
where

import Cardano.Antithesis.Sdk
    ( sometimesTracesDeclaration
    , sometimesTracesReached
    , writeSdkJsonl
    )
import Cardano.Antithesis.Sidecar
    ( initialStateIO
    , mkSpec
    , processMessageIO
    )
import Control.Concurrent
    ( modifyMVar_
    , newMVar
    , threadDelay
    )
import Control.Concurrent.Async (async, link)
import Control.Exception (SomeException, fromException, try)
import Control.Monad
    ( forM_
    , forever
    , guard
    , unless
    , when
    , (<=<)
    )
import Data.Aeson
    ( FromJSON
    , eitherDecode
    )
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as BL
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (isPrefixOf)
import Data.Maybe (isJust)
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time (UTCTime, defaultTimeLocale, parseTimeM)
import System.Directory
    ( listDirectory
    )
import System.IO.Error (isDoesNotExistError)
import System.Environment
    ( getArgs
    , getEnv
    , lookupEnv
    )
import System.FilePath
    ( takeFileName
    , (</>)
    )
import System.IO
    ( BufferMode (LineBuffering)
    , IOMode (..)
    , SeekMode (SeekFromEnd)
    , hIsEOF
    , hSeek
    , hSetBuffering
    , stdout
    , withFile
    )

-- main ------------------------------------------------------------------------

-- | Main: <program> <directory>
--  Processes existing .jsonl files and tails them for new entries.
main :: IO ()
main = do
    hSetBuffering stdout LineBuffering
    putStrLn "starting tracer-sidecar..."
    args <- getArgs
    dir <- case args of
        [d] -> return d
        _ -> error "Usage: <executable name> <directory>"

    (nPools :: Int) <- read <$> getEnv "POOLS"
    consumerHost <- fmap Text.pack <$> lookupEnv "AMARU_CONSUMER_HOST"

    writeSdkJsonl $ sometimesTracesDeclaration "find log files"

    let spec = mkSpec nPools consumerHost
    mvar <- newMVar =<< initialStateIO spec

    -- Each cardano-node process gets its own subdirectory under `dir` once it
    -- handshakes with cardano-tracer. Those subdirectories appear over time
    -- and may also appear *after* sidecar startup (e.g. slow-starting pool
    -- containers, or node restarts via fault injection). Scan in a loop,
    -- spawning a file-tailing watcher the first time we see each subdir.
    seenRef <- newIORef (Set.empty :: Set FilePath)
    sdkReachedRef <- newIORef False
    forever $ do
        esubs <- try (listDirectory dir)
        case esubs of
            -- Until cardano-tracer creates the log root, listDirectory fails
            -- with "does not exist". That is an expected startup race (and can
            -- recur when fault injection recreates the volume), so wait quietly
            -- rather than logging a misleading error each second.
            Left (e :: SomeException)
                | Just ioe <- fromException e
                , isDoesNotExistError ioe ->
                    pure ()
                | otherwise ->
                    putStrLn
                        $ "Error listing directory " <> dir <> ": " <> show e
            Right subs -> do
                seen <- readIORef seenRef
                let current = Set.fromList $ fmap (dir </>) subs
                    new = current `Set.difference` seen
                unless (null new) $ do
                    reached <- readIORef sdkReachedRef
                    unless reached $ do
                        writeSdkJsonl $ sometimesTracesReached "find log files"
                        writeIORef sdkReachedRef True
                    forM_ new $ \nodeDir -> do
                        putStrLn $ "Tailing node log dir: " <> nodeDir
                        link
                            =<< async
                                ( tailJsonLinesFromTracerLogDir
                                    True
                                    nodeDir
                                    (modifyMVar_ mvar . flip (processMessageIO spec))
                                )
                    writeIORef seenRef (seen <> new)
        threadDelay 1000000

-- | Tails json lines from each file in a directory,
-- one at a time respecting their lexical order
-- and waiting for new files to appear forever.
-- We rely on the invariant that the filename order reflects the order of arrival
-- in the directory
tailJsonLinesFromTracerLogDir
    :: FromJSON a
    => Bool
    -> FilePath -- directory to watch
    -> (a -> IO ()) -- action on each decoded log message
    -> IO ()
tailJsonLinesFromTracerLogDir skip dir action = go mempty
  where
    callback bs = case eitherDecode $ BL.fromStrict bs of
        Right msg -> action msg
        Left _e -> pure () -- ignore decode errors
    go
        :: Set FilePath
        -> IO ()
    go seen = do
        let sample = do
                newSet <- nodeLogFiles
                let newFiles = newSet `Set.difference` seen
                if null newFiles
                    then do
                        threadDelay 1000000
                        sample
                    else return newFiles
        newFiles <- sample
        forM_ newFiles $ \path -> link <=< async $ do
            putStrLn $ "Tailing file: " <> path
            exited <- try
                $ withFile path ReadMode
                $ \h -> do
                    hSetBuffering h LineBuffering
                    when skip
                        $ hSeek h SeekFromEnd 0
                    forever $ do
                        eof <- hIsEOF h
                        if eof
                            then do
                                threadDelay 10000
                            else do
                                l <- B8.hGetLine h
                                callback l
            case exited of
                Left (e :: SomeException) ->
                    putStrLn
                        $ "Error reading file "
                            <> path
                            <> ": "
                            <> show e
                Right _ -> print $ "Finished reading file: " <> path
        go (seen <> newFiles)
      where
        -- switch to unbuffered mode and follow new data

        nodeLogFiles :: IO (Set FilePath)
        nodeLogFiles = do
            entries <- fmap (dir </>) <$> listDirectory dir
            let logFiles = filter parsingNodeLogFile entries
            pure $ Set.fromList logFiles

parsingNodeLogFile :: FilePath -> Bool
parsingNodeLogFile path = isJust $ do
    let filename = takeFileName path
    guard $ isPrefixOf "node-" filename
    let timestamp = drop 5 $ takeWhile (/= '.') filename
    parseTimeM @_ @UTCTime
        True
        defaultTimeLocale
        "%Y-%m-%dT%H-%M-%S"
        timestamp
