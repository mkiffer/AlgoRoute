{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/routefinding/bidirectional_dijkstra_test.go@.
module Routefinding.BidirectionalSpec (spec) where

import Data.Map.Strict qualified as Map
import Graph (Edge (..), Network, NodeID (..))
import Routefinding.Bidirectional (bidirectionalDijkstra, reverseAdjacency)
import Routefinding.Dijkstra (dijkstra)
import Routefinding.Types (RouteError (..), RouteResult (..))
import Test.Hspec
import TestSupport (EdgeSpec (..), mustNetwork, mustRight, shouldBeApprox)

spec :: Spec
spec = do
  describe "Routefinding.Bidirectional.bidirectionalDijkstra" $ do
    it "finds the shortest path" $ do
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
      result <- mustRight (bidirectionalDijkstra net (NodeID 1) (NodeID 3))
      result.path `shouldBe` map NodeID [1, 2, 3]
      result.distance `shouldBeApprox` 2

    it "reports an error when the goal is unreachable" $ do
      let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1]
      bidirectionalDijkstra net (NodeID 1) (NodeID 3)
        `shouldBe` Left (NoPathFound (NodeID 1) (NodeID 3))

    it "respects edge direction" $ do
      -- The backward search walks reversed edges, which is exactly where a
      -- bidirectional implementation is most likely to accidentally traverse a
      -- one-way street the wrong way. A one-way 1→2 must stay unroutable as 2→1.
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      bidirectionalDijkstra net (NodeID 2) (NodeID 1)
        `shouldBe` Left (NoPathFound (NodeID 2) (NodeID 1))

    it "returns a trivial path when start equals goal" $ do
      let net = mustNetwork [1] []
      result <- mustRight (bidirectionalDijkstra net (NodeID 1) (NodeID 1))
      result.path `shouldBe` [NodeID 1]
      result.distance `shouldBeApprox` 0

    it "records both the start and the goal among the visited nodes" $ do
      result <- mustRight (bidirectionalDijkstra corridor (NodeID 1) (NodeID 9))
      result.visitedNodes `shouldContain` [NodeID 1]
      result.visitedNodes `shouldContain` [NodeID 9]

    describe "against Dijkstra on a long corridor" $ do
      it "agrees on the optimal distance" $ do
        -- The correctness claim. Stopping at the first frontier meeting rather
        -- than when topForward + topBackward >= mu is the classic bug, and it
        -- shows up here as a distance that is too large.
        viaBoth <- mustRight (bidirectionalDijkstra corridor (NodeID 1) (NodeID 9))
        viaOne <- mustRight (dijkstra corridor (NodeID 1) (NodeID 9))
        viaBoth.distance `shouldBeApprox` viaOne.distance

      it "agrees on the path" $ do
        viaBoth <- mustRight (bidirectionalDijkstra corridor (NodeID 1) (NodeID 9))
        viaOne <- mustRight (dijkstra corridor (NodeID 1) (NodeID 9))
        viaBoth.path `shouldBe` viaOne.path

      it "settles fewer nodes than Dijkstra" $ do
        -- The performance claim, and the reason the algorithm exists. Both
        -- frontiers only have to travel half the distance, so on a graph with
        -- dead ends hanging off the corridor the two-sided search skips most of
        -- what Dijkstra is forced to expand.
        viaBoth <- mustRight (bidirectionalDijkstra corridor (NodeID 1) (NodeID 9))
        viaOne <- mustRight (dijkstra corridor (NodeID 1) (NodeID 9))
        length viaBoth.visitedNodes
          `shouldSatisfy` (< length viaOne.visitedNodes)

  describe "Routefinding.Bidirectional.reverseAdjacency" $ do
    it "flips every edge" $ do
      let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 7, EdgeSpec 2 3 9]
          reversed = reverseAdjacency net
      map (.to) (Map.findWithDefault [] (NodeID 2) reversed) `shouldBe` [NodeID 1]
      map (.weight) (Map.findWithDefault [] (NodeID 3) reversed) `shouldBe` [9]

    it "leaves a node with no incoming edges absent" $ do
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      Map.lookup (NodeID 1) (reverseAdjacency net) `shouldBe` Nothing

-- | A corridor 1→2→…→9 with an expensive dead-end branch off node 2.
--
-- Dijkstra expands radially from node 1 and must settle the whole branch before
-- it gets far enough along the corridor; the backward search reaches the middle
-- from the other end without ever seeing it.
corridor :: Network
corridor = mustNetwork ([1 .. 9] <> [10 .. 14]) (chain <> deadEnd)
  where
    chain = concat [[EdgeSpec a b 1, EdgeSpec b a 1] | (a, b) <- zip [1 .. 8] [2 .. 9]]
    -- A branch hanging off node 2, cheap enough that Dijkstra settles all of it
    -- before reaching the goal.
    deadEnd =
      concat
        [ [EdgeSpec a b 1, EdgeSpec b a 1]
        | (a, b) <- zip (2 : [10 .. 13]) [10 .. 14]
        ]
