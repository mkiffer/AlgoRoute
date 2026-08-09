{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/geo/tests/bbox_helpers_test.go@ and the @BBoxContains@ half
-- of @geo_test.go@.
module Geo.BBoxSpec (spec) where

import Geo.BBox (approxAreaKm2, contains, fromCoords)
import Geo.Types (BBox (..), Coord (..))
import Test.Hspec
import TestSupport (shouldBeApprox)

spec :: Spec
spec = do
  describe "Geo.BBox.contains" $ do
    let box = BBox {minLat = -38, minLon = 144, maxLat = -37, maxLon = 145}

    it "accepts a point inside the bounds" $
      contains box (Coord {lat = -37.5, lon = 144.5}) `shouldBe` True

    it "rejects a point outside the bounds" $
      contains box (Coord {lat = -36.0, lon = 144.5}) `shouldBe` False

    it "accepts a point exactly on the boundary" $
      -- Inclusive bounds, matching Go's >= / <=. A geocode landing exactly on
      -- the edge of the queried area must not be treated as outside it.
      contains box (Coord {lat = -38, lon = 144}) `shouldBe` True

  describe "Geo.BBox.fromCoords" $ do
    let a = Coord {lat = -37.9, lon = 145.1}
        b = Coord {lat = -37.8, lon = 145.2}

    it "contains both input points" $ do
      let box = fromCoords a b 0.01
      contains box a `shouldBe` True
      contains box b `shouldBe` True

    it "expands beyond both points by the padding" $ do
      let box = fromCoords a b 0.01
      box.minLat `shouldBeApprox` (-37.91)
      box.maxLat `shouldBeApprox` (-37.79)
      box.minLon `shouldBeApprox` 145.09
      box.maxLon `shouldBeApprox` 145.21

    it "with zero padding gives exactly the bounds of the inputs" $ do
      let box = fromCoords a b 0
      box.minLat `shouldBeApprox` (-37.9)
      box.maxLat `shouldBeApprox` (-37.8)
      box.minLon `shouldBeApprox` 145.1
      box.maxLon `shouldBeApprox` 145.2

    it "does not care which point is given first" $
      fromCoords a b 0.01 `shouldBe` fromCoords b a 0.01

  describe "Geo.BBox.approxAreaKm2" $ do
    it "gives ~111.32² km² for a one-degree box at the equator" $ do
      -- At the equator the cosine correction is 1, so the area is just
      -- (111.32)² ≈ 12,392 km².
      let box = BBox {minLat = 0, minLon = 0, maxLat = 1, maxLon = 1}
      approxAreaKm2 box `shouldSatisfy` \area -> abs (area - 12392) < 5

    it "flags a Melbourne-to-Geelong box as over the 500 km² limit" $ do
      -- The case the limit exists for: this box's Overpass response can exceed
      -- 100 MB. Same expectation as the Go test.
      let box = BBox {minLat = -38.2, minLon = 144.3, maxLat = -37.8, maxLon = 145.0}
      approxAreaKm2 box `shouldSatisfy` (> 500)

    it "gives a near-zero area for a tiny box" $ do
      let box = BBox {minLat = -37.8, minLon = 144.9, maxLat = -37.799, maxLon = 144.901}
      approxAreaKm2 box `shouldSatisfy` \area -> area > 0 && area < 1

    it "shrinks a box of fixed degree span as it moves toward the poles" $ do
      -- The cosine correction in action: the same one-degree square covers far
      -- less ground at 60° than at the equator.
      let equator = BBox {minLat = 0, minLon = 0, maxLat = 1, maxLon = 1}
          high = BBox {minLat = 59, minLon = 0, maxLat = 60, maxLon = 1}
      approxAreaKm2 high `shouldSatisfy` (< approxAreaKm2 equator)
