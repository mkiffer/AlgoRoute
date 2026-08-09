{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Services.Routing
-- Description : The address-to-route pipeline.
--
-- Ports @backend/services/address_routing.go@, @routing.go@,
-- @address_options.go@ and @load_network.go@.
--
-- This is where the whole backend comes together: seven steps, each of which
-- can fail, composed into one @do@ block that reads top to bottom.
module Services.Routing
  ( -- * Requests and results
    RouteRequest (..)
  , RouteOutcome (..)

    -- * The pipeline
  , routeByAddress

    -- * File-based routing (CLI mode)
  , loadNetworkFromFile

    -- * Tuning constants
  , bboxPaddingDegrees
  , maxBBoxAreaKm2
  ) where

import App.Env (AppM, Env (..), Endpoints (..), attempt, failWith)
import App.Error (AppError (..))
import Control.Monad (when)
import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Geo.BBox qualified as BBox
import Geo.Geocode (geocode)
import Geo.Types (BBox, Coord)
import Graph (Network, Node, NodeID)
import Graph qualified
import Graph.Snap (nearestNode)
import Mapping (BuildOptions, buildNetwork)
import Overpass.Client (fetchFromAPI, loadFromFile)
import Overpass.Types (Response (..))
import Routefinding.Router (Algorithm, runRouter)
import Routefinding.Types (RouteResult (..))
import Services.Cache (insertCache, lookupCache)

-- | Padding added around the two geocoded points when building the query box.
--
-- 0.01° is roughly 1 km. Without it, a geocode that lands 200 m from the
-- nearest mapped road can produce a box containing no usable network at all.
bboxPaddingDegrees :: Double
bboxPaddingDegrees = 0.01

-- | Largest bounding box we will ask Overpass for, in km².
--
-- 500 km² is about a 22 km square — generous for city routing. The limit exists
-- because a Melbourne→Geelong request spans roughly 1,800 km², and that
-- response can exceed 100 MB and take the process out of memory. Rejecting the
-- request before the fetch is cheaper than surviving the fetch.
maxBBoxAreaKm2 :: Double
maxBBoxAreaKm2 = 500

-- | An address-to-address routing request.
--
-- Compare Go's @AddressRouteRequest@, which also carries @GeocoderBaseURL@,
-- @DestGeocoderBaseURL@ and @OverpassBaseURL@ — three fields that production
-- always leaves empty and only tests ever set. Those now live in
-- 'App.Env.Endpoints', so this type describes the request and nothing else.
--
-- @algorithm@ is an 'Algorithm', not a 'Text'. Parsing happens once at the HTTP
-- boundary, so by the time a request reaches this module an invalid algorithm
-- name is not something that can still go wrong.
data RouteRequest = RouteRequest
  { origin :: !Text
  , destination :: !Text
  , algorithm :: !Algorithm
  , buildOptions :: !BuildOptions
  }
  deriving stock (Eq, Show)

-- | A completed route.
--
-- @pathNodes@ and @visitedNodes@ carry whole 'Node' values rather than bare
-- IDs, so the HTTP layer can serialise coordinates without a second lookup —
-- the same reason Go's @AddressRouteResult@ does it.
--
-- @originCoord@ and @destinationCoord@ are the /geocoded/ points, not the
-- snapped nodes. The frontend draws both: the pin where the user asked for, and
-- the polyline starting wherever the road network actually begins.
data RouteOutcome = RouteOutcome
  { algorithm :: !Algorithm
  , distanceMeters :: !Double
  , pathNodes :: ![Node]
  , visitedNodes :: ![Node]
  , originCoord :: !Coord
  , destinationCoord :: !Coord
  }
  deriving stock (Eq, Show)

-- | Geocode, fetch, build, snap, search, enrich.
--
-- __Read the @do@ block.__ Every line either binds a value or fails the whole
-- request. There is no error checking between the steps because 'AppM' carries
-- an 'ExceptT': the first 'throwError' abandons the rest of the block. The Go
-- equivalent is the same seven steps interleaved with eight
-- @if err != nil { return …, fmt.Errorf(…) }@ blocks — the same control flow,
-- with the failure path written out by hand.
--
-- If you have written C#: this reads like @await@-ing seven calls in a @try@,
-- except the failure type is in the signature rather than in documentation.
--
-- __The steps__, matching the numbered comments in @address_routing.go@:
--
-- 1. Geocode both addresses (two Nominatim calls).
-- 2. Build a padded box around them, and reject it if too large.
-- 3. Fetch the road network — from cache when the same box has been seen.
-- 4. Build a graph from the OSM elements.
-- 5. Snap both coordinates to their nearest graph nodes.
-- 6. Run the chosen algorithm.
-- 7. Attach coordinates to the resulting node IDs for rendering.
routeByAddress :: RouteRequest -> AppM RouteOutcome
routeByAddress request = do
  -- 1. Both endpoints, geocoded. The address is threaded into the error so the
  --    message can say *which* one failed — Go's "geocode origin:" prefix.
  from <- geocodeAddress "origin" request.origin
  to <- geocodeAddress "destination" request.destination

  -- 2. A box containing both, padded, and small enough to be worth asking for.
  let bbox = BBox.fromCoords from to bboxPaddingDegrees
      areaKm2 = BBox.approxAreaKm2 bbox
  when (areaKm2 > maxBBoxAreaKm2) $
    throwError (AreaTooLarge areaKm2 maxBBoxAreaKm2)

  -- 3. Road data, from the cache when we can.
  response <- fetchRoadData bbox

  -- An empty way list is not an error from Overpass' point of view, but there
  -- is nothing to route on, and "no path found" would be a misleading message.
  when (null response.ways) $ throwError NoRoadsInArea

  -- 4. OSM elements to a routable graph.
  (network, _stats) <-
    failWith NetworkBuildFailed (buildNetwork request.buildOptions response)

  -- 5. Project both coordinates onto the network.
  startNode <- failWith (SnapFailed "origin") (nearestNode network from)
  goalNode <- failWith (SnapFailed "destination") (nearestNode network to)

  -- 6. The search itself — the only pure step, and the only one that is
  --    genuinely about routing rather than about plumbing.
  result <-
    failWith RoutingFailed (runRouter request.algorithm network startNode goalNode)

  -- 7. Node IDs to nodes-with-coordinates, so the HTTP layer can draw them.
  pure
    RouteOutcome
      { algorithm = request.algorithm
      , distanceMeters = result.distance
      , pathNodes = resolveNodes network result.path
      , visitedNodes = resolveNodes network result.visitedNodes
      , originCoord = from
      , destinationCoord = to
      }

-- | Geocode one address, labelling any failure with which address it was.
geocodeAddress :: Text -> Text -> AppM Coord
geocodeAddress label address = do
  env <- ask
  attempt
    (GeocodeFailed label)
    (geocode env.httpManager env.endpoints.nominatimSearch address)

-- | Return the cached road network for this box, or fetch and cache it.
--
-- The cache is keyed by box rather than by address pair on purpose: two
-- different address pairs that happen to produce the same box — for instance
-- the same route requested in reverse — share the fetch.
fetchRoadData :: BBox -> AppM Response
fetchRoadData bbox = do
  env <- ask
  cached <- liftIO (lookupCache env.networkCache bbox)
  case cached of
    Just response -> pure response
    Nothing -> do
      response <-
        attempt
          RoadDataUnavailable
          (fetchFromAPI env.httpManager env.endpoints.overpassInterpreter bbox)
      liftIO (insertCache env.networkCache bbox response)
      pure response

-- | Attach coordinates to a list of node IDs.
--
-- 'mapMaybe' silently drops IDs the network does not contain. That cannot
-- happen — every ID came out of a search over this very network — but writing
-- it this way means a future bug produces a slightly short polyline rather than
-- a crash. Go's @network.Nodes[nodeID]@ would instead insert a zero-valued node
-- at coordinate (0, 0), drawing a line to the Atlantic.
resolveNodes :: Network -> [NodeID] -> [Node]
resolveNodes network = mapMaybe (`Graph.lookupNode` network)

-- | Build a network from a saved Overpass JSON file.
--
-- Ports @services/load_network.go@, and backs the CLI mode of the executable —
-- routing against a fixture with no network access, which is how the original
-- Go program was used before it grew a server.
--
-- Plain 'IO' rather than 'AppM': it needs no environment, and saying so in the
-- type means the CLI path can call it without constructing one.
loadNetworkFromFile :: FilePath -> BuildOptions -> IO (Either AppError Network)
loadNetworkFromFile path options = do
  loaded <- loadFromFile path
  pure $ case loaded of
    Left err -> Left (RoadDataUnavailable err)
    Right response -> case buildNetwork options response of
      Left err -> Left (NetworkBuildFailed err)
      Right (network, _stats) -> Right network
