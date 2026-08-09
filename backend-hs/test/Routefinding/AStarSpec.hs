{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/routefinding/astar_test.go@.
module Routefinding.AStarSpec (spec) where

import Data.Map.Strict qualified as Map
import Geo.Distance (distanceMeters)
import Geo.Types (Coord (..))
import Graph (Network, NodeID (..))
import Routefinding.AStar (aStar)
import Routefinding.Dijkstra (dijkstra)
import Routefinding.Types (RouteError (..), RouteResult (..))
import Test.Hspec
import TestSupport
  ( EdgeSpec (..)
  , mustNetwork
  , mustNetworkWithCoords
  , mustRight
  , shouldBeApprox
  )

spec :: Spec
spec = describe "Routefinding.AStar.aStar" $ do
  describe "path finding" $ do
    it "finds the unique shortest path" $ do
      let net =
            mustNetwork
              [1, 2, 3, 4, 5]
              [ EdgeSpec 1 2 1
              , EdgeSpec 2 3 1
              , EdgeSpec 1 3 5
              , EdgeSpec 1 4 2
              , EdgeSpec 4 5 2
              , EdgeSpec 5 3 2
              ]
      result <- mustRight (aStar net (NodeID 1) (NodeID 3))
      result.path `shouldBe` map NodeID [1, 2, 3]
      result.distance `shouldBeApprox` 2

    it "reports an error when the goal is unreachable" $ do
      let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1]
      aStar net (NodeID 1) (NodeID 3)
        `shouldBe` Left (NoPathFound (NodeID 1) (NodeID 3))

    it "respects edge direction" $ do
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      aStar net (NodeID 2) (NodeID 1)
        `shouldBe` Left (NoPathFound (NodeID 2) (NodeID 1))

    it "returns a trivial path when start equals goal" $ do
      let net = mustNetwork [1] []
      result <- mustRight (aStar net (NodeID 1) (NodeID 1))
      result.path `shouldBe` [NodeID 1]
      result.distance `shouldBeApprox` 0

  describe "with a real Haversine heuristic" $ do
    it "picks the same unique optimum as Dijkstra" $ do
      -- A straight eastward chain 1→2→3→4 with a cheap cul-de-sac hanging off
      -- node 1 to the west. Real ground distances as weights, so the chain is
      -- the only route to the goal and the optimum is unique — no tie for the
      -- two algorithms to break differently.
      viaAStar <- mustRight (aStar detourNetwork (NodeID 1) (NodeID 4))
      viaDijkstra <- mustRight (dijkstra detourNetwork (NodeID 1) (NodeID 4))
      viaAStar.path `shouldBe` map NodeID [1, 2, 3, 4]
      viaAStar.path `shouldBe` viaDijkstra.path

    it "agrees with Dijkstra on distance across a grid" $ do
      -- The property that makes A* usable: Haversine can never exceed the true
      -- road distance between two points, so the heuristic is admissible and
      -- A* returns the same optimum as Dijkstra. On this lattice many routes
      -- tie on cost, so only the distance is asserted — which is exactly the
      -- guarantee, and not more than it.
      viaAStar <- mustRight (aStar gridNetwork (NodeID 1) (NodeID 9))
      viaDijkstra <- mustRight (dijkstra gridNetwork (NodeID 1) (NodeID 9))
      viaAStar.distance `shouldBeApprox` viaDijkstra.distance

    it "settles no more nodes than Dijkstra" $ do
      -- The whole point of the heuristic. Stated as "no worse" rather than
      -- "strictly better" because a heuristic cannot help on a graph with no
      -- useful geometry — but it must never hurt.
      viaAStar <- mustRight (aStar gridNetwork (NodeID 1) (NodeID 9))
      viaDijkstra <- mustRight (dijkstra gridNetwork (NodeID 1) (NodeID 9))
      length viaAStar.visitedNodes
        `shouldSatisfy` (<= length viaDijkstra.visitedNodes)

    it "settles strictly fewer nodes than Dijkstra when cheap roads lead away from the goal" $ do
      -- The cul-de-sac is *cheap*, so Dijkstra — ordering by g alone — settles
      -- all of it before it has travelled far enough east to reach the goal.
      -- A* adds h, which makes those same nodes look expensive because they are
      -- pointing the wrong way, and never expands them.
      --
      -- Note the fixture has to be built this way round: an expensive detour
      -- proves nothing, because Dijkstra would not expand it either.
      viaAStar <- mustRight (aStar detourNetwork (NodeID 1) (NodeID 4))
      viaDijkstra <- mustRight (dijkstra detourNetwork (NodeID 1) (NodeID 4))
      length viaAStar.visitedNodes
        `shouldSatisfy` (< length viaDijkstra.visitedNodes)

  describe "visited nodes" $ do
    let chain = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1, EdgeSpec 2 3 1]

    it "starts at the start node" $ do
      result <- mustRight (aStar chain (NodeID 1) (NodeID 3))
      take 1 result.visitedNodes `shouldBe` [NodeID 1]

    it "contains the goal node" $ do
      result <- mustRight (aStar chain (NodeID 1) (NodeID 3))
      result.visitedNodes `shouldContain` [NodeID 3]

    it "is just the start node for a trivial path" $ do
      let net = mustNetwork [1] []
      result <- mustRight (aStar net (NodeID 1) (NodeID 1))
      result.visitedNodes `shouldBe` [NodeID 1]

