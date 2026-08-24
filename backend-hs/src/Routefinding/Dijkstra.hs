-- | Dijkstra's shortest path. Port of Go @routefinding/dijkstra.go@.
--
-- THE key translation: the Go @for openSet.Len() > 0@ loop mutates
-- @bestKnownCostTo@, @arrivedViaNode@, the heap and @visitedOrder@ on each
-- pass. Here that becomes a tail-recursive @go@ helper whose \"loop variables\"
-- are its arguments, and which returns the next call's arguments. \"Loop state\"
-- becomes \"function parameters.\"
module Routefinding.Dijkstra
  ( dijkstra
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import Graph (Network, NodeID)
import Routefinding.Types (RouteError (..), RouteResult (..))

-- | Shortest path from @start@ to @goal@; 'Left' 'NoPathFound' if unreachable.
--
-- Suggested shape (fill in the @where@ helpers):
--
-- @
-- dijkstra net start goal
--   | start == goal = Right (RouteResult [start] 0 [start])
--   | otherwise     = go initialHeap initialCosts Map.empty []
--   where
--     go heap costs parents visited = case popMin heap of
--       Nothing -> Left NoPathFound          -- heap drained, goal never settled
--       Just ((current, _), heap')
--         | current == goal -> Right (reconstruct costs parents (current : visited))
--         | otherwise       -> go heap'' costs' parents' (current : visited)
--         where (heap'', costs', parents') = relaxNeighbours current heap' costs parents
-- @
--
-- Notes:
--   * @initialCosts@: 0 for @start@; every other node effectively +∞ (represent
--     \"unknown\" as absence from the map, or use a big sentinel — your call).
--   * @relaxNeighbours@: fold over @neighbours current net@; for each edge, if
--     @cost current + weight < cost to@, update @costs@/@parents@ and either
--     'insert' or 'decreaseKey' in the heap.
--   * @reconstruct@: walk @parents@ from @goal@ back to @start@, reverse it,
--     and remember @visited@ is accumulated newest-first (reverse it too).
--     A* differs from this by ONE line — the heap priority. Keep them parallel.
dijkstra :: Network -> NodeID -> NodeID -> Either RouteError RouteResult
dijkstra = undefined

-- Suggested private helper — delete if you inline it.
-- Represents \"best known cost to each node.\"
_initialCosts :: NodeID -> Map NodeID Double
_initialCosts start = Map.singleton start 0
