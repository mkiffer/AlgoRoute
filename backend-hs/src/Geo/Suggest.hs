{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Geo.Suggest
-- Description : Address autocomplete suggestions, via Nominatim search.
--
-- Ports @backend/geo/suggest.go@.
module Geo.Suggest
  ( suggest
  , suggestURL
  , SuggestResult (..)
  , suggestResultLimit
  ) where

import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Geo.Nominatim (GeoError, buildURL, fetchJSON, parseCoordinateText)
import Network.HTTP.Client (Manager)

-- | How many suggestions to request.
--
-- Five fills a compact dropdown without scrolling, and Nominatim's fair-use
-- policy asks for modest limits. Same value as Go.
suggestResultLimit :: Text
suggestResultLimit = "5"

-- | One suggestion, as returned by @GET \/api\/suggest@.
--
-- Unlike 'Geo.Geocode.NominatimHit', this type is also part of the /outgoing/
-- JSON contract, so it carries a 'ToJSON' instance producing the field names
-- the frontend expects — note @display_name@, not @displayName@.
data SuggestResult = SuggestResult
  { displayName :: !Text
  , lat :: !Double
  , lon :: !Double
  }
  deriving stock (Eq, Show)

instance ToJSON SuggestResult where
  toJSON result =
    object
      [ "display_name" .= result.displayName
      , "lat" .= result.lat
      , "lon" .= result.lon
      ]

-- | The mirror of 'ToJSON', so a client — or a test asserting the wire
-- contract — can read back what the server writes. Note the coordinates are
-- numbers here, not the strings Nominatim sends: this is /our/ shape, not
-- Nominatim's.
instance FromJSON SuggestResult where
  parseJSON = withObject "SuggestResult" $ \o ->
    SuggestResult <$> o .: "display_name" <*> o .: "lat" <*> o .: "lon"

-- | The raw wire shape: @display_name@ plus string coordinates.
data SuggestHit = SuggestHit
  { rawDisplayName :: !Text
  , rawLat :: !Text
  , rawLon :: !Text
  }

instance FromJSON SuggestHit where
  parseJSON = withObject "SuggestHit" $ \o ->
    SuggestHit <$> o .: "display_name" <*> o .: "lat" <*> o .: "lon"

-- | The URL an autocomplete request would hit. Exposed for testing, mirroring
-- Go's @SuggestURL@.
suggestURL :: Text -> Text -> Text
suggestURL baseUrl query =
  buildURL baseUrl [("format", "json"), ("q", query), ("limit", suggestResultLimit)]

-- | Up to five address suggestions for a partial query.
--
-- __Bad entries are skipped, not fatal.__ If one hit has an unparseable
-- coordinate, it is dropped and the rest are returned — 'mapMaybe' keeps every
-- 'Just' and discards every 'Nothing'. Failing the whole response would blank
-- the user's dropdown because of one malformed row. Go writes the same policy
-- as two @continue@ statements.
--
-- (The Go backend lists this silent skipping as a known issue: failures are
-- invisible. That is equally true here. The fix is to log before discarding,
-- which is a two-line change confined to 'toResult'.)
--
-- A transport-level failure /is/ returned as an error. The HTTP handler is what
-- decides to turn that into an empty array — see "API.Handlers".
suggest :: Manager -> Text -> Text -> IO (Either GeoError [SuggestResult])
suggest manager baseUrl query = do
  response <- fetchJSON manager (suggestURL baseUrl query)
  pure $ case response of
    Left err -> Left err
    Right hits -> Right (mapMaybe toResult hits)
  where
    toResult :: SuggestHit -> Maybe SuggestResult
    toResult hit =
      case (parseCoordinateText hit.rawLat, parseCoordinateText hit.rawLon) of
        (Right latitude, Right longitude) ->
          Just
            SuggestResult
              { displayName = hit.rawDisplayName
              , lat = latitude
              , lon = longitude
              }
        _ -> Nothing
