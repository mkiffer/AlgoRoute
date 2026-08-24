{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Geographic primitives: coordinates and bounding boxes.
--
-- Port of Go @geo/coords.go@, @geo/bbox.go@, @geo/bbox_helpers.go@.
--
-- These are the lowest layer — pure data plus a little arithmetic, no IO.
-- Everything else (graph, mapping, services) depends on 'Coord'/'BBox', so
-- get these right first.
--
-- Note on layering: the plan (§3.1) lists 'Coord' inside @Graph.hs@, but the
-- @.cabal@ gives us a dedicated @Geo.Types@ module and the Go code keeps
-- @geo.Coord@ in the geo package — so 'Coord' lives here and @Graph@ imports it.
module Geo.Types
  ( Coord (..)
  , BBox (..)
  , contains
  , approxAreaKm2
  , bboxFromCoords
  ) where

-- | A latitude/longitude pair in decimal degrees. (Go: @geo.Coord@.)
data Coord = Coord
  { lat :: Double
  , lon :: Double
  }
  deriving stock (Show, Eq)

-- | An axis-aligned geographic rectangle. (Go: @geo.BBox@.)
--
-- All fields are 'Double', so 'BBox' derives 'Ord' and can be used directly as
-- a @Map@ key — that is what the network cache relies on (see "Services.Cache").
data BBox = BBox
  { minLat :: Double
  , minLon :: Double
  , maxLat :: Double
  , maxLon :: Double
  }
  deriving stock (Show, Eq, Ord)

-- | Does the box contain the coordinate? (Go: @BBox.Contains@.)
contains :: BBox -> Coord -> Bool
contains bbox coord = latWithinBounds && lonWithinBounds 
  where 
    latWithinBounds = coord.lat <= bbox.maxLat &&  coord.lat >= bbox.minLat
    lonWithinBounds =  coord.lon <= bbox.maxLon &&  coord.lon >= bbox.minLon

-- | Approximate area in km², with a cosine correction at the midpoint latitude
-- for longitude convergence. (Go: @BBox.ApproxAreaKm2@.)
--
-- Used by the services layer to reject oversized Overpass queries.
approxAreaKm2 :: BBox -> Double
approxAreaKm2 bbox = latSpanKm * lonSpanKm 
  where
    kmPerDegree = 111.32
    latSpanKm = (bbox.maxLat - bbox.minLat) * kmPerDegree
    midLatRad = (bbox.minLat + bbox.maxLat) / 2 * pi / 180
    lonSpanKm = (bbox.maxLon - bbox.minLon) * kmPerDegree * cos midLatRad

-- | Smallest box containing both coords, expanded by @paddingDegrees@ on every
-- side. (Go: @geo.BBoxFromCoords@; 0.01° ≈ 1 km.)
--
bboxFromCoords :: Coord -> Coord -> Double -> BBox
bboxFromCoords c1 c2 pad = BBox minLat minLon maxLat maxLon 
  where 
    minLat = min c1.lat c2.lat - pad
    minLon = min c1.lon c2.lon - pad
    maxLat = max c1.lat c2.lat + pad 
    maxLon = max c1.lon c2.lon + pad