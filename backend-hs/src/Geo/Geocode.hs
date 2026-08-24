{-# LANGUAGE OverloadedStrings #-}

-- | Forward geocoding via Nominatim. Port of Go @geo/geocode.go@.
--
-- Your first taste of @ExceptT GeoError IO@: an effectful computation that can
-- short-circuit with a typed error (≈ an async Task that can throw @GeoError@).
-- The 'Manager' is created once at startup and threaded in (see the @Env@
-- pattern in "Services.Routing") — think C# scoped singleton, not a global.
module Geo.Geocode
  ( GeoError (..)
  , nominatimURL
  , geocode
  ) where

import Control.Monad.Except (ExceptT)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import Geo.Types (Coord)

-- | Failure modes shared by geocode/reverse. (Go returns formatted @error@s.)
data GeoError
  = GeoRequestFailed Text   -- ^ transport/HTTP error
  | GeoBadStatus Int        -- ^ non-200 from Nominatim
  | GeoNoResults            -- ^ empty result array
  | GeoDecodeFailed Text    -- ^ JSON did not parse, or lat/lon unparseable
  deriving stock (Show, Eq)

-- | Base endpoint for Nominatim search. (Go: @nominatimBaseURL@.)
nominatimBaseURL :: Text
nominatimBaseURL = "https://nominatim.openstreetmap.org/search"

-- | The full search URL for an address — pure, so it can be unit-tested
-- without a network call. (Go: @NominatimURL@.)
--
-- TODO: query params @format=json@, @q=<address>@, @limit=1@, URL-encoded.
--       @Network.HTTP.Types.URI.renderSimpleQuery@ or @http-client@'s
--       @setQueryString@ can build this.
nominatimURL :: Text -> Text
nominatimURL = undefined

-- | Resolve a free-text address to a coordinate. (Go: @Geocode@ /
-- @GeocodeWithBaseURL@ — pass the base URL so tests can inject a fake server.)
--
-- Watch out: Nominatim returns @lat@/@lon@ as JSON /strings/. Parse with
-- @read \@Double . unpack@ (≈ Go's @strconv.ParseFloat@).
--
-- TODO:
--   1. Build the request from 'nominatimURL'; set a descriptive @User-Agent@
--      header (Nominatim rate-limits requests without one).
--   2. @httpLbs@ with the shared 'Manager'; non-200 → 'GeoBadStatus'.
--   3. Decode a @[{lat,lon}]@ array; empty → 'GeoNoResults'.
--   4. Parse the first hit's string lat/lon into a 'Coord'.
geocode :: Manager -> Text -> Text -> ExceptT GeoError IO Coord
geocode = undefined
