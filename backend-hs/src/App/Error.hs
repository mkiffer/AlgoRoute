-- |
-- Module      : App.Error
-- Description : One error type for the whole request pipeline.
--
-- There is no single Go file this ports. Go threads @error@ through every
-- layer, wrapping with @fmt.Errorf(\"context: %w\", err)@ as it goes, and the
-- HTTP handler turns whatever arrives into a 500 with the accumulated message.
-- The layers below each keep their own error types here — 'GeoError',
-- 'OverpassError', 'GraphError', 'SnapError', 'RouteError' — and this module is
-- where they converge into the one type the HTTP boundary knows how to answer.
module App.Error
  ( AppError (..)
  , errorMessage
  , errorStatus
  , toServantError
  ) where

import Data.Aeson (encode, object, (.=))
import Data.Text (Text)
import Data.Text qualified as T
-- Both GeoError and OverpassError have RequestFailed / BadStatus /
-- DecodeFailed constructors. Rather than renaming one set, import both
-- qualified and let the prefix say which failure domain is meant.
import Geo.Nominatim (GeoError)
import Geo.Nominatim qualified as Nominatim
import Graph (GraphError (..))
import Graph.Snap (SnapError (..))
import Overpass.Client (OverpassError)
import Overpass.Client qualified as Overpass
import Routefinding.Types (RouteError (..))
import Servant (ServerError (..), err400, err500)

-- | Everything a route request can fail with.
--
-- Each constructor wraps the lower-level error it came from rather than
-- flattening it to a string, so nothing is lost on the way up: a handler, a
-- test, or a future logger can still pattern match on the original cause.
-- That is the practical difference from Go's @%w@ wrapping, which preserves the
-- cause but only reaches it through @errors.As@ and a type assertion.
data AppError
  = -- | The request itself was malformed — missing address, unknown algorithm.
    InvalidRequest !Text
  | -- | Geocoding failed. Carries which address, since the pipeline geocodes
    -- two and the message must say which one.
    GeocodeFailed !Text !GeoError
  | -- | The bounding box was too big to query. Carries actual and maximum km².
    AreaTooLarge !Double !Double
  | -- | Overpass could not be reached, or answered with something unusable.
    RoadDataUnavailable !OverpassError
  | -- | Overpass answered, but with no driveable roads in the box.
    NoRoadsInArea
  | -- | The response could not be turned into a valid graph.
    NetworkBuildFailed !GraphError
  | -- | An endpoint could not be snapped to the network.
    SnapFailed !Text !SnapError
  | -- | The search ran but found no route.
    RoutingFailed !RouteError
  deriving stock (Eq, Show)

-- | The message sent to the client.
--
-- Wording follows the Go handlers closely, because the frontend surfaces these
-- strings to the user directly and they have been written to be actionable
-- ("try closer addresses", not "bbox validation failed").
errorMessage :: AppError -> Text
errorMessage = \case
  InvalidRequest detail -> detail
  GeocodeFailed address cause ->
    "geocode " <> address <> ": " <> geoErrorMessage cause
  AreaTooLarge actual maximumAllowed ->
    "query area too large ("
      <> T.pack (show (round actual :: Int))
      <> " km²): maximum is "
      <> T.pack (show (round maximumAllowed :: Int))
      <> " km² — try closer addresses"
  RoadDataUnavailable cause -> "fetch road network: " <> overpassErrorMessage cause
  NoRoadsInArea ->
    "no driveable roads found in bounding box — \
    \the area between the two addresses may have no OSM road data"
  NetworkBuildFailed cause -> "build network: " <> graphErrorMessage cause
  SnapFailed which EmptyNetwork ->
    "snap " <> which <> " to network: network has no nodes"
  RoutingFailed (NoPathFound start goal) ->
    "route: no path from " <> T.pack (show start) <> " to " <> T.pack (show goal)
  RoutingFailed (NodeNotInNetwork nodeID) ->
    "route: node " <> T.pack (show nodeID) <> " is not in the network"

geoErrorMessage :: GeoError -> Text
geoErrorMessage = \case
  Nominatim.RequestFailed detail -> "HTTP request failed: " <> detail
  Nominatim.BadStatus status -> "nominatim returned status " <> T.pack (show status)
  Nominatim.DecodeFailed detail -> "could not decode response: " <> detail
  Nominatim.NoResults query -> "no results for " <> T.pack (show query)
  Nominatim.UnparseableCoordinate raw ->
    "unparseable coordinate " <> T.pack (show raw)

overpassErrorMessage :: OverpassError -> Text
overpassErrorMessage = \case
  Overpass.RequestFailed detail -> "HTTP request failed: " <> detail
  Overpass.BadStatus status ->
    "overpass API returned status " <> T.pack (show status)
  Overpass.ResponseTooLarge ->
    "overpass response too large (>10 MB): try a smaller area"
  Overpass.DecodeFailed detail -> "could not decode response: " <> detail
  Overpass.FileReadFailed detail -> "could not read file: " <> detail

graphErrorMessage :: GraphError -> Text
graphErrorMessage = \case
  MissingFromNode nodeID -> "missing 'from' node " <> T.pack (show nodeID)
  MissingToNode nodeID -> "missing 'to' node " <> T.pack (show nodeID)
  NegativeWeight weight -> "negative edge weight " <> T.pack (show weight)

-- | The HTTP status for an error.
--
-- __This matches the Go backend rather than what is strictly correct.__
-- @server\/handlers.go@ returns 400 only for a malformed request body or an
-- unknown algorithm, and 500 for every failure inside @RouteByAddress@ —
-- including \"area too large\" and \"address not found\", which are arguably the
-- client's fault and would be better as 4xx. Parity wins here: the frontend
-- reads @data.error@ for the message and only branches on @response.ok@, so
-- changing these would alter behaviour for no gain while the two backends are
-- meant to be interchangeable. Worth revisiting once the Go backend is retired.
errorStatus :: AppError -> Int
errorStatus = \case
  InvalidRequest _ -> 400
  _ -> 500

-- | Convert to the error Servant will send.
--
-- The body is @{\"error\": \"…\"}@ with a JSON content type, matching Go's
-- @errorResponse@ struct — the shape @frontend/api.ts@ parses.
--
-- Servant's own @err400@ and @err500@ default to a @text\/plain@ body, so both
-- the body and the header have to be replaced; leaving the default header is
-- the usual reason a Servant error body arrives at the browser as unparsed
-- text.
toServantError :: AppError -> ServerError
toServantError appError =
  template
    { errBody = encode (object ["error" .= errorMessage appError])
    , errHeaders = [("Content-Type", "application/json;charset=utf-8")]
    }
  where
    template = case errorStatus appError of
      400 -> err400
      _ -> err500
