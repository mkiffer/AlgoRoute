-- |
-- Module      : Routefinding.Dijkstra
-- Description : Dijkstra's shortest-path algorithm.
--
-- Ports @backend/routefinding/dijkstra.go@. The 90 lines of loop, cost map and
-- path reconstruction that make up the Go file live in "Routefinding.Search";
-- what is left here is the one decision that makes this Dijkstra rather than
-- A*.
module Routefinding.Dijkstra (dijkstra) where

import Graph (Network, NodeID)
import Routefinding.Search (bestFirstSearch, noHeuristic)
import Routefinding.Types (RouteError, RouteResult)

-- | Shortest path by total edge weight.
--
-- __The idea.__ Always expand the frontier node with the smallest known cost
-- from the start. Because every edge weight is non-negative, the first time a
-- node is popped, no cheaper route to it can still exist — anything still on
-- the frontier already costs at least as much, and can only get more expensive
-- from there. So each pop finalises a node, and the algorithm never revisits
-- one.
--
-- __The priority.__ @\\g _ -> g@: order purely by cost-so-far, ignore the
-- heuristic entirely. That single lambda is the whole of Dijkstra's
-- specialisation.
--
-- __Complexity.__ O((V + E) log V) with the indexed binary heap.
--
-- __Guarantee.__ Optimal — the returned path is genuinely the shortest.
--
-- __What the animation shows.__ The frontier grows as an even circle around the
-- start, because equal cost means equal radius. Dijkstra has no idea where the
-- goal is, so it explores just as eagerly in the wrong direction as the right
-- one. Comparing this to A* on the same route is the clearest demonstration of
-- what a heuristic buys.
--
-- __Precondition.__ Non-negative edge weights. 'Graph.addEdge' rejects negative
-- ones at construction time, so a 'Network' cannot violate this.
dijkstra :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
dijkstra = bestFirstSearch (\g _ -> g) noHeuristic
