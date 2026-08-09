{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Overpass.Types
-- Description : The JSON shape returned by the Overpass API, as Haskell data.
--
-- Ports the DTOs in @backend/api/overpass/client.go@.
--
-- This is the module the rewrite plan singles out, and with reason: it is where
-- the difference between \"a struct with a type tag\" and \"a sum type\" is most
-- visible.
module Overpass.Types
  ( -- * Elements
    Element (..)
  , OsmNode (..)
  , OsmWay (..)
  , Tags
  , tagValue

    -- * Responses
  , Response (..)
  , emptyResponse
  , indexResponse
  ) where

import Data.Aeson (FromJSON (..), withObject, (.!=), (.:), (.:?))
import Data.Int (Int64)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Geo.Types (Coord (..))

-- | OSM tags. Free-form key-value strings — the OSM data model imposes no
-- schema, so neither does this.
type Tags = Map Text Text

-- | An OSM node: a point with an ID.
data OsmNode = OsmNode
  { nodeId :: !Int64
  , coord :: !Coord
  , tags :: !Tags
  }
  deriving stock (Eq, Show)

-- | An OSM way: an ordered list of node IDs describing a polyline, plus tags.
--
-- @nodeRefs@ holds IDs, not nodes. Overpass sends ways and nodes as separate
-- top-level elements, so resolving a reference means a lookup in
-- 'Response.nodesById'. "Mapping" does exactly that.
data OsmWay = OsmWay
  { wayId :: !Int64
  , nodeRefs :: ![Int64]
  , tags :: !Tags
  }
  deriving stock (Eq, Show)

-- | One element from an Overpass response.
--
-- __The design decision.__ Go models this as a single struct with a
-- @Type string@ tag and every field of both variants present:
--
-- > type Element struct {
-- >     Type  string
-- >     Id    int64
-- >     Lat   *float64   // only when Type == "node"
-- >     Lon   *float64   // only when Type == "node"
-- >     Nodes []int64    // only when Type == "way"
-- >     Tags  map[string]string
-- > }
--
-- Every one of those comments is a rule the compiler cannot check. Nothing
-- stops you reading @Lat@ on a way — you get a nil pointer, and the mapping
-- code has to write @if !exists || node.Lat == nil || node.Lon == nil@ at every
-- use. The struct can also represent states that do not exist in the OSM data
-- model: a way with a latitude, a node with a node list, an element whose type
-- is @\"node\"@ but whose @Lat@ is nil.
--
-- A sum type makes those states unrepresentable. Pattern matching on
-- 'NodeElement' /gives/ you a coordinate — there is no nil to check, because
-- there is no way to build a node without one. Three of the four nil checks in
-- @road_mapper.go@ simply have no counterpart in "Mapping".
--
-- If you know C# discriminated unions or F# DUs, this is exactly that, and it
-- is the single most transferable idea in the port.
--
-- __Why 'OtherElement' exists.__ Overpass can return relations, and Go's
-- @switch@ silently ignores any type it does not recognise. Failing the whole
-- parse on an unexpected type would be a regression, so unknown types decode
-- into 'OtherElement' and are skipped downstream — the same tolerance, but
-- visible in the type rather than implied by a missing @case@.
data Element
  = NodeElement !OsmNode
  | WayElement !OsmWay
  | -- | An element type this backend does not use (e.g. @relation@). Carries
    -- its type string and ID so it can be logged if it ever matters.
    OtherElement !Text !Int64
  deriving stock (Eq, Show)

-- | Look up a tag. Go's @Element.Tag@ method.
--
-- Go needs that method mainly to guard against a nil @Tags@ map; here the map
-- is always present (decoding defaults it to empty), so this is a plain
-- 'Map.lookup' under a name that documents intent.
tagValue :: Text -> Tags -> Maybe Text
tagValue = Map.lookup

-- | A decoded Overpass response, with the two indexes the mapping layer needs.
--
-- __On the derived fields.__ Go declares @Ways@, @Nodes@ and @NodeByID@ with
-- @json:\"-\"@ and fills them in a loop /after/ unmarshalling — a loop that is
-- copy-pasted into both @LoadNetworkFromJSON@ and @FetchFromAPIWithBaseURL@,
-- so a fix to one would have to be remembered in the other. Here the loop is
-- 'indexResponse', called once from the 'FromJSON' instance, so decoding a
-- response by any route produces the same indexes.
--
-- Go's @Nodes []Element@ field has no readers anywhere in the backend, so it is
-- not reproduced. @nodesById@ is the index that mapping actually uses.
data Response = Response
  { version :: !(Maybe Double)
  , generator :: !(Maybe Text)
  , elements :: ![Element]
  -- ^ Everything, in the order Overpass sent it.
  , ways :: ![OsmWay]
  -- ^ Derived: just the ways, in order. "Mapping" folds over this, and
  -- "Services.Routing" checks it is non-empty before bothering to build a
  -- network.
  , nodesById :: !(Map Int64 OsmNode)
  -- ^ Derived: O(log n) resolution of a way's node references.
  }
  deriving stock (Eq, Show)

-- | A response with no elements. Handy in tests and as a cache miss default.
emptyResponse :: Response
emptyResponse =
  Response
    { version = Nothing
    , generator = Nothing
    , elements = []
    , ways = []
    , nodesById = Map.empty
    }

-- | Populate 'ways' and 'nodesById' from 'elements'.
--
-- One pass over the element list, partitioning as it goes. Go does the same
-- with two @append@s and a map insert inside a @switch@.
indexResponse :: Response -> Response
indexResponse response =
  response
    { ways = [way | WayElement way <- response.elements]
    , nodesById =
        Map.fromList [(node.nodeId, node) | NodeElement node <- response.elements]
    }

-- | Decode an element, choosing the constructor from the @\"type\"@ field.
--
-- This is the hand-written instance the plan calls for. @aeson@ can derive
-- instances for sum types automatically, but only in its own tagged encodings —
-- none of which match Overpass's wire format, where the tag is an ordinary
-- field alongside the payload. Writing it by hand is a dozen lines and gives
-- exact control.
--
-- Note @.:?@ with @.!=@ for @tags@ and @nodes@: \"optional, defaulting to
-- empty\". That is the direct equivalent of Go's @omitempty@ fields arriving as
-- nil, minus the nil.
instance FromJSON Element where
  parseJSON = withObject "Overpass.Element" $ \object -> do
    elementType <- object .: "type"
    elementId <- object .: "id"
    case elementType :: Text of
      "node" -> do
        latitude <- object .: "lat"
        longitude <- object .: "lon"
        elementTags <- object .:? "tags" .!= Map.empty
        pure $
          NodeElement
            OsmNode
              { nodeId = elementId
              , coord = Coord {lat = latitude, lon = longitude}
              , tags = elementTags
              }
      "way" -> do
        refs <- object .:? "nodes" .!= []
        elementTags <- object .:? "tags" .!= Map.empty
        pure $
          WayElement
            OsmWay {wayId = elementId, nodeRefs = refs, tags = elementTags}
      other -> pure (OtherElement other elementId)

-- | Decode a full response and build its indexes in one step.
instance FromJSON Response where
  parseJSON = withObject "Overpass.Response" $ \object -> do
    responseVersion <- object .:? "version"
    responseGenerator <- object .:? "generator"
    responseElements <- object .:? "elements" .!= []
    pure $
      indexResponse
        emptyResponse
          { version = responseVersion
          , generator = responseGenerator
          , elements = responseElements
          }