-- | Build bidirectional edges whose weights are the real ground distance
-- between their endpoints.
--
-- Using true distances is what keeps the Haversine heuristic admissible: an
-- edge weighted below its own straight-line length would let @h@ overestimate,
-- and A*'s optimality guarantee would no longer hold. Getting this wrong in a
-- test is a good way to \"discover\" a bug that is really a broken fixture.
geoEdges :: [(Integer, Double, Double)] -> [(Integer, Integer)] -> [EdgeSpec]
geoEdges positions links =
  concat
    [ [EdgeSpec a b metres, EdgeSpec b a metres]
    | (a, b) <- links
    , let metres = distanceMeters (coordOf a) (coordOf b)
    ]
  where
    index = Map.fromList [(nodeID, Coord {lat = la, lon = lo}) | (nodeID, la, lo) <- positions]
    coordOf nodeID = index Map.! nodeID

-- | A 3×3 lattice about 1 km apart, connected to orthogonal neighbours.
--
-- > 1 2 3
-- > 4 5 6
-- > 7 8 9
gridNetwork :: Network
gridNetwork = mustNetworkWithCoords positions (geoEdges positions links)
  where
    positions =
      [ (fromIntegral (row * 3 + col + 1), -37.80 - fromIntegral row * 0.01, 144.96 + fromIntegral col * 0.01)
      | row <- [0 :: Int .. 2]
      , col <- [0 :: Int .. 2]
      ]
    links =
      [(1, 2), (2, 3), (4, 5), (5, 6), (7, 8), (8, 9)]
        <> [(1, 4), (4, 7), (2, 5), (5, 8), (3, 6), (6, 9)]

-- | A straight eastward chain to the goal, with a cheap dead-end running west.
--
-- Node 4 is the goal. Nodes 5–7 sit just west of the start, each about half the
-- distance apart that the eastward hops are — so they are the cheapest thing on
-- the frontier by cost-so-far, and the most expensive by estimated total.
detourNetwork :: Network
detourNetwork = mustNetworkWithCoords positions (geoEdges positions links)
  where
    positions =
      [ (1, -37.80, 144.960) -- start
      , (2, -37.80, 144.970)
      , (3, -37.80, 144.980)
      , (4, -37.80, 144.990) -- goal
      -- The cul-de-sac: cheap hops heading away from the goal.
      , (5, -37.80, 144.955)
      , (6, -37.80, 144.950)
      , (7, -37.80, 144.945)
      ]
    links = [(1, 2), (2, 3), (3, 4), (1, 5), (5, 6), (6, 7)]
