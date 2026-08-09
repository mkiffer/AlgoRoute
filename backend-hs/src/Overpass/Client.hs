{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Overpass.Client
-- Description : Build Overpass QL queries and fetch road data.
--
-- Ports @backend/api/overpass/fetch.go@ and the file-loading half of
-- @client.go@.
--
-- The module splits cleanly in two: 'buildQuery' is pure and exhaustively
-- testable, while 'fetchFromAPI' and 'loadFromFile' are the only functions here
-- that touch the outside world. Their types say so — anything returning @IO@
-- can perform effects, anything not returning @IO@ provably cannot. That is the
-- guarantee Go's @BuildOverpassQuery@ can only ask for by convention.
module Overpass.Client
  ( -- * Query construction
    buildQuery
  , driveableHighwayTypes

    -- * Fetching
  , fetchFromAPI
  , loadFromFile
  , OverpassError (..)

    -- * Limits
  , maxResponseBytes
  , overpassTimeoutMicroseconds
  , defaultOverpassURL
  ) where

import Control.Exception (SomeException, try)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Geo.Types (BBox (..))
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , brReadSome
  , parseRequest
  , responseBody
  , responseStatus
  , responseTimeoutMicro
  , urlEncodedBody
  , withResponse
  )
import Network.HTTP.Types.Status (statusCode)
import Numeric (showFFloat)
import Overpass.Types (Response)

-- | The live Overpass endpoint.
defaultOverpassURL :: Text
defaultOverpassURL = "https://overpass-api.de/api/interpreter"

-- | OSM @highway@ values a car may legally drive on, as an alternation for the
-- Overpass regex filter.
--
-- Footways, cycleways and service roads are excluded on purpose: including them
-- would let the router send a car down a pedestrian mall. Verbatim from Go.
driveableHighwayTypes :: Text
driveableHighwayTypes =
  "motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street"

-- | How long to wait for Overpass. 30 seconds, matching Go.
--
-- Generous by API standards, and deliberately so: a city-scale bounding box can
-- take Overpass 10+ seconds to answer, and a shorter timeout turns a slow
-- response into a spurious failure.
overpassTimeoutMicroseconds :: Int
overpassTimeoutMicroseconds = 30 * 1000 * 1000

-- | Refuse to read more than 10 MB of response body.
--
-- Generous for a city, and the thing standing between a Melbourne→Geelong
-- request and an out-of-memory kill: that bounding box can return well over
-- 100 MB. "Services.Routing" also rejects oversized boxes before the request is
-- made; this is the backstop for when the estimate is wrong.
maxResponseBytes :: Int
maxResponseBytes = 10 * 1024 * 1024

-- | Everything that can go wrong getting data out of Overpass.
--
-- Go returns @fmt.Errorf@ strings, so a caller wanting to react differently to
-- \"too large\" than to \"timed out\" would have to match on message text. These
-- constructors let "App.Error" map each cause to its own HTTP response.
data OverpassError
  = -- | The HTTP request itself failed: DNS, connection, timeout.
    RequestFailed !Text
  | -- | Overpass answered with a non-200 status. Carries the status code.
    BadStatus !Int
  | -- | The body exceeded 'maxResponseBytes'.
    ResponseTooLarge
  | -- | The body was not the JSON we expected.
    DecodeFailed !Text
  | -- | 'loadFromFile' could not read the file.
    FileReadFailed !Text
  deriving stock (Eq, Show)

