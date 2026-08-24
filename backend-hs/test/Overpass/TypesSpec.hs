-- | Tests for "Overpass.Types" — the hand-written 'FromJSON' and 'mkResponse'.
--
-- Parses the shared fixture copied from the Go tests
-- (@test/testdata/sample_overpass.json@) and checks the derived indexes. Run:
--
--   cabal test --test-options='--match "Overpass"'
module Overpass.TypesSpec (spec) where

import qualified Data.ByteString as BS
import Data.Aeson (eitherDecodeStrict)
import qualified Data.Map.Strict as Map
import Test.Hspec

import Overpass.Types

fixturePath :: FilePath
fixturePath = "test/testdata/sample_overpass.json"

spec :: Spec
spec = do
  describe "Overpass.Types FromJSON" $ do
    it "parses the sample fixture without error" $ do
      raw <- BS.readFile fixturePath
      case eitherDecodeStrict raw :: Either String Response of
        Left err -> expectationFailure ("decode failed: " <> err)
        Right _ -> pure ()

    it "populates ways and the node index (mkResponse)" $ do
      raw <- BS.readFile fixturePath
      case eitherDecodeStrict raw :: Either String Response of
        Left err -> expectationFailure err
        Right resp -> do
          -- The fixture contains at least one way and several nodes.
          length (ways resp) `shouldSatisfy` (> 0)
          Map.size (nodeById resp) `shouldSatisfy` (> 0)

    it "classifies each way as a WayElement with node ids" $ do
      raw <- BS.readFile fixturePath
      case eitherDecodeStrict raw :: Either String Response of
        Left err -> expectationFailure err
        Right resp ->
          let isWay WayElement{} = True
              isWay _ = False
          in all isWay (ways resp) `shouldBe` True
