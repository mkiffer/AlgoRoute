{-# LANGUAGE OverloadedStrings #-}

-- | Reverse geocoding via Nominatim. Port of Go @geo/reverse.go@.
--
-- Turns a coordinate back into a human-readable address. Note the two
-- differences from the forward path: a different endpoint (@/reverse@) and a
-- single JSON /object/ response (not an array).
module Geo.Reverse
  ( reverseGeocodeURL
  , reverseGeocode
  ) where

import Control.Monad.Except (ExceptT)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import Geo.Geocode (GeoError)
import Geo.Types (Coord)

-- | Nominatim reverse endpoint. (Go: @nominatimReverseBaseURL@.)
nominatimReverseBaseURL :: Text
nominatimReverseBaseURL = "https://nominatim.openstreetmap.org/reverse"

-- | The full reverse URL for a coordinate — pure, unit-testable.
-- (Go: @ReverseGeocodeURL@.)
--
-- TODO: params @format=json@, @lat=<lat>@, @lon=<lon>@ (full-precision floats).
reverseGeocodeURL :: Coord -> Text
reverseGeocodeURL = undefined

-- | The address string for a coordinate. (Go: @ReverseGeocode@ /
-- @ReverseGeocodeWithBaseURL@.)
--
-- TODO:
--   1. Fetch as elsewhere (User-Agent header, shared 'Manager').
--   2. Decode a single object; read its @display_name@ field.
--   3. Missing/empty @display_name@ → 'Geo.Geocode.GeoNoResults'.
reverseGeocode :: Manager -> Text -> Coord -> ExceptT GeoError IO Text
reverseGeocode = undefined