-- | The Overpass QL query fetching every driveable way inside a bounding box,
-- together with the nodes those ways reference.
--
-- Byte-identical to Go's @BuildOverpassQuery@, including the six-decimal
-- coordinate formatting. Two details are worth knowing:
--
-- * __Argument order.__ Overpass takes a bbox as @(south, west, north, east)@,
--   i.e. @minLat, minLon, maxLat, maxLon@ — latitude first, unlike almost every
--   other geo API. Getting this backwards yields an empty result rather than an
--   error, which is a miserable thing to debug.
--
-- * __The @>;@ idiom.__ The filter matches /ways/, and a way is just a list of
--   node IDs — no coordinates. @>;@ means \"also emit everything these ways
--   refer to\", so the response contains the nodes as well. Without it,
--   "Mapping" would have references it could not resolve and would build an
--   empty network.
buildQuery :: BBox -> Text
buildQuery bbox =
  "[out:json];(way[\"highway\"~\"^("
    <> driveableHighwayTypes
    <> ")$\"]("
    <> boundingBoxArgument
    <> ");>;);out body;"
  where
    boundingBoxArgument =
      T.intercalate
        ","
        (map sixDecimals [bbox.minLat, bbox.minLon, bbox.maxLat, bbox.maxLon])

-- | Format a coordinate the way Go's @%.6f@ does. Six decimal places is about
-- 11 cm at the equator — far finer than OSM data warrants, and what the Go
-- backend emits, so the two produce identical query strings.
sixDecimals :: Double -> Text
sixDecimals value = T.pack (showFFloat (Just 6) value "")

-- | POST a bounding-box query to Overpass and decode the response.
--
-- The base URL is a parameter rather than a constant so tests can point it at a
-- local stub server. Go achieves the same with a parallel
-- @FetchFromAPIWithBaseURL@ function that production never calls; here there is
-- one function, and "App.Env" supplies the URL. See @src\/App\/README.md@.
--
-- __Streaming, not slurping.__ 'withResponse' plus 'brReadSome' reads at most
-- @maxResponseBytes + 1@ bytes and stops. Asking for one byte past the limit is
-- what makes \"exactly at the limit\" distinguishable from \"over it\" — the same
-- trick as Go's @io.LimitReader(body, max+1)@.
fetchFromAPI :: Manager -> Text -> BBox -> IO (Either OverpassError Response)
fetchFromAPI manager baseUrl bbox = do
  parsed <- try (parseRequest (T.unpack baseUrl))
  case parsed of
    Left exception -> pure (Left (RequestFailed (renderException exception)))
    Right template -> do
      let request =
            (urlEncodedBody [("data", TE.encodeUtf8 (buildQuery bbox))] template)
              {responseTimeout = responseTimeoutMicro overpassTimeoutMicroseconds}
      outcome <- try (withResponse request manager readBody)
      pure $ case outcome of
        Left exception -> Left (RequestFailed (renderException exception))
        Right result -> result
  where
    readBody response
      | status /= 200 = pure (Left (BadStatus status))
      | otherwise = do
          body <- brReadSome (responseBody response) (maxResponseBytes + 1)
          pure $
            if LBS.length body > fromIntegral maxResponseBytes
              then Left ResponseTooLarge
              else decodeResponse body
      where
        status = statusCode (responseStatus response)

-- | Read a saved Overpass response from disk.
--
-- Ports @LoadNetworkFromJSON@. Used by the CLI mode of "Main" and by tests that
-- want a real network without a network call.
loadFromFile :: FilePath -> IO (Either OverpassError Response)
loadFromFile path = do
  contents <- try (LBS.readFile path)
  pure $ case contents of
    Left exception -> Left (FileReadFailed (renderException exception))
    Right body -> decodeResponse body

-- | Decode a response body, tagging any @aeson@ error as 'DecodeFailed'.
decodeResponse :: LBS.ByteString -> Either OverpassError Response
decodeResponse body = case eitherDecode body of
  Left message -> Left (DecodeFailed (T.pack message))
  Right response -> Right response

-- | Render any exception as text.
--
-- 'try' at 'SomeException' catches everything, which is the right granularity
-- here: whether it was a DNS failure or a TLS handshake error, the caller's
-- response is the same, and the detail survives in the message.
renderException :: SomeException -> Text
renderException = T.pack . show
