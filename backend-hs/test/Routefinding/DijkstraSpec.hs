{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/routefinding/dijkstra_test.go@.
module Routefinding.DijkstraSpec (spec) where

import Graph (NodeID (..))
import Routefinding.Dijkstra (dijkstra)
import Routefinding.Types (RouteError (..), RouteResult (..))
import Test.Hspec
import TestSupport (EdgeSpec (..), mustNetwork, mustRight, shouldBeApprox)

spec :: Spec
spec = describe "Routefinding.Dijkstra.dijkstra" $ do
  describe "path finding" $ do
    it "finds the unique shortest path over a cheaper-looking direct edge" $ do
      -- 1→2→3 costs 2. A direct 1→3 costs 5, and a third route 1→4→5→3 costs 6.
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
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 3))
      result.path `shouldBe` map NodeID [1, 2, 3]
      result.distance `shouldBeApprox` 2

    it "chooses the cheapest of several outgoing options" $ do
      let net =
            mustNetwork
              [1, 2, 3, 4]
              [EdgeSpec 1 2 10, EdgeSpec 1 3 1, EdgeSpec 3 4 1, EdgeSpec 2 4 1]
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 4))
      result.path `shouldBe` map NodeID [1, 3, 4]
      result.distance `shouldBeApprox` 2

    it "reports an error when the goal is unreachable" $ do
      let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1]
      dijkstra net (NodeID 1) (NodeID 3)
        `shouldBe` Left (NoPathFound (NodeID 1) (NodeID 3))

    it "respects edge direction" $ do
      -- A one-way 1→2 must not be traversable as 2→1.
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      dijkstra net (NodeID 2) (NodeID 1)
        `shouldBe` Left (NoPathFound (NodeID 2) (NodeID 1))

    it "returns a trivial path when start equals goal" $ do
      let net = mustNetwork [1] []
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 1))
      result.path `shouldBe` [NodeID 1]
      result.distance `shouldBeApprox` 0

    it "reports an error for a node that is not in the network" $ do
      -- Go has no equivalent: net.Nodes[goal] yields a zero-valued node and the
      -- search silently heads for coordinate (0, 0).
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      dijkstra net (NodeID 1) (NodeID 99)
        `shouldBe` Left (NodeNotInNetwork (NodeID 99))

  describe "visited nodes" $ do
    let chain = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1, EdgeSpec 2 3 1]

    it "starts at the start node" $ do
      -- The start is pushed with cost 0, and no cheaper path to it can exist,
      -- so it is always settled first.
      result <- mustRight (dijkstra chain (NodeID 1) (NodeID 3))
      take 1 result.visitedNodes `shouldBe` [NodeID 1]

    it "contains the goal node" $ do
      -- The search stops *because* the goal was settled, so it must be recorded.
      result <- mustRight (dijkstra chain (NodeID 1) (NodeID 3))
      result.visitedNodes `shouldContain` [NodeID 3]

    it "contains every node on the returned path" $ do
      let net =
            mustNetwork
              [1, 2, 3, 4, 5]
              [EdgeSpec 1 2 1, EdgeSpec 2 3 1, EdgeSpec 1 4 10, EdgeSpec 4 5 10]
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 3))
      mapM_ (\n -> result.visitedNodes `shouldContain` [n]) result.path

    it "is just the start node for a trivial path" $ do
      let net = mustNetwork [1] []
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 1))
      result.visitedNodes `shouldBe` [NodeID 1]

    it "never settles the same node twice" $ do
      -- With an indexed heap every node has at most one entry, so each is
      -- popped exactly once. A lazy-deletion queue would need a stale check to
      -- get this right.
      let net =
            mustNetwork
              [1, 2, 3, 4]
              [ EdgeSpec 1 2 1
              , EdgeSpec 1 3 5
              , EdgeSpec 2 3 1
              , EdgeSpec 3 4 1
              ]
      result <- mustRight (dijkstra net (NodeID 1) (NodeID 4))
      length result.visitedNodes `shouldBe` length (unique result.visitedNodes)

unique :: (Eq a) => [a] -> [a]
unique = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
