{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Routefinding.Search
-- Description : The best-first search shared by Dijkstra, A* and greedy.
--
-- This module has no counterpart in the Go backend, and that is the point.
--
-- @dijkstra.go@, @astar.go@ and @greedy_best_first.go@ are 90-line files that
-- differ in exactly one expression: the value pushed onto the heap. Go has no
-- comfortable way to abstract that — you would pass a function value into a
-- generic search and lose the readability the three separate files buy. In
-- Haskell, passing a function is the ordinary thing to do, so the shared 60%
-- lives here once and each algorithm module states only its own idea.
--
-- Read this module and you have read all three algorithms.
module Routefinding.Search
  ( bestFirstSearch
  , PriorityFn
  , Heuristic
  , noHeuristic
  , haversineHeuristic
  ) where

import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Geo.Distance (distanceMeters)
import Graph (Edge (..), Network (..), Node (..), NodeID)
import Graph qualified
import Routefinding.Heap (Entry (..), IndexedHeap)
import Routefinding.Heap qualified as Heap
import Routefinding.Types (RouteError (..), RouteResult (..))

-- | How a node's heap priority is computed from its path cost @g@ and its
-- heuristic estimate @h@.
--
-- This one function /is/ the difference between the three algorithms:
--
-- * Dijkstra — @\\g _ -> g@ — order by what the path has cost so far.
-- * A* — @\\g h -> g + h@ — order by the estimated cost of the whole journey.
-- * Greedy best-first — @\\_ h -> h@ — order by how close the goal looks,
--   ignoring what getting here cost.
--
-- Because Haskell is lazy, Dijkstra's @\\g _ -> g@ never forces its second
-- argument, so no heuristic is ever computed for it. The abstraction is free:
-- passing @haversineHeuristic@ to Dijkstra would not cost a single call to
-- 'distanceMeters'.
type PriorityFn = Double -> Double -> Double

-- | Estimated remaining cost from a node to the goal.
type Heuristic = NodeID -> Double

-- | The zero heuristic, for Dijkstra.
--
-- A heuristic that always returns 0 is trivially admissible (it never
-- overestimates), which is why A* with 'noHeuristic' /is/ Dijkstra — the two
-- are the same algorithm at different points on one dial.
noHeuristic :: Heuristic
noHeuristic _ = 0

-- | Straight-line distance to the goal, in metres.
--
-- __Admissibility.__ A great-circle distance can never exceed the length of any
-- road path between the same two points, because roads bend and the great
-- circle does not. It therefore never overestimates, which is precisely the
-- condition A* needs to be guaranteed optimal. It is also consistent (obeys the
-- triangle inequality), so no settled node ever needs revisiting — which is why
-- the search below can treat every pop as final.
--
-- Returns @0@ for a node absent from the network; callers check membership
-- before starting, so this only affects nodes that cannot be reached anyway.
haversineHeuristic :: Network -> NodeID -> Heuristic
haversineHeuristic net goal nodeID =
  case (Graph.lookupNode nodeID net, Graph.lookupNode goal net) of
    (Just here, Just there) -> distanceMeters here.coord there.coord
    _ -> 0

-- | Everything the search loop carries between iterations.
--
-- Go declares four mutable locals — @openSet@, @bestKnownCostTo@,
-- @arrivedViaNode@, @visitedOrder@ — and updates them in place. Here they are
-- fields of a value that each iteration returns a new version of. This is the
-- central shape change when porting a loop to Haskell: /loop state becomes
-- function parameters/.
data SearchState = SearchState
  { openSet :: !IndexedHeap
  -- ^ Frontier: discovered but not yet settled.
  , costs :: !(Map NodeID Double)
  -- ^ Best known cost from the start (@g@). __A node absent from this map has
  -- infinite cost.__ Go pre-fills every node with @math.Inf(1)@; leaving them
  -- out is the same statement, and avoids an O(n) initialisation pass over a
  -- network where most nodes are never touched.
  , parents :: !(Map NodeID NodeID)
  -- ^ For each node, the node the best known path arrived from. Walking this
  -- backwards from the goal reconstructs the route.
  , settled :: ![NodeID]
  -- ^ Settlement order, __reversed__ — prepending is O(1) and appending is
  -- O(n), so the list is built backwards and flipped once at the end.
  }

-- | Run a best-first search from @start@ to @goal@.
--
-- __Algorithm.__ Repeatedly settle the frontier node with the lowest priority,
-- then relax its outgoing edges. With an indexed heap, one entry per node,
-- every pop carries that node's final cost — so unlike a lazy-deletion queue
-- there is no stale-entry check, and a node is settled exactly once.
--
-- __Complexity.__ O((V + E) log V): each node is pushed and popped at most
-- once, each edge triggers at most one decrease-key, and every heap operation
-- is O(log V).
--
-- __Optimality.__ Guaranteed when the priority function is @g@ (Dijkstra) or
-- @g + h@ with an admissible, consistent @h@ (A*). /Not/ guaranteed for
-- @h@ alone — see "Routefinding.GreedyBestFirst".
--
-- __Termination.__ The loop stops the moment the goal is settled, exactly like
-- Go's @break@. That is safe for Dijkstra and A* for the same reason a node is
-- settled once: nothing still on the frontier can reach the goal more cheaply.
bestFirstSearch ::
  PriorityFn ->
  Heuristic ->
  Network ->
  NodeID ->
  NodeID ->
  Either RouteError RouteResult
bestFirstSearch priorityOf heuristic net start goal
  | not (present start) = Left (NodeNotInNetwork start)
  | not (present goal) = Left (NodeNotInNetwork goal)
  -- Go special-cases this before touching the heap, and so do we: a zero-length
  -- route is a legitimate answer, not a failure to find one.
  | start == goal =
      Right RouteResult {path = [start], distance = 0, visitedNodes = [start]}
  | otherwise = loop initialState
  where
    present nodeID = Map.member nodeID net.nodes

    initialState =
      SearchState
        { openSet = Heap.push start (priorityOf 0 (heuristic start)) Heap.empty
        , costs = Map.singleton start 0
        , parents = Map.empty
        , settled = []
        }

    -- One iteration of Go's `for openSet.Len() > 0`. The recursive call in the
    -- last line is the loop; `state` is what Go mutates in place.
    loop state =
      case Heap.popMin state.openSet of
        -- Frontier exhausted without reaching the goal.
        Nothing -> finish state
        Just (entry, remaining) ->
          let current = entry.node
              -- Record settlement *before* the goal check, so the goal itself
              -- appears in visitedNodes — the frontend animation ends on it.
              afterPop =
                state {openSet = remaining, settled = current : state.settled}
           in if current == goal
                then finish afterPop
                else loop (foldl' (relax current) afterPop (Graph.neighbours current net))

    -- Relax one outgoing edge: if this path to `edge.to` beats the best known
    -- one, record it and move the neighbour up the queue.
    relax current state edge
      | newCost >= costOf state edge.to = state
      | otherwise =
          state
            { costs = Map.insert edge.to newCost state.costs
            , parents = Map.insert edge.to current state.parents
            , openSet =
                if Heap.member edge.to state.openSet
                  then Heap.decreasePriority edge.to newPriority state.openSet
                  else Heap.push edge.to newPriority state.openSet
            }
      where
        newCost = costOf state current + edge.weight
        newPriority = priorityOf newCost (heuristic edge.to)

    costOf state nodeID = Map.findWithDefault infinity nodeID state.costs

    finish state =
      case Map.lookup goal state.costs of
        -- No finite cost was ever recorded for the goal: it is unreachable.
        -- This is Go's `math.IsInf(bestKnownCostTo[goal], 1)` check.
        Nothing -> Left (NoPathFound start goal)
        Just total ->
          case reconstructPath state.parents start goal (Graph.nodeCount net + 1) of
            Nothing -> Left (NoPathFound start goal)
            Just route ->
              Right
                RouteResult
                  { path = route
                  , distance = total
                  , visitedNodes = reverse state.settled
                  }

-- | Walk the parent map backwards from @goal@ to @start@.
--
-- Go accumulates into a slice and reverses it in place. Prepending to a list as
-- we walk backwards produces the same order directly, with no reversal step.
--
-- The @fuel@ counter is a deliberate addition. Go's
-- @for current := goal; current != start; current = arrivedViaNode[current]@
-- loops forever if the parent map is ever cyclic or broken — a missing key
-- yields the zero @NodeID@, which then maps to the zero @NodeID@ again. Here a
-- corrupt map costs at most @nodeCount + 1@ steps and then reports failure.
-- Bounding it costs one @Int@ and removes a class of hang.
reconstructPath :: Map NodeID NodeID -> NodeID -> NodeID -> Int -> Maybe [NodeID]
reconstructPath parentOf start goal = walk goal []
  where
    walk current acc fuel
      | current == start = Just (start : acc)
      | fuel <= 0 = Nothing
      | otherwise = case Map.lookup current parentOf of
          Nothing -> Nothing
          Just previous -> walk previous (current : acc) (fuel - 1)

-- | Positive infinity, the cost of a node not yet reached.
infinity :: Double
infinity = 1 / 0
