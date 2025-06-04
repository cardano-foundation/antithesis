{-# LANGUAGE OverloadedStrings     #-}


{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ScopedTypeVariables   #-}

module Main where

import           Cardano.Antithesis.LogMessage
import           Cardano.Antithesis.Sidecar

import qualified Data.ByteString.Char8         as B8
import qualified Data.ByteString.Lazy          as BL

import           Control.Concurrent            (forkIO, modifyMVar_, newMVar,
                                                threadDelay)
import           Control.Monad                 (filterM, forM, forM_, forever,
                                                unless)
import           Data.Aeson                    (eitherDecode)
import           System.Directory              (doesDirectoryExist,
                                                doesFileExist, listDirectory)
import           System.Environment            (getArgs, getEnv)
import           System.FilePath               (takeExtension, (</>))
import           System.IO                     (BufferMode (LineBuffering, NoBuffering),
                                                IOMode (ReadMode), hIsEOF,
                                                hSetBuffering, stdout, withFile)

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
             _   -> error "Usage: <executable name> <directory>"

    mvar <- newMVar =<< initialStateIO

    (nPools :: Int) <- read <$> getEnv "POOLS"

    files <- waitFor (\files -> length files == nPools) $ do
        threadDelay 2000000 -- allow log files to be created
        putStrLn $ "Looking for " <> show nPools <> " log files"
        jsonFiles dir

    putStrLn $ "Observing .json files: " <> show files

    forM_ files $ \file ->
      forkIO $ tailJsonLines file (modifyMVar_ mvar . flip processMessageIO)
    forever $ threadDelay maxBound
  where
    waitFor :: Monad m => (a -> Bool) -> m a -> m a
    waitFor cond act = do
        a <- act
        if cond a then return a else waitFor cond act

-- utils -----------------------------------------------------------------------

-- | Recursively find .json files in a directory
jsonFiles :: FilePath -> IO [FilePath]
jsonFiles dir = do
  entries <- listDirectory dir
  let paths = map (dir </>) entries

  files <- filterM doesFileExist paths
  dirs  <- filterM doesDirectoryExist paths

  let jsonHere = filter ((== ".json") . takeExtension) files
  jsonInSubDirs <- concat <$> forM dirs jsonFiles

  pure (jsonHere ++ jsonInSubDirs)

tailJsonLines :: FilePath -> (LogMessage -> IO ()) -> IO ()
tailJsonLines path action = tailLines path $ \bs ->
  case eitherDecode $ BL.fromStrict bs of
      Right msg -> action msg
      Left _e   -> pure () -- putStrLn $ "warning: unrecognized line: " <> B8.unpack bs <> " " <> show e

tailLines :: FilePath -> (B8.ByteString -> IO ()) -> IO ()
tailLines path callback = withFile path ReadMode $ \h -> do
    -- read up to current EOF without closing the handle
    let drain = do
          eof <- hIsEOF h
          unless eof $ B8.hGetLine h >>= callback >> drain
    drain

    -- switch to unbuffered mode and follow new data
    hSetBuffering h NoBuffering
    forever $ do
      eof <- hIsEOF h
      if eof
         then threadDelay 100000
         else B8.hGetLine h >>= callback
