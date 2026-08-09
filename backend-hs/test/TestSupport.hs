-- EdgeSpec below reuses Graph.Edge's field names (from/to/weight) so the test
-- fixtures read like the Go ones. DuplicateRecordFields lets both records own
-- those names; OverloadedRecordDot resolves `spec.from` by the record's type.
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : TestSupport
-- Description : Shared helpers for the HSpec suite.
--
-- The Haskell counterpart of the @must…@ helpers scattered through the Go
-- tests (@mustAddNode@, @mustAddEdge@, @assertPathEquals@) plus the
-- @httptest.Server@ stubs the service and handler tests stand up.
--
-- Naming follows the project convention: helpers that abort the test on
-- failure are prefixed @must@.
module TestSupport
  ( -- * Building networks
    EdgeSpec (..)
  , mustNetwork
  , mustNetworkWithCoords
  , node

    -- * Assertions
  , shouldBeApprox
  , mustRight

    -- * Fixtures
  , fixturePath
  , mustLoadFixture

    -- * Stub upstream servers
  , withStubUpstream
  , jsonResponse
  , statusResponse
  , routeByPath
  , lookupQuery
  ) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (foldl')
import Data.Text (Text)
import Data.Text qualified as T
import Geo.Types (Coord (..))
import Graph (Edge (..), Network, Node (..), NodeID (..))
import Graph qualified
import Network.HTTP.Types (Status, status200)
import Network.Wai (Application, Request, queryString, rawPathInfo, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)
import Overpass.Client (loadFromFile)
import Overpass.Types (Response)
import Test.Hspec (HasCallStack, expectationFailure, shouldSatisfy)

-- | A directed edge, in the shape the Go tests use.
data EdgeSpec = EdgeSpec
  { from :: !Integer
  , to :: !Integer
  , weight :: !Double
  }

-- | A node at the origin. Coordinates are irrelevant to Dijkstra, so the
-- Dijkstra and heap tests use this; A* and greedy need real geometry and use
-- 'mustNetworkWithCoords'.
node :: Integer -> Node
node nodeID = Node {nodeId = NodeID (fromIntegral nodeID), coord = Coord {lat = 0, lon = 0}}

-- | Build a network from node IDs and edges, failing the test on an invalid
-- edge. Go's @mustAddNode@ + @mustAddEdge@, as one call.
mustNetwork :: (HasCallStack) => [Integer] -> [EdgeSpec] -> Network
mustNetwork nodeIDs = mustNetworkWithCoords [(n, 0, 0) | n <- nodeIDs]

-- | As 'mustNetwork', but with explicit coordinates so heuristic-driven
-- algorithms have real geometry to work with.
mustNetworkWithCoords ::
  (HasCallStack) =>
  [(Integer, Double, Double)] ->
  [EdgeSpec] ->
  Network
mustNetworkWithCoords nodeSpecs edgeSpecs =
  case Graph.addEdges (map toEdge edgeSpecs) withNodes of
    Left err -> error ("mustNetwork: " <> show err)
    Right net -> Graph.finalizeAdjacency net
  where
    withNodes = foldl' (flip Graph.addNode) Graph.empty (map toNode nodeSpecs)

    toNode (nodeID, latitude, longitude) =
      Node
        { nodeId = NodeID (fromIntegral nodeID)
        , coord = Coord {lat = latitude, lon = longitude}
        }

    toEdge spec =
      Edge
        { from = NodeID (fromIntegral spec.from)
        , to = NodeID (fromIntegral spec.to)
        , weight = spec.weight
        , wayId = 0
        , name = ""
        }

-- | Compare two 'Double's within a tolerance.
--
-- Floating-point equality is unreliable across compilers and platforms, so
-- every numeric assertion in this suite goes through here — the same reason the
-- Go tests compare against a tolerance rather than with @==@.
shouldBeApprox :: (HasCallStack) => Double -> Double -> IO ()
shouldBeApprox actual expected =
  actual `shouldSatisfy` \x -> abs (x - expected) < tolerance
  where
    tolerance = 1e-6 * max 1 (abs expected)

-- | Unwrap an 'Either', failing the test with the error on 'Left'.
mustRight :: (HasCallStack, Show e) => Either e a -> IO a
mustRight (Right value) = pure value
mustRight (Left err) = do
  expectationFailure ("expected Right, got Left: " <> show err)
  error "unreachable"

-- | The shared Overpass fixture — the same three-street Melbourne sample the Go
-- tests use, copied from @backend/mapping/testdata/@ so both suites assert
-- against identical data.
fixturePath :: FilePath
fixturePath = "test/testdata/sample_overpass.json"

-- | Load and decode the fixture, failing the test if it cannot be read.
mustLoadFixture :: (HasCallStack) => IO Response
mustLoadFixture = loadFromFile fixturePath >>= mustRight

-- | Run an action against a stub upstream server on a free local port.
--
-- Replaces Go's @httptest.NewServer@. 'testWithApplication' picks an unused
-- port, starts Warp, hands the port to the action, and shuts the server down
-- afterwards even if the action throws.
--
-- The action receives the base URL, which the test puts into an
-- 'App.Env.Endpoints' — the same mechanism production uses to point at the real
-- Nominatim and Overpass. No test-only code path is involved.
withStubUpstream :: Application -> (Text -> IO a) -> IO a
withStubUpstream app action =
  testWithApplication (pure app) $ \port ->
    action (T.pack ("http://127.0.0.1:" <> show port))

-- | An application that answers every request with the same JSON body.
jsonResponse :: LBS.ByteString -> Application
jsonResponse = statusResponse status200

-- | An application that answers every request with a fixed status and body.
statusResponse :: Status -> LBS.ByteString -> Application
statusResponse status body _request respond =
  respond (responseLBS status [("Content-Type", "application/json")] body)

-- | Dispatch to different stub applications by request path.
--
-- Lets one stub server stand in for both Nominatim and Overpass, which is how
-- the pipeline and handler tests avoid running three separate servers.
routeByPath :: [(BS.ByteString, Application)] -> Application -> Application
routeByPath routes fallback request respond =
  case lookup (rawPathInfo request) routes of
    Just app -> app request respond
    Nothing -> fallback request respond

-- | Read a query parameter from a request inside a stub handler.
--
-- Lets one stub give different answers to different queries — returning one
-- coordinate for the origin address and another for the destination, which Go
-- can only do by running two separate stub servers and threading two base URLs
-- through the whole call stack.
lookupQuery :: BS.ByteString -> Request -> Maybe BS.ByteString
lookupQuery name request =
  case lookup name (queryString request) of
    Just (Just value) -> Just value
    _ -> Nothing
