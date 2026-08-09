{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/services/tests/address_routing_test.go@ and the
-- file-loading tests from @routing_test.go@.
module Services.RoutingSpec (spec) where

import App.Env (Endpoints (..), Env (..), newEnvWith, runAppM)
import App.Error (AppError (..), errorMessage)
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as T
import Geo.Types (Coord (..))
import Graph (Node (..), NodeID (..))
import Graph qualified
import Mapping (defaultBuildOptions)
import Network.Wai (Application, responseLBS)
import Network.HTTP.Types (status404)
import Routefinding.Router (Algorithm (..))
import Services.Cache (cacheSize)
import Services.Routing
  ( RouteOutcome (..)
  , RouteRequest (..)
  , loadNetworkFromFile
  , maxBBoxAreaKm2
  , routeByAddress
  )
import Test.Hspec
import TestSupport
  ( fixturePath
  , jsonResponse
  , lookupQuery
  , mustRight
  , routeByPath
  , shouldBeApprox
  , withStubUpstream
  )

-- Two real nodes from the fixture, and the distance the Go backend reports
-- between them. Asserting the exact number is what makes this a parity test
-- rather than a smoke test.
originAddress, destinationAddress :: Text
originAddress = "Gillon Court, Melbourne"
destinationAddress = "Estelle Street, Melbourne"

originLatLon, destinationLatLon :: (Text, Text)
originLatLon = ("-37.8916497", "145.1044461")
destinationLatLon = ("-37.8931412", "145.1069308")

goExpectedDistanceMetres :: Double
goExpectedDistanceMetres = 349.24

spec :: Spec
spec = do
  describe "Services.Routing.routeByAddress" $ do
    it "routes between two addresses through the whole pipeline" $
      withPipeline (stubUpstream Nothing) $ \env -> do
        outcome <- mustRight =<< runAppM env (routeByAddress (request Dijkstra))
        outcome.distanceMeters `shouldBeApprox` goExpectedDistanceMetres
        map (.nodeId) outcome.pathNodes
          `shouldBe` map
            NodeID
            [27347732, 27347731, 27347730, 27347728, 27347729, 271299529, 27347552]

    it "snaps each geocoded coordinate to a real network node" $
      withPipeline (stubUpstream Nothing) $ \env -> do
        outcome <- mustRight =<< runAppM env (routeByAddress (request Dijkstra))
        head outcome.pathNodes `shouldBe` Node {nodeId = NodeID 27347732, coord = (head outcome.pathNodes).coord}
        (last outcome.pathNodes).nodeId `shouldBe` NodeID 27347552

    it "returns the geocoded coordinates alongside the snapped path" $
      -- The frontend draws both: a pin where the user asked for, and a polyline
      -- starting wherever the road network actually begins.
      withPipeline (stubUpstream Nothing) $ \env -> do
        outcome <- mustRight =<< runAppM env (routeByAddress (request Dijkstra))
        outcome.originCoord.lat `shouldBeApprox` (-37.8916497)
        outcome.destinationCoord.lon `shouldBeApprox` 145.1069308

    it "records the settlement order for the traversal animation" $
      withPipeline (stubUpstream Nothing) $ \env -> do
        outcome <- mustRight =<< runAppM env (routeByAddress (request Dijkstra))
        map (.nodeId) (take 1 outcome.visitedNodes) `shouldBe` [NodeID 27347732]
        map (.nodeId) outcome.visitedNodes `shouldContain` [NodeID 27347552]

    it "gives every algorithm the same answer on this fixture" $
      withPipeline (stubUpstream Nothing) $ \env ->
        mapM_
          ( \algorithm -> do
              outcome <- mustRight =<< runAppM env (routeByAddress (request algorithm))
              outcome.distanceMeters `shouldBeApprox` goExpectedDistanceMetres
              outcome.algorithm `shouldBe` algorithm
          )
          [Dijkstra, AStar, GreedyBestFirst, BidirectionalDijkstra]

    it "fetches from Overpass once and serves the second request from cache" $
      -- Two requests for the same addresses produce the same bounding box, so
      -- only the first should reach Overpass.
      withPipeline (stubUpstream Nothing) $ \env -> do
        _ <- mustRight =<< runAppM env (routeByAddress (request Dijkstra))
        _ <- mustRight =<< runAppM env (routeByAddress (request AStar))
        cacheSize env.networkCache >>= (`shouldBe` 1)

  describe "Services.Routing.routeByAddress failure paths" $ do
    it "propagates a geocoding failure, naming which address failed" $
      withPipeline (stubUpstream (Just NoGeocodeResults)) $ \env -> do
        result <- runAppM env (routeByAddress (request Dijkstra))
        case result of
          Left err@(GeocodeFailed which _) -> do
            which `shouldBe` "origin"
            T.unpack (errorMessage err) `shouldContain` "geocode origin"
          other -> expectationFailure ("expected GeocodeFailed, got " <> show other)

    it "rejects a bounding box larger than the area limit before fetching" $
      -- A Melbourne-to-Geelong request spans ~1,800 km² and can return over
      -- 100 MB. Rejecting it up front is cheaper than surviving it.
      withPipeline (stubUpstream (Just FarApartCoords)) $ \env -> do
        result <- runAppM env (routeByAddress (request Dijkstra))
        case result of
          Left err@(AreaTooLarge actual limit) -> do
            actual `shouldSatisfy` (> maxBBoxAreaKm2)
            limit `shouldBeApprox` maxBBoxAreaKm2
            T.unpack (errorMessage err) `shouldContain` "try closer addresses"
          other -> expectationFailure ("expected AreaTooLarge, got " <> show other)

    it "reports an empty road network rather than 'no path found'" $
      -- Overpass answering with no ways is not an error from its point of view,
      -- but "no path found" would send the user hunting for a routing bug.
      withPipeline (stubUpstream (Just EmptyOverpass)) $ \env -> do
        result <- runAppM env (routeByAddress (request Dijkstra))
        case result of
          Left NoRoadsInArea -> pure ()
          other -> expectationFailure ("expected NoRoadsInArea, got " <> show other)

    it "propagates an Overpass transport failure" $
      withPipeline (stubUpstream (Just OverpassDown)) $ \env -> do
        result <- runAppM env (routeByAddress (request Dijkstra))
        case result of
          Left (RoadDataUnavailable _) -> pure ()
          other -> expectationFailure ("expected RoadDataUnavailable, got " <> show other)

  describe "Services.Routing.loadNetworkFromFile" $ do
    it "builds a populated network from a valid file" $ do
      net <- mustRight =<< loadNetworkFromFile fixturePath defaultBuildOptions
      Graph.nodeCount net `shouldSatisfy` (> 0)
      Graph.edgeCount net `shouldSatisfy` (> 0)

    it "reports an error for a missing file" $ do
      result <- loadNetworkFromFile "test/testdata/nope.json" defaultBuildOptions
      case result of
        Left (RoadDataUnavailable _) -> pure ()
        other -> expectationFailure ("expected RoadDataUnavailable, got " <> show (fmap (const ()) other))

-- | The request under test, parameterised by algorithm.
request :: Algorithm -> RouteRequest
request chosen =
  RouteRequest
    { origin = originAddress
    , destination = destinationAddress
    , algorithm = chosen
    , buildOptions = defaultBuildOptions
    }

-- | Start a stub upstream, point a fresh 'Env' at it, and run the action.
--
-- This is the whole reason endpoints live in 'Env' rather than being threaded
-- through as test-only function parameters: the pipeline under test is the
-- production pipeline, unmodified.
withPipeline :: Application -> (Env -> IO a) -> IO a
withPipeline app action =
  withStubUpstream app $ \baseUrl -> do
    env <-
      newEnvWith
        Endpoints
          { nominatimSearch = baseUrl <> "/search"
          , nominatimReverse = baseUrl <> "/reverse"
          , overpassInterpreter = baseUrl <> "/interpreter"
          }
        "."
    action env

-- | How the stub should misbehave, if at all.
data StubFault
  = NoGeocodeResults
  | FarApartCoords
  | EmptyOverpass
  | OverpassDown
  deriving stock (Eq)

-- | One stub server standing in for both Nominatim and Overpass.
--
-- Go needs three separate @httptest.Server@s here — one per base-URL override
-- field — because it has no way to tell origin and destination apart on a
-- shared server. Reading the @q@ parameter does exactly that in two lines.
stubUpstream :: Maybe StubFault -> Application
stubUpstream fault =
  routeByPath
    [ ("/search", searchApp)
    , ("/interpreter", overpassApp)
    ]
    notFound
  where
    searchApp request' respond
      | fault == Just NoGeocodeResults = jsonResponse "[]" request' respond
      | otherwise = jsonResponse (hitFor query) request' respond
      where
        query = maybe "" BS8.unpack (lookupQuery "q" request')

    hitFor query
      | fault == Just FarApartCoords =
          if isOrigin query
            then latLonHit ("-37.8136", "144.9631") -- Melbourne
            else latLonHit ("-38.1499", "144.3617") -- Geelong, ~75 km away
      | isOrigin query = latLonHit originLatLon
      | otherwise = latLonHit destinationLatLon

    isOrigin query = take 6 query == "Gillon"

    overpassApp
      | fault == Just EmptyOverpass = jsonResponse "{\"elements\":[]}"
      | fault == Just OverpassDown = \_ respond -> respond (responseLBS status404 [] "gone")
      | otherwise = \request' respond -> do
          body <- LBS.readFile fixturePath
          jsonResponse body request' respond

    notFound _ respond = respond (responseLBS status404 [] "no such stub route")

-- | A one-element Nominatim search response with string coordinates, as the
-- real API sends them.
latLonHit :: (Text, Text) -> LBS.ByteString
latLonHit (latitude, longitude) =
  "[{\"lat\":\""
    <> LBS.fromStrict (BS8.pack (T.unpack latitude))
    <> "\",\"lon\":\""
    <> LBS.fromStrict (BS8.pack (T.unpack longitude))
    <> "\",\"display_name\":\"stub\"}]"
