-- | Tests for "Geo.Distance" (Haversine).
--
-- The golden values below are exact consequences of the formula, so they also
-- cross-check against the Go @DistanceMeters@: one degree of latitude is
-- ~111.195 km anywhere on Earth.
module Geo.DistanceSpec (spec) where

import Test.Hspec
import Test.QuickCheck

import Geo.Distance (distanceMeters)
import Geo.Types (Coord (..))

-- | Assert two distances agree within @tol@ metres.
closeTo :: Double -> Double -> Double -> Expectation
closeTo tol expected actual =
  abs (expected - actual) `shouldSatisfy` (< tol)

spec :: Spec
spec = do
  describe "Geo.Distance.distanceMeters" $ do
    it "is zero between a point and itself" $
      distanceMeters (Coord 37.8 144.96) (Coord 37.8 144.96) `shouldSatisfy` (< 1e-6)

    it "is ~111195 m for one degree of latitude (golden vs Go)" $
      closeTo 1.0 111194.93 (distanceMeters (Coord 0 0) (Coord 1 0))

    it "is ~111195 m for one degree of longitude at the equator" $
      closeTo 1.0 111194.93 (distanceMeters (Coord 0 0) (Coord 0 1))

    it "is symmetric: d a b == d b a" $ property $
      \la lo lb lob ->
        let a = Coord la lo
            b = Coord lb lob
        in abs (distanceMeters a b - distanceMeters b a) < 1e-6
