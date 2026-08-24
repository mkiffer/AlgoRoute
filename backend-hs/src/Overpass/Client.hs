{-# LANGUAGE OverloadedStrings #-}

-- | Overpass API HTTP client. Port of Go @api/overpass/fetch.go@
-- (@BuildOverpassQuery@, @FetchFromAPI@) and the JSON loader in @client.go@
-- (@LoadNetworkFromJSON@, reused by the mapping tests).
--
-- First IO in the Overpass layer. 'buildQuery' stays pure (TDD it directly);
-- 'fetchFromAPI' lives in @ExceptT OverpassError IO@ so failures short-circuit
-- with a typed error instead of an exception.
module Overpass.Client
  ( OverpassError (..)
  , buildQuery
  , fetchFromAPI
  , loadFromFile
  ) where

import Control.Monad.Except (ExceptT)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import Geo.Types (BBox)
import Overpass.Types (Response)

-- | Everything that can go wrong talking to Overpass. (Go returns formatted
-- @error@ values; a typed sum lets the service map each case deliberately.)
data OverpassError
  = RequestFailed Text     -- ^ transport/HTTP error
  | BadStatus Int          -- ^ non-200 response
  | ResponseTooLarge       -- ^ body exceeded the 10 MB cap
  | DecodeFailed Text      -- ^ JSON did not parse
  deriving stock (Show, Eq)

-- | Driveable OSM highway classes, as an alternation for the regex filter.
-- (Go: @driveableHighwayTypes@.)
driveableHighwayTypes :: Text
driveableHighwayTypes =
  "motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street"

-- | Maximum response body we will buffer: 10 MB. (Go: @maxResponseBytes@.)
maxResponseBytes :: Int
maxResponseBytes = 10 * 1024 * 1024

-- | Build the Overpass QL query for all driveable ways (and their nodes) in
-- @bbox@. Pure and unit-testable. (Go: @BuildOverpassQuery@.)
--
-- Bbox argument order is Overpass's: south,west,north,east = minLat,minLon,maxLat,maxLon.
--
-- TODO: format the bbox to 6 dp and interpolate into:
--   [out:json];(way["highway"~"^(<types>)$"](<south,west,north,east>);>;);out body;
-- @Data.Text@ + @Text.printf@ or plain @<>@ concatenation both work.
buildQuery :: BBox -> Text
buildQuery = undefined

-- | POST the query for @bbox@ to Overpass and parse the response.
-- (Go: @FetchFromAPIWithBaseURL@; @baseURL@ defaults to the public endpoint but
-- is a parameter so tests can point at a fake server.)
--
-- TODO:
--   1. @buildQuery bbox@ → form-encode as @data=<query>@.
--   2. POST with a 30 s timeout using the shared 'Manager'.
--   3. Non-200 → 'Left' ('BadStatus' code).
--   4. Read at most @maxResponseBytes + 1@; if over, 'Left' 'ResponseTooLarge'.
--   5. Decode via the 'FromJSON' 'Response' instance ('mkResponse' fills indexes).
--      Wrap 'IO' exceptions with @liftIO@ / @tryAny@ into 'Left' 'RequestFailed'.
fetchFromAPI :: Manager -> Text -> BBox -> ExceptT OverpassError IO Response
fetchFromAPI = undefined

-- | Load and parse an Overpass JSON file from disk. (Go: @LoadNetworkFromJSON@.)
-- Handy for tests and offline runs against the sample fixture.
--
-- TODO: read the file, 'Data.Aeson.eitherDecodeStrict', map a decode error to
--       'Left' ('DecodeFailed' …).
loadFromFile :: FilePath -> IO (Either OverpassError Response)
loadFromFile = undefined
