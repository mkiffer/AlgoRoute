# `Geo/Distance.hs` — Haversine great-circle distance

## What it does

One function: the distance in metres between two coordinates, over the surface
of a sphere.

## The Go code it replaces

`backend/geo/distance.go`, exactly — same formula, same Earth radius, same
`asin(sqrt a)` form rather than `atan2`. The two backends produce
bit-for-bit identical distances for the same input, which is what makes the CLI
parity check meaningful.

## The formula

```
a = sin²(Δφ/2) + cos φ₁ · cos φ₂ · sin²(Δλ/2)
d = 2 · R · asin(√a)
```

with `R = 6,371,000 m`, the mean Earth radius.

Haversine computes the **great-circle** distance: the shortest path across the
surface of a sphere. It is the standard choice for this kind of work because it
is numerically well behaved at small distances, where the naive spherical law of
cosines loses precision badly.

## Accuracy, and why it is fine

The Earth is an oblate spheroid, not a sphere — about 21 km flatter pole-to-pole
than equator-to-equator. Haversine therefore carries up to **~0.5% error**
against a geodesic method like Vincenty.

For road routing that is irrelevant, and the reason is worth internalising: the
error is far smaller than the difference between straight-line distance and the
actual road geometry we are approximating in the first place. Each edge weight
is the straight line between two consecutive OSM nodes, and the real tarmac
between them curves. Chasing 0.5% on a value that is already an approximation of
a polyline is effort spent in the wrong place.

Where it *would* matter: surveying, aviation flight planning, anything where the
straight line is the thing being measured rather than a proxy.

## Purity, and why it matters here

```haskell
distanceMeters :: Coord -> Coord -> Double
```

No `IO` in that type. That is not a comment or a convention — the compiler
enforces it. This function provably cannot read a clock, hit the network, throw,
or mutate anything.

That guarantee is what lets `Routefinding.AStar` call it inside a tight search
loop, thousands of times per request, without a moment's thought about ordering,
caching, or thread safety. In Go the same function is equally pure in practice,
but nothing in its signature says so, and nothing stops the next person adding a
log line to it.

It is also why `Geo/Distance.hs` sits apart from `Geo/Geocode.hs` in this
package. Both are "geo"; one is maths and one is a network call, and the module
split makes that visible before you open either file.

## `toRadians`

Go spells `x * math.Pi / 180.0` inline four times. Naming it once is the same
code with the intent made explicit — the sort of change `CLAUDE.md`'s clean-code
rule asks for, and one of the few places this port is *longer* than the Go.

## The property test

`test/Geo/DistanceSpec.hs` checks symmetry with QuickCheck rather than by
example:

```haskell
prop "is symmetric for all coordinate pairs" $ \a b c d ->
  distanceMeters one two === distanceMeters two one
```

Symmetry is a claim about *every* pair of coordinates, and Haversine's structure
makes it easy to break asymmetrically — swap a `b.lat - a.lat` for
`a.lat - b.lat` in the wrong place and the hand-written examples still pass.
Coordinates are clamped to ±90/±180 first, because a generated latitude of 4,000°
is not a coordinate and a failure there would tell you nothing.

## Poke it in the REPL

```
ghci> import Geo.Distance
ghci> import Geo.Types
ghci> distanceMeters (Coord 0 0) (Coord 0 1)
111194.92664455873
ghci> distanceMeters (Coord (-37.8136) 144.9631) (Coord (-33.8688) 151.2093)
713408.6...
```

One degree of longitude at the equator, then Melbourne to Sydney. Both are
sanity checks you can verify against any online calculator in ten seconds.
