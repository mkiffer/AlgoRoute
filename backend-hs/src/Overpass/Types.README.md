# `Overpass/Types.hs` — the OSM wire format as Haskell data

**The headline example of the whole port.** If you read one README about "what
does a sum type actually buy me", read this one.

## What it does

Decodes the JSON the Overpass API returns, and indexes it for the mapping layer.

## The Go code it replaces

The DTOs in `backend/api/overpass/client.go`, plus the post-unmarshal indexing
loop that appears in **two** places there.

## The design decision: string tag vs. sum type

Go models an element as one struct with a type tag and every field of both
variants present:

```go
type Element struct {
    Type  string             `json:"type"`   // "node" or "way"
    Id    int64
    Lat   *float64           // only set when Type == "node"
    Lon   *float64           // only set when Type == "node"
    Nodes []int64            // only set when Type == "way"
    Tags  map[string]string
}
```

**Every one of those comments is a rule the compiler cannot check.** Nothing
stops you reading `Lat` on a way; you get a nil pointer. And the struct can
represent states that do not exist in the OSM data model at all:

- a way with a latitude
- a node with a node list
- an element whose `Type` is `"node"` but whose `Lat` is nil
- an element whose `Type` is `""`

Haskell:

```haskell
data OsmNode = OsmNode { nodeId :: !Int64, coord :: !Coord, tags :: !Tags }
data OsmWay  = OsmWay  { wayId :: !Int64, nodeRefs :: ![Int64], tags :: !Tags }

data Element
  = NodeElement !OsmNode
  | WayElement  !OsmWay
  | OtherElement !Text !Int64
```

Pattern matching on `NodeElement` **gives** you a coordinate. There is no nil to
check, because there is no way to construct a node without one. Illegal states
are unrepresentable rather than merely undocumented.

**The concrete payoff.** `backend/mapping/road_mapper.go` contains this, twice:

```go
respFromNode, exists := response.NodeByID[fromID]
if !exists || respFromNode.Lat == nil || respFromNode.Lon == nil {
    stats.MissingNodeRefs++
    break
}
```

Three conditions. In `Mapping.hs` only the first survives — "is this ID in the
map" — because the other two cannot happen. Two of the four nil checks in the
Go mapper simply have no counterpart.

If you know C# discriminated unions or F# DUs, this is exactly that, and it is
the single most transferable idea in the port.

### Why separate records rather than shared fields

The plan sketches `NodeElement { elemId, elemLat, elemLon, elemTags }` and
`WayElement { elemId, elemNodeIds, elemTags }` — one sum type with fields on
each constructor. That works, but it generates **partial selectors**: `elemLat`
would typecheck on a `WayElement` and crash at runtime. Giving each variant its
own record and wrapping them keeps every selector total.

### Why `OtherElement` exists

Overpass returns relations. Go's `switch` has cases for `"way"` and `"node"` and
silently ignores anything else — and that tolerance is correct, because a
relation in the response is not an error.

Failing the whole parse on an unexpected type would be a regression, so unknown
types decode into `OtherElement` carrying their type string and ID, and are
skipped downstream. Same behaviour, but **visible in the type** rather than
implied by a missing `case`. There is a test for it.

## The hand-written `FromJSON`

```haskell
instance FromJSON Element where
  parseJSON = withObject "Overpass.Element" $ \object -> do
    elementType <- object .: "type"
    elementId   <- object .: "id"
    case elementType :: Text of
      "node" -> ...
      "way"  -> ...
      other  -> pure (OtherElement other elementId)
```

`aeson` can derive sum-type instances automatically, but only in its own tagged
encodings — `{"tag": "NodeElement", "contents": {...}}` and similar. None of
them match Overpass's format, where the tag is an **ordinary field alongside the
payload**. Writing it by hand is a dozen lines and gives exact control.

Note `.:?` with `.!=` for `tags` and `nodes`: "optional, defaulting to empty".
That is Go's `omitempty` fields arriving as nil, minus the nil — nothing
downstream ever sees an absent map.

## The derived indexes

```haskell
data Response = Response
  { version   :: !(Maybe Double)
  , generator :: !(Maybe Text)
  , elements  :: ![Element]
  , ways      :: ![OsmWay]              -- derived
  , nodesById :: !(Map Int64 OsmNode)   -- derived
  }
```

Go declares `Ways`, `Nodes` and `NodeByID` with `json:"-"` and fills them in a
loop *after* unmarshalling — a loop that is **copy-pasted into both**
`LoadNetworkFromJSON` and `FetchFromAPIWithBaseURL`. A fix to one would have to
be remembered in the other.

Here the loop is `indexResponse`, called once from the `FromJSON` instance, so
decoding a response by any route produces the same indexes. `Overpass.Client`
has nothing to do after decoding.

Go's `Nodes []Element` field has no readers anywhere in the backend, so it is
not reproduced. Reproducing an always-unused field would be worse than dropping
it.

## Poke it in the REPL

```
ghci> import Overpass.Types
ghci> import Data.Aeson
ghci> decode "{\"type\":\"node\",\"id\":42,\"lat\":-37.8,\"lon\":144.9}" :: Maybe Element
Just (NodeElement (OsmNode {nodeId = 42, coord = Coord {lat = -37.8, lon = 144.9}, tags = fromList []}))
ghci> decode "{\"type\":\"node\",\"id\":42}" :: Maybe Element
Nothing
ghci> decode "{\"type\":\"relation\",\"id\":99}" :: Maybe Element
Just (OtherElement "relation" 99)
```

The middle one is the point: a node without a coordinate is not a node, and it
is rejected at the boundary rather than three layers in.
