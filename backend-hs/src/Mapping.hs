{-# LANGUAGE OverloadedStrings #-}

-- | Convert an Overpass 'Response' into a routing 'Network'.
-- Port of Go @mapping/road_mapper.go@ (@BuildNetwork@ + the @isOneWay@ helpers).
--
-- The Go nested loop (ways → consecutive node pairs → edges, mutating the
-- network) becomes a 'Data.List.foldl'' over ways, where each way folds over
-- its consecutive node pairs. \"Accumulate into a Network\" replaces \"mutate a
-- *Network\". Pure — TDD against the shared @testdata/sample_overpass.json@ and
-- match the Go node/edge counts and oneway handling.
module Mapping
  ( BuildOptions (..)
  , BuildStats (..)
  , buildNetwork
  ) where

import Graph (Network)
import Overpass.Types (Response)

-- | How to treat ways with no @oneway@ tag. (Go: @mapping.BuildOptions@.)
newtype BuildOptions = BuildOptions
  { assumeBidirectional :: Bool
  }
  deriving stock (Show, Eq)

-- | Counters describing what was built/skipped. (Go: @mapping.BuildStats@.)
-- Optional to fully populate at first — the 'Network' is what routing needs.
data BuildStats = BuildStats
  { wayCount :: Int
  , nodeCount :: Int
  , edgeCount :: Int
  , skippedWays :: Int
  , missingNodeRefs :: Int
  , nonRoutableWays :: Int
  }
  deriving stock (Show, Eq)

-- | Build the network (and stats) from a response. 'Left' propagates an
-- 'Graph.addEdge' failure. (Go: @BuildNetwork@, which returns @(net, stats, err)@.)
--
-- Direction rules from the @oneway@ tag (see the Go @isForwardOnlyOneWay@ /
-- @isReverseOnlyOneWay@ / @isExplicitlyBidirectional@ helpers — port them as
-- pure @Text -> Bool@ predicates):
--   * yes|1|true      → forward edge only
--   * -1|reverse      → backward edge only
--   * no|0|false      → both directions
--   * (absent)        → both iff @assumeBidirectional@
--
-- TODO:
--   * consecutivePairs :: [Int64] -> [(Int64, Int64)]  -- @zip xs (tail xs)@
--   * for each pair look up both nodes in @nodeById@ (skip the way on a miss),
--     compute @distanceMeters@ as the weight, then 'Graph.addNode' both and
--     'Graph.addEdge' the legal direction(s).
--   * fold all of that starting from 'Graph.emptyNetwork'; thread 'BuildStats'
--     alongside if you want the counters.
buildNetwork :: BuildOptions -> Response -> Either String (Network, BuildStats)
buildNetwork = undefined
