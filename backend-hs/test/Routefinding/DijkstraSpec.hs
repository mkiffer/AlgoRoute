{-# LANGUAGE OverloadedStrings #-}

-- | Tests for "Routefinding.Dijkstra" on a hand-built network.
--
-- Uses zero-ish coordinates so edge weights are whatever we set — this keeps
-- the expected path arithmetic trivial and independent of Haversine. (The same
-- network is a good starting point for AStarSpec: with h=0 at the goal, A*
-- must return the identical path.)
module Routefinding.DijkstraSpec (spec) where

import Data.Either (isLeft)
import Test.Hspec

import Geo.Types (Coord (..))
import Graph
import Routefinding.Dijkstra (dijkstra)
import Routefinding.Types (RouteResult (..))

-- | Build a network from nodes and directed, weighted edges, failing the test
-- if any 'addEdge' is rejected. (Mirrors the Go `mustAddEdge` test helper.)
mustBuild :: [(NodeID, Double, Double)] -> [(NodeID, NodeID, Double)] -> Network
mustBuild nodeSpecs edgeSpecs =
  let withNodes = foldr addNode' emptyNetwork nodeSpecs
      addNode' (i, la, lo) = addNode (Node i (Coord la lo))
  in foldl addEdge' withNodes edgeSpecs
  where
    addEdge' net (f, t, w) =
      case addEdge (Edge f t w 0 "") net of
        Right net' -> net'
        Left err -> error ("mustBuild: " <> err)

-- A diamond: 1→2 (1.0), 1→3 (4.0), 2→4 (1.0), 3→4 (1.0).
-- Cheapest 1→4 is 1→2→4 = 2.0, not 1→3→4 = 5.0.
diamond :: Network
diamond =
  mustBuild
    [(1, 0, 0), (2, 0, 0), (3, 0, 0), (4, 0, 0)]
    [(1, 2, 1.0), (1, 3, 4.0), (2, 4, 1.0), (3, 4, 1.0)]

spec :: Spec
spec = do
  describe "Routefinding.Dijkstra.dijkstra" $ do
    it "returns a trivial path when start == goal" $
      fmap path (dijkstra diamond 1 1) `shouldBe` Right [1]

    it "finds the cheapest route through the diamond" $
      fmap path (dijkstra diamond 1 4) `shouldBe` Right [1, 2, 4]

    it "reports the correct total distance" $
      fmap distance (dijkstra diamond 1 4) `shouldBe` Right 2.0

    it "settles the start node first in visitedNodes" $
      fmap (take 1 . visitedNodes) (dijkstra diamond 1 4) `shouldBe` Right [1]

    it "fails with Left when the goal is unreachable" $ do
      let disconnected = mustBuild [(1, 0, 0), (2, 0, 0)] []
      dijkstra disconnected 1 2 `shouldSatisfy` isLeft
