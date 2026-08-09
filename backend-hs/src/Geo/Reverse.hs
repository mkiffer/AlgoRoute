{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.Reverse
-- Description : Coordinate to human-readable address, via Nominatim reverse.
--
-- Ports @backend/geo/reverse.go@. This is what turns a click on the map into
-- a label in the origin/destination box.
module Geo.Reverse
  ( reverseGeocode
  , reverseGeocodeURL
  ) where

import Data.Aeson (FromJSON (..), withObject, (.:?))
import Data.Text (Text)
import Geo.Nominatim
  ( GeoError (..)
  , buildURL
  , fetchJSON
  , formatCoordinate
  )
import Geo.Types (Coord (..))
import Network.HTTP.Client (Manager)

-- | Nominatim's reverse response.
--
-- Note this is a single JSON /object/, not an array — the one structural
-- difference from the search endpoint, and the reason reverse cannot simply
-- reuse 'Geo.Geocode.geocode'.
--
-- @display_name@ is optional here because Nominatim omits it entirely when the
-- coordinate falls in the ocean or on unmapped land. That is a legitimate
-- \"no address\" answer rather than a malformed response, so the field is
-- 'Maybe' and the empty case is handled below.
newtype ReverseResult = ReverseResult
  { displayName :: Maybe Text
  }

instance FromJSON ReverseResult where
  parseJSON = withObject "ReverseResult" $ \object ->
    ReverseResult <$> object .:? "display_name"

-- | The URL a reverse-geocode request would hit. Exposed for testing, mirroring
-- Go's @ReverseGeocodeURL@.
reverseGeocodeURL :: Text -> Coord -> Text
reverseGeocodeURL baseUrl coordinate =
  buildURL
    baseUrl
    [ ("format", "json")
    , ("lat", formatCoordinate coordinate.lat)
    , ("lon", formatCoordinate coordinate.lon)
    ]

-- | The address nearest to a coordinate.
--
-- __Degrades gracefully by design.__ A missing or empty @display_name@ becomes
-- 'NoResults' rather than a crash, and "API.Handlers" turns that into
-- @{\"address\": \"\"}@ with a 200. The user still gets their pin dropped on the
-- map; they just type the address themselves. Losing the label is a small
-- annoyance, losing the pin would break the click-to-route flow entirely.
reverseGeocode :: Manager -> Text -> Coord -> IO (Either GeoError Text)
reverseGeocode manager baseUrl coordinate = do
  -- 'fetchJSON' is polymorphic in its result, and nothing below pins the type
  -- down (record-dot access goes through @HasField@, which does not drive
  -- inference). The annotation says which decoder to use — the Haskell
  -- equivalent of naming the struct you unmarshal into.
  response <-
    fetchJSON manager (reverseGeocodeURL baseUrl coordinate) ::
      IO (Either GeoError ReverseResult)
  pure $ case response of
    Left err -> Left err
    Right result -> case result.displayName of
      Just address | address /= "" -> Right address
      _ -> Left (NoResults "reverse geocode: no display_name in response")
