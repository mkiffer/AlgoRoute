{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/api/overpass/tests/client_test.go@.
module Overpass.TypesSpec (spec) where

import Data.Aeson (decode, eitherDecode)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Geo.Types (Coord (..))
import Overpass.Types
  ( Element (..)
  , OsmNode (..)
  , OsmWay (..)
  , Response (..)
  , tagValue
  )
import Test.Hspec
import TestSupport (mustLoadFixture, shouldBeApprox)

spec :: Spec
spec = do
  describe "Overpass.Types FromJSON Element" $ do
    it "decodes a node into NodeElement with its coordinate" $ do
      -- The payoff of the sum type: matching NodeElement *gives* you a
      -- coordinate. Go's struct has *float64 fields that must be nil-checked at
      -- every use.
      let json = "{\"type\":\"node\",\"id\":42,\"lat\":-37.8,\"lon\":144.9}"
      case eitherDecode json of
        Right (NodeElement osmNode) -> do
          osmNode.nodeId `shouldBe` 42
          osmNode.coord.lat `shouldBeApprox` (-37.8)
          osmNode.coord.lon `shouldBeApprox` 144.9
        other -> expectationFailure ("expected a NodeElement, got " <> show other)

    it "decodes a way into WayElement with its node references" $ do
      let json = "{\"type\":\"way\",\"id\":7,\"nodes\":[1,2,3]}"
      case eitherDecode json of
        Right (WayElement way) -> do
          way.wayId `shouldBe` 7
          way.nodeRefs `shouldBe` [1, 2, 3]
        other -> expectationFailure ("expected a WayElement, got " <> show other)

    it "decodes tags into a map" $ do
      let json = "{\"type\":\"way\",\"id\":7,\"tags\":{\"highway\":\"residential\"}}"
      case eitherDecode json of
        Right (WayElement way) ->
          tagValue "highway" way.tags `shouldBe` Just "residential"
        other -> expectationFailure ("expected a WayElement, got " <> show other)

    it "defaults absent tags and node lists to empty" $ do
      -- Go's `omitempty` fields arrive as nil and every reader has to cope.
      -- Defaulting at the decode boundary means nothing downstream sees an
      -- absent map.
      let json = "{\"type\":\"way\",\"id\":7}"
      case eitherDecode json of
        Right (WayElement way) -> do
          way.tags `shouldBe` Map.empty
          way.nodeRefs `shouldBe` []
        other -> expectationFailure ("expected a WayElement, got " <> show other)

    it "tolerates an element type it does not use" $ do
      -- Overpass returns relations. Go's switch silently ignores them; failing
      -- the whole parse instead would be a regression, so they decode into
      -- OtherElement and are skipped downstream.
      let json = "{\"type\":\"relation\",\"id\":99}"
      decode json `shouldBe` Just (OtherElement "relation" 99)

    it "rejects a node with no coordinate" $ do
      -- A node without lat/lon is not a node. Go would decode it happily and
      -- fail much later, in the mapping layer, with a nil dereference guard.
      let json = "{\"type\":\"node\",\"id\":42}"
      (decode json :: Maybe Element) `shouldBe` Nothing

  describe "Overpass.Types FromJSON Response on the shared fixture" $ do
    it "splits elements into ways and an indexed node map" $ do
      -- Same fixture as backend/mapping/testdata/, so both suites are asserting
      -- against identical bytes.
      response <- mustLoadFixture
      length response.ways `shouldBe` 55
      Map.size response.nodesById `shouldBe` 260

    it "indexes nodes by their own ID" $ do
      response <- mustLoadFixture
      fmap (.nodeId) (Map.lookup 27347732 response.nodesById) `shouldBe` Just 27347732

    it "keeps every element in the order Overpass sent them" $ do
      response <- mustLoadFixture
      length response.elements `shouldBe` 55 + 260

    it "reads the top-level metadata" $ do
      response <- mustLoadFixture
      response.version `shouldBe` Just 0.6
      fmap (T.take 8) response.generator `shouldBe` Just "Overpass"

    it "reports a decode error rather than throwing on malformed JSON" $ do
      let broken = "{\"elements\": [" :: LBS.ByteString
      (eitherDecode broken :: Either String Response) `shouldSatisfy` isLeftResult
  where
    isLeftResult (Left _) = True
    isLeftResult _ = False
