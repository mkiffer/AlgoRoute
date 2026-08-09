{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.Distance
-- Description : Great-circle distance between two coordinates (Haversine).
--
-- Ports @backend/geo/distance.go@ exactly — same formula, same Earth radius,
-- so the two backends produce byte-identical distances for the same input.
module Geo.Distance
  ( distanceMeters
  , earthRadiusMeters
  ) where

import Geo.Types (Coord (..))

-- | Mean Earth radius in metres, as used by the Go backend.
--
-- This is the spherical approximation. The Earth is an oblate spheroid, so
-- Haversine carries up to ~0.5% error versus a geodesic method like Vincenty.
-- For road routing that is irrelevant: the error is far smaller than the
-- difference between straight-line distance and the actual road geometry we
-- are approximating anyway.
earthRadiusMeters :: Double
earthRadiusMeters = 6371000.0

-- | Great-circle distance between two coordinates, in metres.
--
-- This function is /pure/ in the strong Haskell sense: its type contains no
-- @IO@, so the compiler guarantees it cannot read a clock, hit the network, or
-- mutate anything. That guarantee is what lets "Routefinding.AStar" call it
-- inside a tight search loop without any thought about ordering or effects.
--
-- The formula, unchanged from the Go source:
--
-- > a = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)
-- > d = 2 · R · asin(√a)
--
-- Using @asin(sqrt a)@ rather than @atan2(sqrt a, sqrt (1-a))@ matches Go
-- line-for-line. Both are numerically well behaved for the sub-100 km
-- distances this backend deals with.
distanceMeters :: Coord -> Coord -> Double
distanceMeters a b =
  2 * earthRadiusMeters * asin (sqrt h)
  where
    lat1 = toRadians a.lat
    lat2 = toRadians b.lat
    dLat = toRadians (b.lat - a.lat)
    dLon = toRadians (b.lon - a.lon)

    sinDLat = sin (dLat / 2)
    sinDLon = sin (dLon / 2)

    h = sinDLat * sinDLat + cos lat1 * cos lat2 * sinDLon * sinDLon

-- | Degrees to radians. Go spells this inline as @x * math.Pi / 180.0@ four
-- times; naming it once is the same code with the intent made explicit.
toRadians :: Double -> Double
toRadians degrees = degrees * pi / 180.0
