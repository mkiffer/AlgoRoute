{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Graph
-- Description : The directed road network: nodes, weighted edges, adjacency.
--
-- Ports @backend/graph/@ — @node_id.go@, @node.go@, @edge.go@ and
-- @network.go@ — into one module, because in Haskell there is no reason to
-- spread four tiny declarations across four files.
--
-- The central design difference from Go: a 'Network' here is an /immutable
-- value/. Go's @AddNode@ and @AddEdge@ mutate a @*Network@ in place and return
-- an error; the equivalents here take a network and return a new one. Nothing
-- is copied wholesale — @Data.Map@ is a persistent balanced tree, so inserting
-- into a map of /n/ entries shares all but O(log n) of the structure with the
-- original. Building a 40,000-node network this way is not meaningfully slower
-- than mutating one, and it buys total freedom from aliasing bugs.
module Graph
  ( -- * Identifiers
    NodeID (..)

    -- * Structure
  , Node (..)
  , Edge (..)
  , Network (..)
  , GraphError (..)

    -- * Construction
  , empty
  , addNode
  , addEdge
  , addEdges
  , finalizeAdjacency

    -- * Queries
  , neighbours
  , lookupNode
  , nodeCount
  , edgeCount
  ) where

import Data.Int (Int64)
import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Geo.Types (Coord)

-- | An OpenStreetMap node identifier.
--
-- Go writes @type NodeID int64@, which creates a distinct named type. The
-- Haskell equivalent is a @newtype@, not @type@: a bare @type NodeID = Int64@
-- would be a transparent synonym, letting you pass a way ID where a node ID is
-- expected. The newtype makes that a compile error and costs nothing at
-- runtime — GHC erases the wrapper entirely.
newtype NodeID = NodeID {unNodeID :: Int64}
  deriving stock (Eq, Ord)
  deriving newtype (Show)

-- | A graph vertex: an OSM node ID paired with its position.
data Node = Node
  { nodeId :: !NodeID
  , coord :: !Coord
  }
  deriving stock (Eq, Show)

-- | A directed, weighted edge, carrying the OSM metadata needed to describe
-- the road it came from.
--
-- @weight@ is the Haversine length of the road segment in metres. The way ID
-- and name are not used by the search algorithms; they exist so a future
-- turn-by-turn feature has something to print, exactly as in Go.
data Edge = Edge
  { from :: !NodeID
  , to :: !NodeID
  , weight :: !Double
  , wayId :: !Int64
  , name :: !Text
  }
  deriving stock (Eq, Show)

-- | The road network: every node by ID, and every node's outgoing edges.
--
-- Two maps rather than one map of @(Node, [Edge])@ because the two are read at
-- different times — @nodes@ for coordinate lookups during snapping and result
-- enrichment, @adjacency@ during the search loop — and keeping them separate
-- avoids touching edge lists when only a coordinate is wanted.
data Network = Network
  { nodes :: !(Map NodeID Node)
  , adjacency :: !(Map NodeID [Edge])
  }
  deriving stock (Eq, Show)

-- | Why an edge could not be added.
--
-- Go returns @error@, an interface satisfied by any type with an @Error()@
-- method — so the caller learns what went wrong only by reading the message
-- string. A closed sum type says it in the type instead: a caller can pattern
-- match on 'MissingFromNode' and handle it differently from 'NegativeWeight',
-- and the compiler will tell them if a new constructor appears.
data GraphError
  = -- | @addEdge@ referenced a source node not in the network.
    MissingFromNode !NodeID
  | -- | @addEdge@ referenced a target node not in the network.
    MissingToNode !NodeID
  | -- | Dijkstra and A* both require non-negative weights.
    NegativeWeight !Double
  deriving stock (Eq, Show)

-- | The empty network. Go's @NewNetwork()@; a plain value here, since there is
-- no allocation to perform.
empty :: Network
empty = Network {nodes = Map.empty, adjacency = Map.empty}

-- | Insert a node, replacing any existing node with the same ID.
--
-- Like Go, this also ensures the adjacency map has a key for the node, so
-- 'neighbours' can never be asked about a node that exists but has no entry.
-- @insertWith (\\_ old -> old)@ means "insert @[]@ only if absent" — it keeps
-- any edges already recorded for this ID, which matters because "Mapping" adds
-- the same node many times as it walks overlapping ways.
addNode :: Node -> Network -> Network
addNode node net =
  net
    { nodes = Map.insert node.nodeId node net.nodes
    , adjacency = Map.insertWith (\_new old -> old) node.nodeId [] net.adjacency
    }

-- | Insert a directed edge, validating it first.
--
-- The three checks are Go's, unchanged: both endpoints must already be nodes
-- in the network, and the weight must be non-negative (Dijkstra's optimality
-- proof depends on it — a negative edge can make an already-settled node
-- reachable more cheaply, and the algorithm never revisits it).
--
-- Returning @Either GraphError Network@ rather than mutating means the caller
-- cannot accidentally use a half-updated network after a failure: on 'Left'
-- there simply is no new network to use.
--
-- Note the edge is /prepended/ to the node's list, where Go appends. Appending
-- to a linked list is O(n), so doing it per edge would make network
-- construction quadratic. Callers that care about insertion order run
-- 'finalizeAdjacency' once at the end; see its documentation.
addEdge :: Edge -> Network -> Either GraphError Network
addEdge edge net
  | not (Map.member edge.from net.nodes) = Left (MissingFromNode edge.from)
  | not (Map.member edge.to net.nodes) = Left (MissingToNode edge.to)
  | edge.weight < 0 = Left (NegativeWeight edge.weight)
  | otherwise =
      Right net {adjacency = Map.insertWith (<>) edge.from [edge] net.adjacency}

-- | Add many edges, stopping at the first failure.
--
-- @foldl'@ with an @Either@ accumulator is the Haskell shape of Go's
-- @for … { if err := …; err != nil { return err } }@. The @'@ in @foldl'@ is
-- not cosmetic: it forces each intermediate network, so a long fold does not
-- build a tower of unevaluated thunks.
addEdges :: [Edge] -> Network -> Either GraphError Network
addEdges edges net0 = foldl' step (Right net0) edges
  where
    step acc edge = acc >>= addEdge edge

-- | Restore insertion order in every adjacency list.
--
-- 'addEdge' prepends for speed, which leaves each list in reverse insertion
-- order. Run this once when construction is complete and the lists read the
-- way Go's do.
--
-- This is not cosmetic. When two neighbours tie on priority, the order they
-- were pushed onto the heap decides which is settled first, which changes the
-- @visited_nodes@ animation the frontend draws — and, on a graph with equal-cost
-- alternative routes, which of them is returned. Reversing here means the
-- Haskell backend and the Go backend agree node-for-node, not merely on total
-- distance.
finalizeAdjacency :: Network -> Network
finalizeAdjacency net = net {adjacency = Map.map reverse net.adjacency}

-- | Outgoing edges of a node; @[]@ for an unknown node.
--
-- Go relies on a missing map key yielding the zero value (@nil@ slice); here
-- 'Map.findWithDefault' says the same thing explicitly.
neighbours :: NodeID -> Network -> [Edge]
neighbours nodeID net = Map.findWithDefault [] nodeID net.adjacency

-- | Look up a node by ID.
--
-- The 'Maybe' is the point. Go's @net.Nodes[id]@ silently returns a zero-value
-- @Node@ for an unknown ID — a bug that surfaces later as a route through
-- coordinate (0, 0) in the Gulf of Guinea. Here the caller must acknowledge
-- the absent case.
lookupNode :: NodeID -> Network -> Maybe Node
lookupNode nodeID net = Map.lookup nodeID net.nodes

-- | Number of nodes in the network.
nodeCount :: Network -> Int
nodeCount net = Map.size net.nodes

-- | Total number of directed edges. A two-way street contributes 2.
edgeCount :: Network -> Int
edgeCount net = sum (map length (Map.elems net.adjacency))
