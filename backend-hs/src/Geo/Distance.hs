-- | Haversine great-circle distance. Port of Go @geo/distance.go@.
--
-- Pure math — no IO. This is also A*'s admissible heuristic, so keep it exact
-- and fast. TDD target: match the Go @DistanceMeters@ results to a few metres.
module Geo.Distance
  ( distanceMeters
  ) where

import Geo.Types (Coord (..))

-- | Mean Earth radius in metres, matching the Go constant.
earthRadiusMeters :: Double
earthRadiusMeters = 6371000.0

-- | Great-circle distance between two coordinates, in metres.
--
-- TODO (Go @DistanceMeters@):
--   lat1 = a.lat in radians;  lat2 = b.lat in radians
--   dLat = (b.lat - a.lat) in radians;  dLon = (b.lon - a.lon) in radians
--   h = sin²(dLat/2) + cos lat1 * cos lat2 * sin²(dLon/2)
--   result = 2 * earthRadiusMeters * asin (sqrt h)
--
-- Degrees→radians: @x * pi / 180@. Consider a @where@ helper for it.
distanceMeters :: Coord -> Coord -> Double
distanceMeters = undefined
