-- | A* shortest path. Port of Go @routefinding/astar.go@.
--
-- Structurally identical to "Routefinding.Dijkstra". The ONLY difference is the
-- heap priority: Dijkstra pushes @g@ (cost so far); A* pushes @g + h@ where
-- @h = distanceMeters (coord n) (coord goal)@ — the straight-line estimate to
-- the goal. @bestKnownCostTo@ still tracks pure @g@; only the priority carries
-- @h@. Being able to explain \"why is that the only change?\" is the checkpoint.
--
-- Tip: once Dijkstra works, consider factoring the shared search loop so A* is
-- \"Dijkstra with a priority function\" — but get both passing first, then
-- refactor (red → green → refactor).
module Routefinding.AStar
  ( astar
  ) where

import Graph (Network, NodeID)
import Routefinding.Types (RouteError, RouteResult)

-- | Shortest path from @start@ to @goal@ using the Haversine heuristic.
--
-- TODO: copy your Dijkstra structure; change the priority pushed into the heap
--       from @g@ to @g + distanceMeters thisCoord goalCoord@. Look @goalCoord@
--       up once (it's constant across the search) — a @where@ binding, not a
--       per-edge recompute.
astar :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
astar = undefined
