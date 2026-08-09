-- |
-- Module      : Geo.Nominatim
-- Description : Shared plumbing for the three Nominatim endpoints.
--
-- This module has no Go counterpart, and that is the point.
--
-- @geocode.go@, @suggest.go@ and @reverse.go@ each repeat the same forty lines:
-- build a URL from @url.Values@, set the @User-Agent@, do the request, check
-- the status, read the body, unmarshal, handle four error cases. Three copies,
-- three chances to fix a bug in only two of them. Here that sequence is
-- 'fetchJSON', and the three endpoint modules are a dozen lines each.
module Geo.Nominatim
  ( -- * Errors
    GeoError (..)

    -- * Endpoints
  , defaultSearchURL
  , defaultReverseURL

    -- * Request plumbing
  , buildURL
  , fetchJSON
  , userAgent

    -- * Parsing helpers
  , parseCoordinateText
  , formatCoordinate
  ) where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON, eitherDecode)
import Data.ByteString qualified as BS
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , brReadSome
  , parseRequest
  , responseBody
  , responseStatus
  , responseTimeoutMicro
  , withResponse
  )
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (renderSimpleQuery)
import Numeric (showFFloat)
import Text.Read (readMaybe)

-- | Everything that can go wrong talking to Nominatim.
--
-- Go returns a formatted @error@ at each of these points. As a sum type, the
-- caller can decide per case — and the three endpoints /do/ decide differently:
-- a failed geocode aborts the whole route request, while a failed autocomplete
-- quietly returns an empty list so the dropdown just shows nothing.
data GeoError
  = -- | Connection, DNS or timeout failure.
    RequestFailed !Text
  | -- | Nominatim answered with a non-200 status.
    BadStatus !Int
  | -- | The body was not the JSON shape expected.
    DecodeFailed !Text
  | -- | The query returned zero results. Carries the query.
    NoResults !Text
  | -- | Nominatim sent a coordinate that would not parse as a number.
    UnparseableCoordinate !Text
  deriving stock (Eq, Show)

-- | Nominatim's search endpoint, used for both geocoding and autocomplete.
defaultSearchURL :: Text
defaultSearchURL = "https://nominatim.openstreetmap.org/search"

-- | Nominatim's reverse-geocoding endpoint.
defaultReverseURL :: Text
defaultReverseURL = "https://nominatim.openstreetmap.org/reverse"

-- | The @User-Agent@ every Nominatim request must carry.
--
-- This is not optional politeness. Nominatim's usage policy requires a
-- descriptive agent identifying the application, and requests without one are
-- rate-limited hard or refused outright. Same string as the Go backend.
userAgent :: BS.ByteString
userAgent = "AlgoRoute/1.0 (https://github.com/algoroute)"

-- | Nominatim requests get 10 seconds.
--
-- Shorter than Overpass's 30 because geocoding is a small lookup, and because
-- a slow geocode would otherwise stall an entire route request before any real
-- work began. Matches Go's @httpClient@ timeout.
nominatimTimeoutMicroseconds :: Int
nominatimTimeoutMicroseconds = 10 * 1000 * 1000

-- | Nominatim responses are small; refuse anything implausible.
maxResponseBytes :: Int
maxResponseBytes = 1024 * 1024

-- | Append a query string to a base URL.
--
-- Parameters are sorted by key before rendering, which is not cosmetic: Go's
-- @url.Values.Encode@ sorts too, so sorting here means the two backends emit
-- byte-identical URLs and the ported URL-shape tests still pass.
buildURL :: Text -> [(Text, Text)] -> Text
buildURL base params =
  base <> TE.decodeUtf8 (renderSimpleQuery True (map encodePair (sortOn fst params)))
  where
    encodePair (key, value) = (TE.encodeUtf8 key, TE.encodeUtf8 value)

-- | GET a URL and decode the JSON body.
--
-- The @FromJSON a@ constraint means the /caller's expected type/ decides how
-- the body is parsed — 'Geo.Geocode' asks for a list of hits, 'Geo.Reverse'
-- asks for a single object, and this function needs to know nothing about
-- either. Go would need @interface{}@ and a type assertion, or a separate
-- function per shape.
fetchJSON :: (FromJSON a) => Manager -> Text -> IO (Either GeoError a)
fetchJSON manager url = do
  parsed <- try (parseRequest (T.unpack url))
  case parsed of
    Left exception -> pure (Left (RequestFailed (renderException exception)))
    Right template -> do
      let request =
            template
              { requestHeaders = ("User-Agent", userAgent) : requestHeaders template
              , responseTimeout = responseTimeoutMicro nominatimTimeoutMicroseconds
              }
      outcome <- try (withResponse request manager readBody)
      pure $ case outcome of
        Left exception -> Left (RequestFailed (renderException exception))
        Right result -> result
  where
    readBody response
      | status /= 200 = pure (Left (BadStatus status))
      | otherwise = do
          body <- brReadSome (responseBody response) maxResponseBytes
          pure $ case eitherDecode body of
            Left message -> Left (DecodeFailed (T.pack message))
            Right value -> Right value
      where
        status = statusCode (responseStatus response)

-- | Parse a coordinate that Nominatim sent as a JSON /string/.
--
-- Nominatim reports @\"lat\": \"-37.8467\"@ — quoted, not numeric. Go handles
-- this by declaring the DTO field as @string@ and calling @strconv.ParseFloat@;
-- this is the same two-step, with the failure in the return type instead of a
-- second return value.
parseCoordinateText :: Text -> Either GeoError Double
parseCoordinateText raw =
  case readMaybe (T.unpack (T.strip raw)) of
    Just value -> Right value
    Nothing -> Left (UnparseableCoordinate raw)

-- | Render a coordinate for a query string.
--
-- Matches Go's @strconv.FormatFloat(v, 'f', -1, 64)@: shortest decimal
-- representation, never scientific notation. Plain 'show' would emit
-- @1.0e-2@ for @0.01@, which Nominatim rejects — 'showFFloat' with no digit
-- count is the fixed-notation equivalent.
formatCoordinate :: Double -> Text
formatCoordinate value = T.pack (showFFloat Nothing value "")

renderException :: SomeException -> Text
renderException = T.pack . show
