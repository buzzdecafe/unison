module Unison.Test.KeyValueStore where

import Data.ByteString.Char8
import System.Random
import Test.Tasty
import Test.Tasty.HUnit
import Unison.Hash (Hash)
import qualified Control.Concurrent.MVar as MVar
import qualified Unison.Runtime.KeyValueStore as KVS

makeRandomHash :: RandomGen r => MVar.MVar r -> IO Hash
makeRandomHash genVar = do
  gen <- MVar.readMVar genVar
  let (hash, newGen) = random gen
  MVar.swapMVar genVar newGen
  pure hash

roundTrip :: RandomGen r => MVar.MVar r -> Assertion
roundTrip genVar = do
  hash <- makeRandomHash genVar
  db <- KVS.load hash
  KVS.insert (pack "keyhash") (pack "key", pack "value") db
  KVS.close db
  db2 <- KVS.load hash
  result <- KVS.lookup (pack "keyhash") db2
  case result of
    Just v | unpack v == "value" -> pure ()
    Just v -> fail ("expected value, got " ++ unpack v)
    _ -> fail "got nothin"
  KVS.cleanup db2

nextKeyAfterRemoval :: RandomGen r => MVar.MVar r -> Assertion
nextKeyAfterRemoval genVar = do
  hash <- makeRandomHash genVar
  db <- KVS.load hash
  KVS.insert (pack "1") (pack "k1", pack "v1") db
  KVS.insert (pack "2") (pack "k2", pack "v2") db
  KVS.insert (pack "3") (pack "k3", pack "v3") db
  KVS.insert (pack "4") (pack "k4", pack "v4") db
  KVS.delete (pack "2") db
  result <- KVS.lookupGT (pack "1") db
  case result of
    Just (kh, (k, v)) | unpack kh == "3" -> pure ()
    Just (kh, (k, v)) -> fail ("expected key 3, got " ++ unpack kh)
    Nothing -> fail "got nothin"
  KVS.cleanup db

ioTests :: IO TestTree
ioTests = do
  gen <- getStdGen
  genVar <- MVar.newMVar gen
  pure $ testGroup "KeyValueStore"
    [ testCase "roundTrip" (roundTrip genVar)
    , testCase "nextKeyAfterRemoval" (nextKeyAfterRemoval genVar)
    ]

main = ioTests >>= defaultMain
