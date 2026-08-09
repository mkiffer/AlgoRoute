{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/api/overpass/tests/fetch_test.go@.
module Overpass.ClientSpec (spec) where

import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Geo.Types (BBox (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (status500)
import Overpass.Client
  ( OverpassError (..)
  , buildQuery
  , driveableHighwayTypes
  , fetchFromAPI
  , loadFromFile
  , maxResponseBytes
  )
import Overpass.Types (Response (..))
import Test.Hspec
import TestSupport
  ( fixturePath
  , jsonResponse
  , mustRight
  , statusResponse
  , withStubUpstream
  )

melbourneBox :: BBox
melbourneBox = BBox {minLat = -37.9, minLon = 145.09, maxLat = -37.88, maxLon = 145.11}

spec :: Spec
spec = do
  describe "Overpass.Client.buildQuery" $ do
    it "filters on the driveable highway types" $ do
      let query = buildQuery melbourneBox
      T.unpack query `shouldContain` T.unpack driveableHighwayTypes
      T.unpack query `shouldContain` "[\"highway\"~"

    it "renders the bbox as south,west,north,east with six decimals" $ do
      -- Overpass takes latitude first, unlike almost every other geo API.
      -- Getting the order wrong returns an empty result rather than an error,
      -- which is a miserable thing to debug — hence a test.
      let query = buildQuery melbourneBox
      T.unpack query
        `shouldContain` "-37.900000,145.090000,-37.880000,145.110000"

    it "requests JSON output and pulls in referenced nodes" $ do
      -- Without `>;` the response contains ways but no coordinates, and Mapping
      -- silently builds an empty network.
      let query = buildQuery melbourneBox
      T.unpack query `shouldContain` "[out:json]"
      T.unpack query `shouldContain` ">;"
      T.unpack query `shouldContain` "out body;"

    it "produces the same string for the same box" $
      buildQuery melbourneBox `shouldBe` buildQuery melbourneBox

  describe "Overpass.Client.loadFromFile" $ do
    it "loads and indexes the fixture" $ do
      response <- loadFromFile fixturePath >>= mustRight
      length response.ways `shouldBe` 55
      Map.size response.nodesById `shouldBe` 260

    it "reports a read failure for a missing file" $ do
      result <- loadFromFile "test/testdata/does-not-exist.json"
      case result of
        Left (FileReadFailed _) -> pure ()
        other -> expectationFailure ("expected FileReadFailed, got " <> show other)

  describe "Overpass.Client.fetchFromAPI" $ do
    it "decodes a successful response" $ do
      manager <- newManager defaultManagerSettings
      body <- LBS.readFile fixturePath
      withStubUpstream (jsonResponse body) $ \baseUrl -> do
        response <- fetchFromAPI manager baseUrl melbourneBox >>= mustRight
        length response.ways `shouldBe` 55
        Map.size response.nodesById `shouldBe` 260

    it "rejects a response larger than the 10 MB cap" $ do
      -- The guard that stands between a Melbourne-to-Geelong query and an
      -- out-of-memory kill. The body is valid JSON, so only the size check can
      -- reject it.
      manager <- newManager defaultManagerSettings
      let oversized =
            "{\"elements\":[" <> LBS.replicate (fromIntegral maxResponseBytes) 32 <> "]}"
      withStubUpstream (jsonResponse oversized) $ \baseUrl -> do
        result <- fetchFromAPI manager baseUrl melbourneBox
        result `shouldBe` Left ResponseTooLarge

    it "reports a non-200 status" $ do
      manager <- newManager defaultManagerSettings
      withStubUpstream (statusResponse status500 "upstream is unwell") $ \baseUrl -> do
        result <- fetchFromAPI manager baseUrl melbourneBox
        result `shouldBe` Left (BadStatus 500)

    it "reports a decode failure for a non-JSON body" $ do
      manager <- newManager defaultManagerSettings
      withStubUpstream (jsonResponse "not json at all") $ \baseUrl -> do
        result <- fetchFromAPI manager baseUrl melbourneBox
        case result of
          Left (DecodeFailed _) -> pure ()
          other -> expectationFailure ("expected DecodeFailed, got " <> show other)

    it "reports a request failure when nothing is listening" $ do
      manager <- newManager defaultManagerSettings
      -- Port 1 is reserved and nothing will be bound to it.
      result <- fetchFromAPI manager "http://127.0.0.1:1" melbourneBox
      case result of
        Left (RequestFailed _) -> pure ()
        other -> expectationFailure ("expected RequestFailed, got " <> show other)
