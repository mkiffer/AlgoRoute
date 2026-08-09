# `Mapping.hs` — OSM elements to a routable graph

## What it does

The layer where OpenStreetMap's data model becomes a graph the search algorithms
can traverse, and where the `oneway` tag is interpreted.

## The Go code it replaces

`backend/mapping/road_mapper.go`.

## The shape of the transformation

An OSM way is a **polyline**: a flat, ordered list of node IDs.

```
way 4518176: [27347732, 27347731, 27347730, 27347728]
```

means three road segments — 27347732→27347731, 27347731→27347730,
27347730→27347728. So the whole job is a fold over ways, where each way folds
over its **consecutive pairs**.

Go writes this as a nested `for` with an index-zero guard:

```go
for i, nodeID := range way.Nodes {
    if i == 0 { continue }           // no predecessor to pair with
    fromID := way.Nodes[i-1]
    ...
}
```

Haskell takes the pairs directly:

```haskell
consecutivePairs refs = zip refs (drop 1 refs)
-- [a,b,c] → [(a,b), (b,c)]
```

and the special case disappears. A way with fewer than two nodes yields no
pairs, which is exactly right: it describes no segment.

## Where the weights come from

Each segment's weight is the Haversine distance between its endpoints, so
"shortest path" means **shortest in metres**.

Nothing in `Routefinding` knows or cares what a weight means. Switching to
travel time would mean changing this one expression — `distanceMeters / speed`,
with speed derived from the `highway` and `maxspeed` tags — and every algorithm
would work unchanged.

(One caveat if you ever do: A*'s heuristic is a *distance*, so it would start
overestimating and quietly stop being optimal. See `Routefinding/AStar.README.md`.)

## The `oneway` tag

The rules, straight from the [OSM wiki](https://wiki.openstreetmap.org/wiki/Key:oneway)
and unchanged from Go:

| Tag value | Forward edge | Backward edge |
|---|---|---|
| `yes`, `1`, `true` | yes | no |
| `-1`, `reverse` | **no** | yes |
| `no`, `0`, `false` | yes | yes |
| *(absent)* | yes | iff `assumeBidirectional` |

`-1`/`reverse` means the way was **digitised against the direction of travel** —
the node order in the data runs the opposite way to the traffic. So the forward
edge is *suppressed*, not merely supplemented. That is the case people get
wrong.

### `assumeBidirectional`

```haskell
newtype BuildOptions = BuildOptions { assumeBidirectional :: Bool }
```

OSM's convention is that an untagged road is bidirectional, but the tag is
frequently missing on roads that really are one-way. The trade:

- **Assume bidirectional** (what the server does): a connected, routable
  network, at the cost of occasionally routing the wrong way down a street.
- **Assume one-way**: a network so fragmented that many routes cannot be found
  at all.

`API.Handlers` passes `True`, matching `server/handlers.go`. Ways with an
*explicit* tag always have it respected either way.

### A Go quirk, deliberately preserved

The backward-edge condition is:

```haskell
not (isForwardOnlyOneWay tag)
  && (isReverseOnlyOneWay tag || isExplicitlyBidirectional tag
        || (assumeBidirectional && tag == ""))
```

An **unrecognised** value — a typo, or a conditional restriction like
`yes @ (Mo-Fr 07:00-09:00)` — falls through every branch. It is not
forward-only, not reverse-only, not explicitly two-way, and the `tag == ""`
guard fails because the tag *is* present. So no backward edge is added and the
way silently becomes one-way.

Arguably it should fall back to the untagged behaviour. It is reproduced as-is
because the point of this port is to match the Go backend, and a silent
behavioural difference in one-way handling would be a genuinely nasty thing to
debug. There is a test asserting it, with the reasoning written out. **Change
both backends together.**

## Missing node references

If a way names a node Overpass did not send — completely normal at the edge of a
bounding box, where a road runs out of the query area — the rest of that way is
abandoned, `missingNodeRefs` is incremented, and the next way proceeds.

That is Go's `break` out of the inner loop, and it is deliberately **not** a hard
error: a partial network is still routable, and failing the request because one
road left the box would make the app unusable.

Note the port matches Go's exact ordering here: the `from` node is added to the
network even when the `to` node turns out to be missing. That is why
`addSegments` resolves and inserts the two endpoints one at a time rather than
checking both up front.

## `BuildStats`

Diagnostics only — nothing in the routing pipeline branches on them.

Go's `BuildStats` also declares `SkippedWays` and `NonRoutableWays`, but nothing
ever increments them. A field that is always zero is worse than no field, so
they are not reproduced.

## Why the result is `Either`

```haskell
buildNetwork :: BuildOptions -> Response -> Either GraphError (Network, BuildStats)
```

`Graph.addEdge` validates its arguments, so a malformed way could in principle
produce an invalid edge. In practice it cannot — both endpoints are added as
nodes immediately before, and Haversine distance is never negative — but the
error path is threaded through rather than assumed away with a partial function.

## `finalizeAdjacency`

The last thing `buildNetwork` does. `Graph.addEdge` prepends for speed, so the
adjacency lists come out reversed; this restores insertion order in one O(E)
pass. It is what keeps the Haskell backend's `visited_nodes` node-for-node
identical to Go's. See `src/Graph.README.md`.

## Poke it in the REPL

```
ghci> import Mapping
ghci> import Overpass.Client
ghci> Right r <- loadFromFile "test/testdata/sample_overpass.json"
ghci> let Right (net, stats) = buildNetwork defaultBuildOptions r
ghci> stats
BuildStats {wayCount = 55, nodeCount = ..., edgeCount = ..., missingNodeRefs = ...}
ghci> let Right (oneWay, _) = buildNetwork (BuildOptions False) r
ghci> (Graph.edgeCount net, Graph.edgeCount oneWay)
```

That last pair is `assumeBidirectional` in action: roughly half the edges
disappear when untagged ways stop being two-way.
