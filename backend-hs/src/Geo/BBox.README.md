# `Geo/BBox.hs` — bounding-box construction, containment and area

## What it does

Three functions on the `BBox` type: does it contain a point, roughly how big is
it, and how do you build one around two points.

## The Go code it replaces

The function half of `backend/geo/bbox.go` and all of `bbox_helpers.go`.

## `fromCoords` — and why the padding exists

```haskell
fromCoords :: Coord -> Coord -> Double -> BBox
```

The smallest box containing both coordinates, expanded outward by
`paddingDegrees` on every side.

**The padding is what makes routing work at all.** A geocoded address almost
never lands exactly on an OSM node — it lands on a building, a driveway, or the
centroid of a parcel. Without a margin, the fetched network can stop short of
the road either endpoint actually sits on, and `Graph.Snap.nearestNode` snaps to
something across the map or the whole request fails with "no roads in area".

`Services.Routing` passes `0.01°`, which is roughly **1 km** of latitude
(0.01 × 111.32 km). Longitude shrinks toward the poles, so at Melbourne's
latitude 0.01° of longitude is about 880 m — close enough for a buffer.

## `approxAreaKm2` — the cosine correction

```haskell
latSpanKm = (maxLat - minLat) * 111.32
lonSpanKm = (maxLon - minLon) * 111.32 * cos(midLatitude)
area      = latSpanKm * lonSpanKm
```

A degree of latitude is ~111.32 km everywhere. A degree of **longitude** is
111.32 km only at the equator, and shrinks to zero at the poles, because
meridians converge. Multiplying by `cos(latitude)` is the first-order
correction; taking the cosine at the box's midpoint latitude is what makes it
first-order rather than exact.

**How good is it?** Fine for the job. The error grows with the box's
north–south span, and this backend rejects anything over 500 km² — roughly a
22 km square — where the cosine barely changes across the box. It is good enough
to answer "is this query too big", and nowhere near good enough for anything
geodesic.

## Why the area check exists

`Services.Routing` rejects boxes over 500 km² before making the Overpass request.
The concrete failure it prevents: a Melbourne→Geelong query spans about
1,800 km², and the Overpass response for that box can exceed 100 MB and take the
process out of memory.

Rejecting the request from four multiplications is very much cheaper than
surviving the response. `Overpass.Client` also caps the body at 10 MB as a
backstop for when the estimate is wrong.

## `contains` — inclusive bounds

```haskell
c.lat >= b.minLat && c.lat <= b.maxLat && ...
```

`>=` and `<=`, matching Go. A geocode landing exactly on the edge of the queried
area must not be treated as outside it.

## Poke it in the REPL

```
ghci> import Geo.BBox
ghci> import Geo.Types
ghci> let box = fromCoords (Coord (-37.9) 145.1) (Coord (-37.8) 145.2) 0.01
ghci> box
BBox {minLat = -37.91, minLon = 145.09, maxLat = -37.79, maxLon = 145.21}
ghci> approxAreaKm2 box
158.6...
ghci> approxAreaKm2 (BBox 0 0 1 1)        -- one degree at the equator
12392.2...
ghci> approxAreaKm2 (BBox 59 0 60 1)      -- the same box at 60° north
6383.0...
```

That last pair is the cosine correction, visible: the same one-degree square
covers half the ground at 60° that it does at the equator.
