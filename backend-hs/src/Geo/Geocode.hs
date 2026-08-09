{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.Geocode
-- Description : Free-text address to coordinate, via Nominatim search.
--
-- Ports @backend/geo/geocode.go@. All the HTTP mechanics live in
-- "Geo.Nominatim"; what remains here is the endpoint's own parameters and
-- response shape.
module Geo.Geocode
  ( geocode
  , geocodeURL
  , NominatimHit (..)
  ) where

import Data.Aeson (FromJSON (..), withObject, (.:))
import Data.Text (Text)
import Geo.Nominatim
  ( GeoError (..)
  , buildURL
  , fetchJSON
  , parseCoordinateText
  )
import Geo.Types (Coord (..))
import Network.HTTP.Client (Manager)

-- | One entry of a Nominatim search response.
--
-- The coordinates arrive as JSON /strings/, so they are kept as 'Text' here and
-- converted in 'geocode'. Modelling the wire shape faithfully and converting in
-- one explicit step beats a clever 'FromJSON' instance that hides the
-- conversion: when Nominatim sends something unparseable, the error names the
-- field.
data NominatimHit = NominatimHit
  { rawLat :: !Text
  , rawLon :: !Text
  }
  deriving stock (Eq, Show)

instance FromJSON NominatimHit where
  parseJSON = withObject "NominatimHit" $ \object ->
    NominatimHit <$> object .: "lat" <*> object .: "lon"

-- | The URL a geocode request would hit.
--
-- Exposed for the same reason Go exports @NominatimURL@: so the query
-- structure can be asserted in a test without a network call. Unlike Go's, this
-- one takes the base URL as a parameter, so the test and production paths are
-- the same code.
geocodeURL :: Text -> Text -> Text
geocodeURL baseUrl address =
  buildURL baseUrl [("format", "json"), ("q", address), ("limit", "1")]

-- | Resolve a free-text address to a coordinate.
--
-- @limit=1@ — we want Nominatim's best guess and nothing else. If the address
-- is ambiguous, the user disambiguates through the autocomplete dropdown
-- ("Geo.Suggest") before ever reaching this call.
--
-- __Failure is fatal to a route request.__ Unlike autocomplete and reverse
-- geocoding, which degrade to something harmless, an unresolvable address means
-- there is no route to compute. 'Services.Routing' propagates the error and the
-- request fails — matching Go's @fmt.Errorf(\"geocode origin: %w\", err)@.
--
-- Note @NoResults@ carries the address: an empty result array is not an HTTP
-- failure, it is a successful \"no such place\", and the message should say which
-- place.
geocode :: Manager -> Text -> Text -> IO (Either GeoError Coord)
geocode manager baseUrl address = do
  response <- fetchJSON manager (geocodeURL baseUrl address)
  pure $ case response of
    Left err -> Left err
    Right [] -> Left (NoResults address)
    Right (hit : _) -> toCoord hit

-- | Convert the string coordinates of a hit, failing on either.
toCoord :: NominatimHit -> Either GeoError Coord
toCoord hit = do
  latitude <- parseCoordinateText hit.rawLat
  longitude <- parseCoordinateText hit.rawLon
  pure Coord {lat = latitude, lon = longitude}
