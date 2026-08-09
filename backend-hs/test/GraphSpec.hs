{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/graph/tests/network_test.go@.
module GraphSpec (spec) where

import Graph
  ( Edge (..)
  , GraphError (..)
  , Node (..)
  , NodeID (..)
  , addEdge
  , addNode
  , edgeCount
  , empty
  , lookupNode
  , neighbours
  , nodeCount
  )
import Test.Hspec
import TestSupport (EdgeSpec (..), mustNetwork, node)

spec :: Spec
spec = do
  describe "Graph.addNode / addEdge" $ do
    it "records nodes and their outgoing edges" $ do
      let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 5, EdgeSpec 1 3 7]
      nodeCount net `shouldBe` 3
      map (.to) (neighbours (NodeID 1) net) `shouldBe` [NodeID 2, NodeID 3]

    it "preserves the order edges were added in" $ do
      -- Not cosmetic: tie-breaking during the search follows adjacency order,
      -- so this is what keeps visited_nodes matching the Go backend's.
      let net = mustNetwork [1, 2, 3, 4] [EdgeSpec 1 4 1, EdgeSpec 1 2 1, EdgeSpec 1 3 1]
      map (.to) (neighbours (NodeID 1) net) `shouldBe` [NodeID 4, NodeID 2, NodeID 3]

    it "gives a node with no outgoing edges an empty neighbour list" $ do
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1]
      neighbours (NodeID 2) net `shouldBe` []

    it "counts each direction of a two-way street separately" $ do
      let net = mustNetwork [1, 2] [EdgeSpec 1 2 1, EdgeSpec 2 1 1]
      edgeCount net `shouldBe` 2

    it "rejects an edge whose source node is missing" $ do
      let net = addNode (node 2) empty
          result = addEdge (edgeBetween 1 2 1) net
      result `shouldBe` Left (MissingFromNode (NodeID 1))

    it "rejects an edge whose target node is missing" $ do
      let net = addNode (node 1) empty
          result = addEdge (edgeBetween 1 2 1) net
      result `shouldBe` Left (MissingToNode (NodeID 2))

    it "rejects a negative weight" $ do
      -- Dijkstra's optimality proof depends on non-negative weights, so this is
      -- enforced at construction rather than checked in the search.
      let net = addNode (node 2) (addNode (node 1) empty)
          result = addEdge (edgeBetween 1 2 (-1)) net
      result `shouldBe` Left (NegativeWeight (-1))

  describe "Graph.lookupNode" $ do
    it "finds a node that exists" $ do
      let net = mustNetwork [1, 2] []
      fmap (.nodeId) (lookupNode (NodeID 1) net) `shouldBe` Just (NodeID 1)

    it "returns Nothing for an unknown node" $ do
      -- The improvement over Go, where net.Nodes[id] silently yields a
      -- zero-valued node at coordinate (0, 0).
      let net = mustNetwork [1, 2] []
      lookupNode (NodeID 99) net `shouldBe` Nothing

edgeBetween :: Integer -> Integer -> Double -> Edge
edgeBetween a b w =
  Edge
    { from = NodeID (fromIntegral a)
    , to = NodeID (fromIntegral b)
    , weight = w
    , wayId = 0
    , name = ""
    }
