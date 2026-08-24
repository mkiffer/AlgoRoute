-- | Shared result and error types for the routing algorithms.
-- Port of Go @routefinding/router.go@ (the @RouteResult@ struct).
--
-- The four Go @*Router@ structs implementing a @Router@ interface collapse
-- here into one 'Algorithm' sum type plus a dispatch function (see
-- "Services.Routing"). No typeclass needed — pattern-matching on 'Algorithm'
-- is the idiomatic Strategy pattern in Haskell.
module Routefinding.Types
  ( RouteResult (..)
  , RouteError (..)
  , Algorithm (..)
  , parseAlgorithm
  ) where

import Data.Text (Text)

import Graph (NodeID)

-- | Output of a routing algorithm. (Go: @routefinding.RouteResult@.)
data RouteResult = RouteResult
  { path :: [NodeID]
    -- ^ Ordered node ids from start to goal.
  , distance :: Double
    -- ^ Total edge-weight cost (metres for real OSM data).
  , visitedNodes :: [NodeID]
    -- ^ Nodes in the order they were settled — drives the frontend animation.
  }
  deriving stock (Show, Eq)

-- | Why a search failed. (Go returns a formatted @error@; a typed sum is
-- clearer and lets handlers map errors to HTTP status codes.)
data RouteError
  = NoPathFound
  deriving stock (Show, Eq)

-- | Which algorithm to run. (Go: the @Algorithm*@ string constants in
-- @services/options.go@.)
data Algorithm
  = Dijkstra
  | AStar
  | GreedyBestFirst
  | BidirectionalDijkstra
  deriving stock (Show, Eq)

-- | Parse the wire string ("dijkstra"/"astar"/"greedy"/"bidijkstra") into an
-- 'Algorithm'. 'Nothing' for an unknown value — the handler turns that into a
-- 400. (Go: the @switch@ in @NewRoutingService@.)
--
-- TODO: match the four strings; empty string may default to 'Dijkstra' like
--       the Go server does.
parseAlgorithm :: Text -> Maybe Algorithm
parseAlgorithm = undefined
