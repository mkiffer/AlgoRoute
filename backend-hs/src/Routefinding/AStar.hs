-- |
-- Module      : Routefinding.AStar
-- Description : A* shortest-path search with a great-circle heuristic.
--
-- Ports @backend/routefinding/astar.go@, which is @dijkstra.go@ with one
-- expression changed. Here that is literally true: the two modules differ by
-- one lambda and one argument.
module Routefinding.AStar (aStar) where

import Graph (Network, NodeID)
import Routefinding.Search (bestFirstSearch, haversineHeuristic)
import Routefinding.Types (RouteError, RouteResult)

-- | Shortest path, guided toward the goal by straight-line distance.
--
-- __The idea.__ Dijkstra orders the frontier by @g@ — what a node has cost so
-- far. A* orders it by @f = g + h@, where @h@ estimates what remains. Nodes
-- that are cheap to reach /and/ point toward the goal are expanded first, so
-- the search elongates along the goal direction instead of spreading evenly.
--
-- __The priority.__ @\\g h -> g + h@, with @h@ the Haversine distance from the
-- node to the goal.
--
-- __Why it stays optimal.__ Great-circle distance can never exceed the true
-- road distance, so @h@ never overestimates — it is /admissible/. It also obeys
-- the triangle inequality, so it is /consistent/, which is the stronger
-- property that lets the search settle each node exactly once and stop the
-- moment the goal is popped. Both hold for Haversine on any road network, so
-- A* here returns exactly the same distance as Dijkstra.
--
-- __Complexity.__ Same O((V + E) log V) worst case. The heuristic changes the
-- constant, not the bound: on a network with no useful geometry (a maze) A*
-- degenerates to Dijkstra, while on real roads it typically settles a small
-- fraction of the nodes.
--
-- __What the animation shows.__ A cone stretching from start to goal rather
-- than a circle. The @visitedNodes@ list is markedly shorter than Dijkstra's on
-- the same route — the test suite asserts exactly that.
--
-- __The dial.__ @g + h@ with @h = 0@ is Dijkstra; @g + h@ with @g@ dropped is
-- greedy best-first. A* sits between them, and is the only one of the three
-- that is both informed and optimal.
aStar :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
aStar net start goal =
  bestFirstSearch (\g h -> g + h) (haversineHeuristic net goal) net start goal
