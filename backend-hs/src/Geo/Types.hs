{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.Types
-- Description : Geographic primitives — a point and an axis-aligned box.
--
-- Ports @backend/geo/coords.go@ and the type half of @backend/geo/bbox.go@.
--
-- This module deliberately holds only data declarations. Everything that
-- /operates/ on these types lives elsewhere: distance maths in "Geo.Distance",
-- box construction and area in "Geo.BBox". Keeping the types in a leaf module
-- with no dependencies means every other module can import them without
-- creating an import cycle — the same reason Go split @coords.go@ out.
module Geo.Types
  ( Coord (..)
  , BBox (..)
  ) where

-- | A WGS-84 geographic coordinate in decimal degrees.
--
-- Go's @geo.Coord@ is a two-field struct and so is this. Note the derived
-- 'Eq': Go compares structs field-by-field with @==@ automatically, and
-- @deriving Eq@ is the direct equivalent. Floating-point equality is as
-- fragile here as it is there, so tests compare with a tolerance rather than
-- with '=='.
data Coord = Coord
  { lat :: !Double
  , lon :: !Double
  }
  deriving stock (Eq, Ord, Show)

-- | An axis-aligned bounding box: the rectangle used as an Overpass query
-- region.
--
-- Ports @geo.BBox@. The 'Ord' instance is not decoration — "Services.Cache"
-- keys a @Map BBox Response@ on it, mirroring Go's use of @map[geo.BBox]@,
-- which is legal there precisely because @BBox@ contains only comparable
-- @float64@ fields.
--
-- The fields are strict (@!Double@) so a box can never hold an unevaluated
-- thunk. That matters because boxes are stored in a long-lived cache; a lazy
-- field would retain the whole computation that produced it.
data BBox = BBox
  { minLat :: !Double
  , minLon :: !Double
  , maxLat :: !Double
  , maxLon :: !Double
  }
  deriving stock (Eq, Ord, Show)
