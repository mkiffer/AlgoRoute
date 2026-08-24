{-# LANGUAGE OverloadedStrings #-}

-- | Address autocomplete via Nominatim. Port of Go @geo/suggest.go@.
--
-- Same request pattern as "Geo.Geocode", but returns up to five results and is
-- forgiving: a single hit with an unparseable coordinate is skipped, not fatal,
-- so the rest still reach the user. The 'SuggestResult' wire type is reused
-- from "API.Types" (that's where the JSON contract lives).
module Geo.Suggest
  ( suggestURL
  , suggest
  ) where

import Control.Monad.Except (ExceptT)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import API.Types (SuggestResult)
import Geo.Geocode (GeoError)

-- | Nominatim caps suggestions at five — enough for a compact dropdown.
-- (Go: @nominatimSuggestResultLimit@.)
suggestResultLimit :: Int
suggestResultLimit = 5

-- | The full search URL for a query — pure, unit-testable. (Go: @SuggestURL@.)
--
-- TODO: same as 'Geo.Geocode.nominatimURL' but with @limit=5@.
suggestURL :: Text -> Text
suggestURL = undefined

-- | Up to five suggestions for @query@. (Go: @Suggest@ / @SuggestWithBaseURL@.)
--
-- TODO:
--   1. Fetch as in 'Geo.Geocode.geocode' (User-Agent header, shared 'Manager').
--   2. Decode a @[{display_name, lat, lon}]@ array (lat/lon are strings).
--   3. 'Data.Maybe.mapMaybe' over the hits: keep only those whose lat/lon
--      parse — skip bad entries instead of failing the whole request.
suggest :: Manager -> Text -> Text -> ExceptT GeoError IO [SuggestResult]
suggest = undefined
