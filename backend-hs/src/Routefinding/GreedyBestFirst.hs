-- |
-- Module      : Routefinding.GreedyBestFirst
-- Description : Greedy best-first search — heuristic only, no path cost.
--
-- Ports @backend/routefinding/greedy_best_first.go@.
--
-- This algorithm exists in AlgoRoute as a teaching device: it is A* with the
-- @g@ term deleted, and watching it fail makes clear what that term was doing.
module Routefinding.GreedyBestFirst (greedyBestFirst) where

import Graph (Network, NodeID)
import Routefinding.Search (bestFirstSearch, haversineHeuristic)
import Routefinding.Types (RouteError, RouteResult)

-- | A path to the goal, found by always expanding whichever frontier node
-- /looks/ closest to the goal.
--
-- __The priority.__ @\\_ h -> h@. The path cost is computed and recorded — it
-- has to be, or the reported distance would be meaningless — but it is thrown
-- away when deciding what to expand next.
--
-- __Why it is not optimal.__ Admissibility of @h@ buys optimality only in
-- combination with @g@. Alone, @h@ says \"this node is 400 m from the goal\" and
-- nothing about whether reaching that node took 200 m or 20 km. So the search
-- commits to whichever corridor points most directly at the goal and follows it
-- even when it is a long way round — a dead-end street pointing the right way
-- beats a through-road pointing slightly wrong. Only when that corridor is
-- exhausted does it back out.
--
-- __What it is good for.__ Speed, when \"a route\" beats \"the route\". It usually
-- settles fewer nodes than A*, because it never expands anything sideways.
--
-- __Complexity.__ O((V + E) log V), same bound. In practice fewer settlements
-- than A*, at the cost of a longer answer.
--
-- __The reported distance is honest.__ 'Routefinding.Search' accumulates the
-- real edge-weight sum in its cost map regardless of what the priority function
-- looks at, so 'Routefinding.Types.distance' is the true length of the path
-- found — not the heuristic value that guided the search. That is what lets the
-- frontend put greedy's number next to Dijkstra's optimum and show the gap.
-- The Go implementation goes out of its way to preserve this same property.
--
-- __One consequence worth knowing.__ Because priority ignores @g@, a node can
-- be settled before its cheapest path is known, and it is never re-expanded. A
-- later relaxation may still improve its recorded cost and parent, so the
-- returned path is the best one through the nodes greedy happened to visit —
-- not the best path in the graph. This matches the Go behaviour exactly.
greedyBestFirst :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
greedyBestFirst net start goal =
  bestFirstSearch (\_ h -> h) (haversineHeuristic net goal) net start goal
