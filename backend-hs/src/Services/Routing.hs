{-# LANGUAGE OverloadedStrings #-}

-- | The address-to-route orchestration pipeline plus the shared 'Env'.
-- Port of Go @services/@ (@routing.go@, @address_routing.go@, @address_options.go@).
--
-- The payoff module: Go's 7-step pipeline with an @if err != nil@ after every
-- step becomes ONE @do@ block in @ExceptT AppError IO@ that short-circuits on
-- the first 'Left' — early-return-on-error, minus the noise. 'liftEither' lifts
-- a pure 'Either' (buildNetwork, snap, run router) into that pipeline;
-- 'throwError' is the typed early return; @liftIO@ runs a plain 'IO' step.
module Services.Routing
  ( Env (..)
  , newEnv
  , AppError (..)
  , AddressRouteRequest (..)
  , AddressRouteResult (..)
  , routeByAddress
  , runRouter
  ) where

import Control.Monad.Except (ExceptT)
import Data.Text (Text)
import Network.HTTP.Client (Manager)

import Geo.Types (Coord)
import Graph (Network, Node, NodeID)
import Mapping (BuildOptions)
import Routefinding.Types (Algorithm, RouteResult)
import Services.Cache (Cache)

-- | Process-wide dependencies, created once at startup and threaded through
-- every request (≈ a scoped singleton). (Go: the 'Manager' + @NetworkCache@
-- that the @Server@ holds.) The plan calls this the @Env@ record.
data Env = Env
  { httpManager :: Manager
  , cache :: Cache
  }

-- | Build the 'Env': one TLS 'Manager', one fresh 'Cache'.
--
-- TODO: @Env <$> newManager tlsManagerSettings <*> newCache@.
--       (The @<$>@/@<*>@ applicative style mirrors the plan §5.1.)
newEnv :: IO Env
newEnv = undefined

-- | Every way the pipeline can fail, so handlers can map each to the right HTTP
-- status. (Go: the wrapped @fmt.Errorf@ messages at each step.)
data AppError
  = GeocodeFailed Text     -- ^ origin or destination did not resolve
  | AreaTooLarge Double    -- ^ bbox exceeded the 500 km² cap (carries the area)
  | FetchFailed Text       -- ^ Overpass fetch/parse failed
  | NoRoadsFound           -- ^ bbox had no driveable ways
  | BuildFailed Text       -- ^ mapping produced an invalid network
  | SnapFailed Text        -- ^ a coordinate could not be snapped to a node
  | RouteFailed Text       -- ^ the router found no path
  deriving stock (Show, Eq)

-- | Inputs to the pipeline. (Go: @AddressRouteRequest@ — minus the per-field
-- test URL overrides, which belong in test setup, not the domain type.)
data AddressRouteRequest = AddressRouteRequest
  { origin :: Text
  , destination :: Text
  , algorithm :: Algorithm
  , mapOpts :: BuildOptions
  }

-- | Pipeline output, enriched with coordinates so the HTTP layer renders a
-- polyline without a second node lookup. (Go: @AddressRouteResult@.)
data AddressRouteResult = AddressRouteResult
  { algorithm :: Algorithm
  , distanceMeters :: Double
  , path :: [Node]
  , visitedNodes :: [Node]
  , originCoord :: Coord
  , destinationCoord :: Coord
  }

-- | The full pipeline. (Go: @RoutingService.RouteByAddress@.)
--
-- Sketch (plan §6.2) — fill in each step:
--
-- @
-- routeByAddress env req = do
--   originC <- geocode  (httpManager env) baseUrl (origin req)      -- ExceptT step
--   destC   <- geocode  (httpManager env) baseUrl (destination req)
--   let box  = bboxFromCoords originC destC bboxPaddingDegrees
--   Control.Monad.when (approxAreaKm2 box > maxBBoxAreaKm2)
--       (throwError (AreaTooLarge (approxAreaKm2 box)))
--   resp    <- fetchOrCache env box                                  -- cache lookup + fetch
--   Control.Monad.when (null (ways resp)) (throwError NoRoadsFound)
--   net     <- liftEither (first BuildFailed (buildNetwork (mapOpts req) resp))
--   start   <- liftEither (first SnapFailed  (nearestNode net originC))
--   goal    <- liftEither (first SnapFailed  (nearestNode net destC))
--   result  <- liftEither (first (const (RouteFailed "no path"))
--                                (runRouter (algorithm req) net start goal))
--   pure (enrich result originC destC net)
-- @
--
-- Map each geo/overpass error into an 'AppError' as you lift it. 'fetchOrCache'
-- and 'enrich' are private @where@/top-level helpers you write.
routeByAddress :: Env -> AddressRouteRequest -> ExceptT AppError IO AddressRouteResult
routeByAddress = undefined

-- | Dispatch to the chosen algorithm — the Strategy pattern as a pure function.
-- (Go: the four @*Router@ structs behind the @Router@ interface.)
--
-- TODO: pattern-match 'Algorithm' and call 'Routefinding.Dijkstra.dijkstra' /
--       'Routefinding.AStar.astar' / greedy / bidirectional. (Only Dijkstra and
--       A* have stubs so far — add the others when you port them.)
runRouter :: Algorithm -> Network -> NodeID -> NodeID -> Either String RouteResult
runRouter = undefined
