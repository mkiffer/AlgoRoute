{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Graph.Snap
-- Description : Snap an arbitrary coordinate to the nearest node in a network.
--
-- Ports @backend/graph/snap.go@.
module Graph.Snap
  ( nearestNode
  , SnapError (..)
  ) where

import Data.Map.Strict qualified as Map
import Geo.Distance (distanceMeters)
import Geo.Types (Coord)
import Graph (Network (..), Node (..), NodeID)

-- | The only way snapping can fail.
--
-- Go returns a formatted @error@ here; a single-constructor sum type carries
-- the same information with no string to parse. It exists as a type at all —
-- rather than 'Maybe' — so "App.Error" can map it to a specific HTTP message.
data SnapError
  = -- | The network contains no nodes, so there is nothing to snap to.
    EmptyNetwork
  deriving stock (Eq, Show)

-- | The node whose coordinate is closest to @target@, by Haversine distance.
--
-- __Why this exists.__ Geocoding an address gives a point on a building, not on
-- a road. The routing algorithms only understand graph nodes, so every request
-- must first project its endpoints onto the network.
--
-- __Algorithm and complexity.__ A linear scan: O(n) in the number of nodes,
-- with one Haversine call each. For the city-scale networks this backend
-- fetches — tens of thousands of nodes — that is a fraction of a millisecond,
-- and it runs twice per request against a network that took seconds to
-- download. A k-d tree or geohash grid would cut it to O(log n) but only pays
-- off at continent scale or under sustained load. Same trade-off, same
-- conclusion, as the Go comment.
--
-- __Why an error rather than a default.__ Returning a zero 'NodeID' for an
-- empty network would send a route request off to node 0, which either does not
-- exist or is some unrelated node in Africa. Failing loudly at the snap keeps
-- the bug where it happened.
--
-- __The fold.__ Go writes a @for … range@ that mutates @nearestID@ and
-- @shortestDistance@. The Haskell version threads those two values through
-- 'Map.foldlWithKey'' as an accumulator — the same loop, with the mutable
-- variables turned into function arguments. The @'@ forces the accumulator at
-- each step, so scanning 40,000 nodes does not build 40,000 nested thunks.
nearestNode :: Network -> Coord -> Either SnapError NodeID
nearestNode net target =
  case Map.foldlWithKey' closer Nothing net.nodes of
    Nothing -> Left EmptyNetwork
    Just (nodeID, _) -> Right nodeID
  where
    closer best nodeID node =
      let distance = distanceMeters target node.coord
       in case best of
            Just (_, bestDistance) | bestDistance <= distance -> best
            _ -> Just (nodeID, distance)
