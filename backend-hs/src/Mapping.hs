{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Mapping
-- Description : Turn an Overpass response into a routable 'Graph.Network'.
--
-- Ports @backend/mapping/road_mapper.go@.
--
-- This is the layer where OSM's data model — ways as flat lists of node IDs —
-- becomes a graph of weighted directed edges, and where the @oneway@ tag is
-- interpreted.
module Mapping
  ( BuildOptions (..)
  , BuildStats (..)
  , defaultBuildOptions
  , emptyStats
  , buildNetwork

    -- * One-way tag interpretation
  , isForwardOnlyOneWay
  , isReverseOnlyOneWay
  , isExplicitlyBidirectional
  ) where

import Data.Int (Int64)
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Geo.Distance (distanceMeters)
import Graph (Edge (..), GraphError, Network, Node (..), NodeID (..))
import Graph qualified
import Overpass.Types (OsmNode (..), OsmWay (..), Response (..), tagValue)

-- | How to treat ways that carry no @oneway@ tag.
--
-- __Why this is a choice at all.__ OSM's convention is that an untagged road is
-- bidirectional, but the tag is frequently missing on roads that really are
-- one-way. Assuming bidirectional gives a connected, routable network at the
-- cost of occasionally routing the wrong way down a street; assuming one-way
-- gives a network so fragmented that many routes cannot be found. The server
-- passes 'True', matching Go's @server\/handlers.go@.
--
-- Ways with an /explicit/ @oneway@ tag always have it respected, whatever this
-- is set to.
newtype BuildOptions = BuildOptions
  { assumeBidirectional :: Bool
  }
  deriving stock (Eq, Show)

-- | Assume untagged ways are bidirectional — what the HTTP layer uses.
defaultBuildOptions :: BuildOptions
defaultBuildOptions = BuildOptions {assumeBidirectional = True}

-- | Counters describing what the build did. Diagnostics only — nothing in the
-- routing pipeline branches on them.
--
-- Go's @BuildStats@ also declares @SkippedWays@ and @NonRoutableWays@, but
-- nothing ever increments them; a field that is always zero is worse than no
-- field, so they are not reproduced here.
data BuildStats = BuildStats
  { wayCount :: !Int
  -- ^ Ways examined.
  , nodeCount :: !Int
  -- ^ Nodes in the finished network.
  , edgeCount :: !Int
  -- ^ Directed edges added. A two-way street contributes 2.
  , missingNodeRefs :: !Int
  -- ^ Ways abandoned part-way because they referenced a node Overpass did not
  -- send. Usually means the way crosses the bounding-box edge.
  }
  deriving stock (Eq, Show)

-- | All counters at zero.
emptyStats :: BuildStats
emptyStats =
  BuildStats {wayCount = 0, nodeCount = 0, edgeCount = 0, missingNodeRefs = 0}

-- | Build a routing network from a decoded Overpass response.
--
-- __The shape of the transformation.__ A way is a polyline: @[a, b, c, d]@ means
-- segments a→b, b→c and c→d. So the whole job is a fold over ways, where each
-- way folds over its consecutive pairs. Go writes this as a nested @for@ with
-- an @if i == 0 { continue }@ to skip the first index; taking
-- @zip refs (drop 1 refs)@ produces the pairs directly and the special case
-- disappears.
--
-- __Where the weights come from.__ Each segment's weight is the Haversine
-- distance between its endpoints, so \"shortest path\" means shortest in metres.
-- Weighting by travel time instead would only mean changing this one
-- expression — the algorithms neither know nor care what a weight means.
--
-- __Missing node references.__ If a way names a node Overpass did not send —
-- normal at the edge of a bounding box — the rest of that way is abandoned and
-- the counter incremented, then the next way proceeds. That is Go's @break@ out
-- of the inner loop, and it is deliberately not a hard error: a partial network
-- is still routable.
--
-- __Why the result is an 'Either'.__ 'Graph.addEdge' validates its arguments, so
-- a malformed way could in principle produce an invalid edge. In practice it
-- cannot — both endpoints are added as nodes immediately before, and Haversine
-- distance is never negative — but the error path is threaded through rather
-- than assumed away.
buildNetwork ::
  BuildOptions ->
  Response ->
  Either GraphError (Network, BuildStats)
buildNetwork options response =
  case foldl' addWay (Right (Graph.empty, emptyStats)) response.ways of
    Left err -> Left err
    Right (net, stats) ->
      Right
        ( -- Restore Go's edge insertion order; see Graph.finalizeAdjacency.
          Graph.finalizeAdjacency net
        , stats {nodeCount = Graph.nodeCount net}
        )
  where
    nodeIndex = response.nodesById

    addWay accumulated way = do
      (net, stats) <- accumulated
      addSegments way (net, stats {wayCount = stats.wayCount + 1})

    -- Walk one way's consecutive node pairs, stopping early if a reference
    -- cannot be resolved.
    addSegments way = go (consecutivePairs way.nodeRefs)
      where
        go [] state = Right state
        go ((fromRef, toRef) : remaining) (net, stats) =
          -- Resolve and insert the two endpoints one at a time, matching Go:
          -- the `from` node is added to the network even when the `to` node
          -- turns out to be missing.
          case Map.lookup fromRef nodeIndex of
            Nothing -> Right (net, bumpMissing stats)
            Just fromOsm ->
              let withFrom = Graph.addNode (toGraphNode fromOsm) net
               in case Map.lookup toRef nodeIndex of
                    Nothing -> Right (withFrom, bumpMissing stats)
                    Just toOsm -> do
                      let withBoth = Graph.addNode (toGraphNode toOsm) withFrom
                          newEdges = segmentEdges way fromOsm toOsm
                      linked <- Graph.addEdges newEdges withBoth
                      go
                        remaining
                        (linked, stats {edgeCount = stats.edgeCount + length newEdges})

    bumpMissing stats = stats {missingNodeRefs = stats.missingNodeRefs + 1}

    -- The one or two directed edges a single segment contributes.
    segmentEdges way fromOsm toOsm =
      [directed fromOsm toOsm | not (isReverseOnlyOneWay onewayTag)]
        <> [directed toOsm fromOsm | shouldAddBackward]
      where
        onewayTag = tagOrEmpty "oneway" way
        wayName = tagOrEmpty "name" way
        segmentLength = distanceMeters fromOsm.coord toOsm.coord

        directed origin destination =
          Edge
            { from = NodeID origin.nodeId
            , to = NodeID destination.nodeId
            , weight = segmentLength
            , wayId = way.wayId
            , name = wayName
            }

        -- Precedence, straight from the OSM wiki and unchanged from Go:
        --   oneway=yes|1|true    → forward only, no backward edge
        --   oneway=-1|reverse    → backward only (the forward edge is
        --                          suppressed above)
        --   oneway=no|0|false    → explicitly bidirectional
        --   (no tag)             → bidirectional iff assumeBidirectional
        shouldAddBackward =
          not (isForwardOnlyOneWay onewayTag)
            && ( isReverseOnlyOneWay onewayTag
                   || isExplicitlyBidirectional onewayTag
                   || (options.assumeBidirectional && onewayTag == "")
               )

-- | A tag's value, or @\"\"@ when absent — matching Go, where a missing map key
-- yields the zero string and the code compares against @\"\"@.
tagOrEmpty :: Text -> OsmWay -> Text
tagOrEmpty key way = fromMaybe "" (tagValue key way.tags)

-- | Adjacent elements of a list, pairwise: @[a,b,c] → [(a,b), (b,c)]@.
--
-- The whole of Go's @if i == 0 { continue }@ / @way.Nodes[i-1]@ index juggling,
-- as one expression. A list of fewer than two elements yields no pairs, which
-- is exactly right: a way with a single node describes no segment.
consecutivePairs :: [Int64] -> [(Int64, Int64)]
consecutivePairs refs = zip refs (drop 1 refs)

-- | Convert an OSM node into a graph node.
toGraphNode :: OsmNode -> Node
toGraphNode osmNode =
  Node {nodeId = NodeID osmNode.nodeId, coord = osmNode.coord}

-- | Does this @oneway@ value forbid the backward direction?
-- Documented OSM values: @yes@, @1@, @true@.
isForwardOnlyOneWay :: Text -> Bool
isForwardOnlyOneWay tag = tag `elem` ["yes", "1", "true"]

-- | Does this @oneway@ value forbid the forward direction?
-- Documented OSM values: @-1@, @reverse@. Such ways are digitised against the
-- direction of travel, so only the backward edge is legal.
isReverseOnlyOneWay :: Text -> Bool
isReverseOnlyOneWay tag = tag `elem` ["-1", "reverse"]

-- | Is this way explicitly marked as two-way?
-- Documented OSM values: @no@, @0@, @false@. An explicit tag always wins over
-- 'assumeBidirectional'.
isExplicitlyBidirectional :: Text -> Bool
isExplicitlyBidirectional tag = tag `elem` ["no", "0", "false"]
