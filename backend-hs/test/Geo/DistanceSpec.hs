-- | Ports @backend/geo/tests/geo_test.go@ (the distance half).
module Geo.DistanceSpec (spec) where

import Geo.Distance (distanceMeters)
import Geo.Types (Coord (..))
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Property, (===))
import TestSupport (shouldBeApprox)

spec :: Spec
spec = describe "Geo.Distance.distanceMeters" $ do
  it "is zero for a point and itself" $
    distanceMeters melbourne melbourne `shouldBeApprox` 0

  it "matches the known length of one degree of longitude at the equator" $ do
    -- One degree of longitude at the equator is ~111.19 km on a sphere of
    -- radius 6,371 km. Same expectation and tolerance as the Go test.
    let measured = distanceMeters (Coord 0 0) (Coord 0 1)
    measured `shouldSatisfy` \d -> abs (d - 111195) < 100

  it "is symmetric for a fixed pair" $
    distanceMeters melbourne sydney `shouldBeApprox` distanceMeters sydney melbourne

  -- A property rather than an example, because symmetry is a claim about
  -- *every* pair of coordinates and Haversine's structure makes it easy to
  -- break asymmetrically (swap a `b.lat - a.lat` for `a.lat - b.lat` in the
  -- wrong place and the examples above still pass).
  prop "is symmetric for all coordinate pairs" propSymmetric

  it "grows with separation" $ do
    let near = distanceMeters melbourne (Coord (-37.82) 144.98)
        far = distanceMeters melbourne sydney
    near `shouldSatisfy` (< far)
  where
    melbourne = Coord {lat = -37.8136, lon = 144.9631}
    sydney = Coord {lat = -33.8688, lon = 151.2093}

-- | Haversine must give the same answer whichever endpoint comes first.
--
-- Coordinates are constrained to valid ranges: QuickCheck would otherwise
-- generate a latitude of 4,000°, which is not a coordinate and tells us nothing.
propSymmetric :: Double -> Double -> Double -> Double -> Property
propSymmetric a b c d =
  distanceMeters one two === distanceMeters two one
  where
    one = Coord {lat = clamp 90 a, lon = clamp 180 b}
    two = Coord {lat = clamp 90 c, lon = clamp 180 d}
    clamp limit value = max (-limit) (min limit value)
