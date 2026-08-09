{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Routefinding.Bidirectional
-- Description : Bidirectional Dijkstra — two searches meeting in the middle.
--
-- Ports @backend/routefinding/bidirectional_dijkstra.go@.
--
-- Unlike Dijkstra, A* and greedy, this one is not a re-parameterisation of
-- "Routefinding.Search": it runs two searches at once, alternating between
-- them, and its stopping rule is genuinely different. So it gets a full
-- implementation.
module Routefinding.Bidirectional
  ( bidirectionalDijkstra
  , reverseAdjacency
  ) where

import Data.List (foldl')
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Graph (Edge (..), Network (..), NodeID)
import Graph qualified
import Routefinding.Heap (Entry (..), IndexedHeap)
import Routefinding.Heap qualified as Heap
import Routefinding.Types (RouteError (..), RouteResult (..))

-- | One of the two searches. Both are ordinary Dijkstra searches; they differ
-- only in which adjacency they walk.
data Side = Side
  { heap :: !IndexedHeap
  , cost :: !(Map NodeID Double)
  -- ^ Best known cost from this side's origin. Absent means infinite.
  , prev :: !(Map NodeID NodeID)
  , done :: !(Set NodeID)
  -- ^ Settled nodes. Go keeps a @map[NodeID]bool@; 'Set' says the same thing
  -- without the redundant value.
  }

-- | The best complete route found so far, and the node it passes through.
--
-- Go calls these @mu@ and @meetingNode@ — @mu@ is the conventional name in the
-- literature for the bidirectional upper bound.
data Meet = Meet
  { best :: !Double
  , via :: !(Maybe NodeID)
  }

-- | Everything carried between iterations of the alternating loop.
data BiState = BiState
  { forward :: !Side
  , backward :: !Side
  , meet :: !Meet
  , order :: ![NodeID]
  -- ^ Settlement order from /both/ frontiers, interleaved and reversed.
  }

-- | Shortest path, searched simultaneously from both ends.
--
-- __The idea.__ A one-directional Dijkstra that travels distance @d@ settles
-- roughly everything within radius @d@ — on a planar road network, an area
-- proportional to @d²@. Two searches that meet in the middle each travel only
-- @d\/2@, so together they cover @2·(d\/2)² = d²\/2@: about half the work. The
-- animation makes this literal — two circles growing toward each other.
--
-- __The backward search.__ It must follow edges /into/ a node, so it walks a
-- reversed adjacency list built once up front by 'reverseAdjacency'. On a
-- network with one-way streets this genuinely matters: the backward search
-- traverses a one-way street in the direction traffic actually flows.
--
-- __Which side to expand.__ Whichever heap's minimum is smaller, so the two
-- frontiers advance at the same cost radius rather than one racing ahead.
--
-- __The stopping rule — the subtle part.__ Track @mu@, the cheapest complete
-- start→goal route seen so far, updated whenever a node is known to both
-- sides. Stop when
--
-- > topForward + topBackward >= mu
--
-- Any route not yet found must use at least one unsettled node from each
-- frontier, so it costs at least @topForward + topBackward@. Once that sum
-- reaches @mu@, no undiscovered route can beat the one already in hand, and the
-- search can stop. Note this is /not/ \"stop when the frontiers first touch\":
-- the first meeting point is often not on the optimal route, and stopping there
-- is the classic bug in bidirectional implementations.
--
-- __Complexity.__ O((V + E) log V) worst case, like Dijkstra. The gain is in
-- the constant, and it is real on road networks.
--
-- __Guarantee.__ Optimal, given non-negative weights.
--
-- __One difference from the Go version.__ Go builds its reversed adjacency by
-- ranging over a map, and Go randomises map iteration order, so the order of
-- edges in each reversed list varies run to run. Here it is deterministic. On
-- graphs with ties this means the Haskell backend can pick a different
-- equal-cost route than a given Go run — but it picks the /same/ one every
-- time, which the Go version cannot promise even against itself.
bidirectionalDijkstra :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
bidirectionalDijkstra net start goal
  | not (present start) = Left (NodeNotInNetwork start)
  | not (present goal) = Left (NodeNotInNetwork goal)
  | start == goal =
      Right RouteResult {path = [start], distance = 0, visitedNodes = [start]}
  | otherwise = finish (loop initialState)
  where
    present nodeID = Map.member nodeID net.nodes

    reversed = reverseAdjacency net
    forwardEdges nodeID = Graph.neighbours nodeID net
    backwardEdges nodeID = Map.findWithDefault [] nodeID reversed

    initialState =
      BiState
        { forward = newSide start
        , backward = newSide goal
        , meet = Meet {best = infinity, via = Nothing}
        , order = []
        }

    newSide origin =
      Side
        { heap = Heap.push origin 0 Heap.empty
        , cost = Map.singleton origin 0
        , prev = Map.empty
        , done = Set.empty
        }

    -- Alternate between the two searches until the stopping rule fires or
    -- either frontier runs dry.
    loop state =
      case (Heap.peekMin state.forward.heap, Heap.peekMin state.backward.heap) of
        (Just topForward, Just topBackward)
          -- Nothing still unexplored can improve on what we already have.
          | topForward.priority + topBackward.priority >= state.meet.best -> state
          | topForward.priority <= topBackward.priority ->
              continueWith (expand forwardEdges state.forward state.backward state.meet) setForward state
          | otherwise ->
              continueWith (expand backwardEdges state.backward state.forward state.meet) setBackward state
        -- A frontier is exhausted: every node reachable from that end has been
        -- settled, so no further route can appear.
        _ -> state

    continueWith Nothing _ state = state
    continueWith (Just (settledNode, side', meet')) place state =
      loop (place state side') {meet = meet', order = settledNode : state.order}

    setForward state side = state {forward = side}
    setBackward state side = state {backward = side}

    finish state =
      case state.meet.via of
        -- Go tests `math.IsInf(mu, 1)`; an unset meeting node says the same.
        Nothing -> Left (NoPathFound start goal)
        Just meetingNode ->
          case ( chainBackward state.forward.prev meetingNode start fuel
               , chainForward state.backward.prev meetingNode goal fuel
               ) of
            (Just toMeeting, Just fromMeeting) ->
              Right
                RouteResult
                  { -- drop 1 removes the duplicated meeting node.
                    path = toMeeting <> drop 1 fromMeeting
                  , distance = state.meet.best
                  , visitedNodes = reverse state.order
                  }
            _ -> Left (NoPathFound start goal)

    fuel = Graph.nodeCount net + 1

-- | Settle one node on @active@ and relax its edges.
--
-- Returns 'Nothing' only if the active heap was empty, which the caller has
-- already ruled out by peeking. @opposite@ is read-only here: its settled set
-- and cost map are consulted to detect that the two searches have met.
expand ::
  (NodeID -> [Edge]) ->
  Side ->
  Side ->
  Meet ->
  Maybe (NodeID, Side, Meet)
expand edgesOf active opposite meet0 =
  case Heap.popMin active.heap of
    Nothing -> Nothing
    Just (entry, remaining) ->
      let current = entry.node
          settledActive =
            active {heap = remaining, done = Set.insert current active.done}
          -- The node may already be settled from the other direction: that is a
          -- complete route through `current`.
          meetAfterPop
            | Set.member current opposite.done =
                recordMeeting current settledActive opposite meet0
            | otherwise = meet0
          (relaxedActive, meetAfterEdges) =
            foldl' (relax current) (settledActive, meetAfterPop) (edgesOf current)
       in Just (current, relaxedActive, meetAfterEdges)
  where
    relax current (side, meetSoFar) edge
      | newCost >= costOf side edge.to = (side, meetSoFar)
      | otherwise = (side', meet')
      where
        newCost = costOf side current + edge.weight
        side' =
          side
            { cost = Map.insert edge.to newCost side.cost
            , prev = Map.insert edge.to current side.prev
            , heap =
                if Heap.member edge.to side.heap
                  then Heap.decreasePriority edge.to newCost side.heap
                  else Heap.push edge.to newCost side.heap
            }
        -- If the opposite search has already finalised this neighbour, we now
        -- know a complete route through it.
        meet'
          | Set.member edge.to opposite.done =
              recordMeeting edge.to side' opposite meetSoFar
          | otherwise = meetSoFar

-- | Note a complete route through @nodeID@ if it beats the best so far.
-- Go's @updateMu@.
recordMeeting :: NodeID -> Side -> Side -> Meet -> Meet
recordMeeting nodeID active opposite meetSoFar =
  case (Map.lookup nodeID active.cost, Map.lookup nodeID opposite.cost) of
    (Just fromHere, Just fromThere)
      | fromHere + fromThere < meetSoFar.best ->
          Meet {best = fromHere + fromThere, via = Just nodeID}
    _ -> meetSoFar

-- | Best known cost to a node on one side; infinite if never reached.
costOf :: Side -> NodeID -> Double
costOf side nodeID = Map.findWithDefault infinity nodeID side.cost

-- | Every edge, flipped.
--
-- The backward search needs to answer \"which nodes have an edge /into/ this
-- one?\", and 'Graph.Network' only indexes outgoing edges. Building the whole
-- reversed index once is O(E); doing it lazily per node would be O(E) per
-- lookup.
--
-- Weight, way ID and name are carried across unchanged. Go drops the metadata
-- when reversing; keeping it costs nothing and means a reversed edge still
-- knows which street it is.
reverseAdjacency :: Network -> Map NodeID [Edge]
reverseAdjacency net =
  Map.fromListWith
    (flip (<>))
    [ (edge.to, [flipEdge edge])
    | edges <- Map.elems net.adjacency
    , edge <- edges
    ]
  where
    flipEdge edge =
      Edge
        { from = edge.to
        , to = edge.from
        , weight = edge.weight
        , wayId = edge.wayId
        , name = edge.name
        }

-- | Walk a parent map backwards, producing @[target … from]@ in forward order.
--
-- Used for the forward half of the route: @forward.prev@ points toward the
-- start, so walking it from the meeting node and prepending yields
-- @[start … meetingNode]@.
chainBackward :: Map NodeID NodeID -> NodeID -> NodeID -> Int -> Maybe [NodeID]
chainBackward parentOf from target = go from []
  where
    go current acc fuel
      | current == target = Just (current : acc)
      | fuel <= 0 = Nothing
      | otherwise = case Map.lookup current parentOf of
          Nothing -> Nothing
          Just parent -> go parent (current : acc) (fuel - 1)

-- | Walk a successor map forwards, producing @[from … target]@.
--
-- Used for the backward half. @backward.prev@ deserves a careful read: an entry
-- @prev[X] = Y@ was written when the backward search relaxed the /reversed/
-- edge X←Y, which means the /original/ graph contains the edge X→Y. So
-- @backward.prev@ is already a map of \"next hop toward the goal\", and walking
-- it forwards gives @[meetingNode … goal]@ in travel order — no reversal.
chainForward :: Map NodeID NodeID -> NodeID -> NodeID -> Int -> Maybe [NodeID]
chainForward nextOf from target = go from []
  where
    go current acc fuel
      | current == target = Just (reverse (current : acc))
      | fuel <= 0 = Nothing
      | otherwise = case Map.lookup current nextOf of
          Nothing -> Nothing
          Just next -> go next (current : acc) (fuel - 1)

infinity :: Double
infinity = 1 / 0
