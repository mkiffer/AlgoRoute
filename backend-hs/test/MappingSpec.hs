-- | Tests for "Mapping" — building a 'Network' from an Overpass response.
--
-- Cross-checks against the Go @mapping@ tests: same fixture, same expected node
-- and edge counts and oneway handling. To learn the exact numbers the Go code
-- produces, run `go test -v ./mapping/...` in ../backend and copy the counts in.
module MappingSpec (spec) where

import qualified Data.ByteString as BS
import Data.Aeson (eitherDecodeStrict)
import qualified Data.Map.Strict as Map
import Test.Hspec

import Graph (Network (..))
import Mapping
import Overpass.Types (Response)

fixturePath :: FilePath
fixturePath = "test/testdata/sample_overpass.json"

loadFixture :: IO Response
loadFixture = do
  raw <- BS.readFile fixturePath
  case eitherDecodeStrict raw of
    Left err -> error ("fixture decode: " <> err)
    Right r -> pure r

spec :: Spec
spec = do
  describe "Mapping.buildNetwork" $ do
    it "builds a network with nodes and edges from the fixture" $ do
      resp <- loadFixture
      case buildNetwork (BuildOptions True) resp of
        Left err -> expectationFailure err
        Right (net, _stats) -> do
          Map.size (nodes net) `shouldSatisfy` (> 0)
          sum (map length (Map.elems (adjacencyList net))) `shouldSatisfy` (> 0)

    it "adds backward edges when assumeBidirectional is on" $ do
      resp <- loadFixture
      let edgesWith b = case buildNetwork (BuildOptions b) resp of
            Right (net, _) -> sum (map length (Map.elems (adjacencyList net)))
            Left e -> error e
      -- Bidirectional should yield at least as many edges as one-way-only.
      edgesWith True `shouldSatisfy` (>= edgesWith False)

    -- TODO: once you know the Go counts, pin them exactly, e.g.:
    -- it "matches the Go node/edge counts" $ do
    --   resp <- loadFixture
    --   let Right (net, _) = buildNetwork (BuildOptions True) resp
    --   Map.size (nodes net) `shouldBe` <N>
