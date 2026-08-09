{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.BBox
-- Description : Operations on bounding boxes — containment, area, construction.
--
-- Ports the function half of @backend/geo/bbox.go@ plus all of
-- @backend/geo/bbox_helpers.go@. The 'BBox' type itself lives in "Geo.Types".
module Geo.BBox
  ( contains
  , approxAreaKm2
  , fromCoords
  , kmPerDegree
  ) where

import Geo.Types (BBox (..), Coord (..))

-- | Approximate length in kilometres of one degree of latitude — and of one
-- degree of longitude /at the equator/. Used only for the rough area estimate
-- that guards query size.
kmPerDegree :: Double
kmPerDegree = 111.32

-- | Does the box contain this coordinate? Boundaries are inclusive, matching
-- Go's @>=@ / @<=@ comparisons.
contains :: BBox -> Coord -> Bool
contains b c =
  c.lat >= b.minLat
    && c.lat <= b.maxLat
    && c.lon >= b.minLon
    && c.lon <= b.maxLon

-- | Approximate area of the box in square kilometres.
--
-- Longitude lines converge toward the poles, so a degree of longitude is
-- @kmPerDegree · cos(latitude)@ wide. Taking the cosine at the box's midpoint
-- latitude is a first-order correction: good enough to reject an oversized
-- Overpass query, nowhere near good enough for geodesic work. Same caveat, and
-- same maths, as the Go original.
approxAreaKm2 :: BBox -> Double
approxAreaKm2 b = latSpanKm * lonSpanKm
  where
    latSpanKm = (b.maxLat - b.minLat) * kmPerDegree
    midLatRadians = (b.minLat + b.maxLat) / 2.0 * pi / 180.0
    lonSpanKm = (b.maxLon - b.minLon) * kmPerDegree * cos midLatRadians

-- | The smallest box containing both coordinates, expanded outward by
-- @paddingDegrees@ on every side.
--
-- The padding is what makes routing work at all: a geocoded address almost
-- never lands exactly on an OSM node, so without a margin the fetched network
-- can stop short of the roads either endpoint actually sits on. The caller
-- passes 0.01°, which is roughly 1 km — see
-- @Services.Routing.bboxPaddingDegrees@.
--
-- Go reaches for its @min@/@max@ builtins; these are Prelude functions here,
-- so the body is the same four comparisons.
fromCoords :: Coord -> Coord -> Double -> BBox
fromCoords a b paddingDegrees =
  BBox
    { minLat = min a.lat b.lat - paddingDegrees
    , maxLat = max a.lat b.lat + paddingDegrees
    , minLon = min a.lon b.lon - paddingDegrees
    , maxLon = max a.lon b.lon + paddingDegrees
    }
