# `Graph/Snap.hs` — snapping a coordinate to the network

## What it does

Given an arbitrary coordinate, finds the graph node closest to it.

## The Go code it replaces

`backend/graph/snap.go`.

## Why it exists

Geocoding an address gives you a point on a *building* — or a driveway, or the
centroid of a parcel. The routing algorithms only understand graph nodes. So
every request must first project its two endpoints onto the network, and that
projection is this function.

It runs twice per route request, on a network that took seconds to download.

## Algorithm and complexity

A linear scan: **O(n)** in the number of nodes, with one Haversine call each.

For the city-scale networks this backend fetches — tens of thousands of nodes —
that is a fraction of a millisecond, and utterly dwarfed by the Overpass fetch
that produced the network. A k-d tree or geohash grid would cut it to O(log n)
after an O(n log n) build, but the build alone would cost more than the scan
saves for a network used twice and discarded.

It would pay off at continent scale, or under sustained load against a cached
network. `PROJECT_STATE.md` lists it under "Performance" as a known trade-off,
and this port keeps the same conclusion as the Go comment.

## Why an error rather than a default

```haskell
nearestNode :: Network -> Coord -> Either SnapError NodeID
```

Returning a zero `NodeID` for an empty network would send the route request off
to node 0 — which either does not exist, or is some unrelated node in Africa.
Failing loudly at the snap keeps the bug where it happened rather than three
layers downstream.

`SnapError` has one constructor (`EmptyNetwork`), so `Maybe` would carry the
same information. It is a named type anyway so `App.Error` can map it to a
specific message — `"snap origin to network: network has no nodes"` — and so
that a second failure mode could be added without changing every call site.

## The fold

Go writes a `for … range` that mutates two locals:

```go
var nearestID NodeID
shortestDistance := math.Inf(1)
for nodeID, node := range net.Nodes { ... }
```

The Haskell version threads those two values through `Map.foldlWithKey'` as an
accumulator — the same loop, with the mutable variables turned into function
arguments. The `'` is not decoration: it forces the accumulator at each step, so
scanning 40,000 nodes does not build 40,000 nested thunks.

## A small improvement over Go: deterministic ties

Go ranges over a map, and **Go randomises map iteration order**. It keeps the
first strict improvement (`<`, not `<=`), so when two nodes sit at identical
coordinates — which happens in OSM data more often than you would like — Go can
return either one, and a different one on the next run.

Folding over `Data.Map` visits keys in ascending order, so this version always
returns the lowest node ID among the ties. Same answer every time, which makes
route responses reproducible and the tests meaningful. There is a test asserting
exactly this.

## Poke it in the REPL

```
ghci> import Graph.Snap
ghci> import Graph
ghci> import Geo.Types
ghci> let net = foldr addNode empty [Node (NodeID 1) (Coord (-37.81) 144.96), Node (NodeID 2) (Coord (-37.82) 144.97)]
ghci> nearestNode net (Coord (-37.821) 144.971)
Right 2
ghci> nearestNode empty (Coord 0 0)
Left EmptyNetwork
```
