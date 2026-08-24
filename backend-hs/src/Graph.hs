{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Directed graph with an adjacency list. Port of Go @graph/@
-- (@node_id.go@, @node.go@, @edge.go@, @network.go@, @snap.go@).
--
-- The Go @*Network@ is mutated in place; here the network is an immutable
-- value and \"mutation\" means returning a new 'Network'. That is the single
-- biggest mindset shift in this module — lean into it.
module Graph
  ( NodeID
  , Node (..)
  , Edge (..)
  , Network (..)
  , emptyNetwork
  , addNode
  , addEdge
  , neighbours
  , nearestNode
  ) where

import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Geo.Types (Coord)

-- | OSM node identifier. (Go: @type NodeID int64@.)
type NodeID = Int64

-- | A graph vertex: an id plus its coordinate. (Go: @graph.Node@.)
data Node = Node
  { nodeId :: NodeID
  , coord :: Coord
  }
  deriving stock (Show, Eq)

-- | A directed, weighted edge with OSM metadata. (Go: @graph.Edge@.)
data Edge = Edge
  { from :: NodeID
  , to :: NodeID
  , weight :: Double
  , wayId :: Int64
  , name :: Text
  }
  deriving stock (Show, Eq)

-- | The road network: nodes by id, and each node's outgoing edges.
-- (Go: @graph.Network@.) Use strict maps to avoid space leaks.
data Network = Network
  { nodes :: Map NodeID Node
  , adjacencyList :: Map NodeID [Edge]
  }
  deriving stock (Show, Eq)

-- | An empty network. (Go: @NewNetwork@.)
emptyNetwork :: Network
emptyNetwork = Network Map.empty Map.empty

-- | Insert a node, ensuring it has an adjacency entry so 'neighbours' never
-- has to special-case a missing key. (Go: @Network.AddNode@.)
--
-- TODO: insert into @nodes@; insert an empty edge list into @adjacencyList@
--       only if the key is absent (@Map.insertWith@ is handy here).
addNode :: Node -> Network -> Network
addNode = undefined

-- | Append an edge, or fail if an endpoint is missing or the weight is
-- negative. (Go: @Network.AddEdge@, which returns an @error@.)
--
-- 'Either' 'String' is Go's @(v, err)@: 'Left' carries the message, 'Right'
-- the updated network.
--
-- TODO: verify @edge.from@ and @edge.to@ exist in @nodes@ and @weight >= 0@,
--       then prepend/append the edge to @adjacencyList[edge.from]@.
addEdge :: Edge -> Network -> Either String Network
addEdge = undefined

-- | Outgoing edges of a node (empty list if unknown). (Go: @Network.Neighbours@.)
--
-- TODO: @Map.findWithDefault [] nodeId (adjacencyList net)@.
neighbours :: NodeID -> Network -> [Edge]
neighbours = undefined

-- | Nearest node to a coordinate by Haversine distance, for snapping a
-- geocoded point onto the graph. (Go: @graph.NearestNode@.)
--
-- 'Left' when the network is empty — there is no meaningful snap target.
--
-- TODO: fold over @nodes@ tracking the minimum @distanceMeters target coord@;
--       'Data.Map.Strict.foldr'' or 'Data.List.minimumBy' over @Map.elems@.
nearestNode :: Network -> Coord -> Either String NodeID
nearestNode = undefined
