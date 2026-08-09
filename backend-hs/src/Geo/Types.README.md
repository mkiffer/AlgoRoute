# `Geo/Types.hs` — `Coord` and `BBox`

## What it does

Two record declarations and nothing else. A point, and an axis-aligned box.

## The Go code it replaces

`backend/geo/coords.go` and the type half of `backend/geo/bbox.go`.

## Why the types are separated from the functions

Everything that *operates* on these types lives elsewhere: distance maths in
`Geo.Distance`, box construction and area in `Geo.BBox`. Keeping the types in a
leaf module with no imports of its own means every other module can import them
without any risk of an import cycle — which is the same reason Go splits
`coords.go` out.

Haskell is stricter about this than Go: Go allows cycles *within* a package,
Haskell forbids module cycles outright (`.hs-boot` files exist to break them and
are unpleasant). Putting bare types at the bottom of the dependency graph is
therefore a habit worth forming early in a Haskell codebase.

## Strict fields

```haskell
data Coord = Coord { lat :: !Double, lon :: !Double }
```

The `!` forces each field when the record is built. Without it, a `Coord` could
hold an unevaluated thunk — a *description* of how to compute the latitude,
holding on to whatever data that computation referenced.

This matters most for `BBox`, because boxes are stored as keys in the long-lived
`Services.Cache`. A lazy field there would retain the whole computation that
produced the box, and a cache full of thunks is the classic Haskell space leak.

## `Ord` on `BBox` is load-bearing

```haskell
deriving stock (Eq, Ord, Show)
```

`Services.Cache` keys a `Map BBox Response` on it. That mirrors Go's
`map[geo.BBox]overpass.Response`, which is legal there precisely because the
struct contains only comparable `float64` fields.

Note what this means: cache lookups are **exact floating-point equality** on
four `Double`s. A geocode that shifts by a billionth of a degree misses the
cache rather than returning data for a slightly different area. That is the
right trade — a near-miss returning the wrong area's road network would be a far
worse bug than an extra fetch — but it is worth knowing, and there is a test
pinning it down.

---

## The record-field trap, explained once

**This is the section `TUTOR.md` promises, and the thing you will hit within an
hour of starting.**

Classic Haskell generates a top-level function for every record field:

```haskell
data Coord = Coord { lat :: Double, lon :: Double }
-- generates:  lat :: Coord -> Double
--             lon :: Coord -> Double
```

So `lat` is an ordinary function in the module's namespace. Which means you
cannot also have:

```haskell
data PathNodeJSON = PathNodeJSON { nodeId :: Int, lat :: Double, lon :: Double }
```

in scope at the same time — there would be two different functions called `lat`.
GHC reports **"Ambiguous occurrence `lat`"** or **"Multiple declarations of
`lat`"**, and `GHC2021` does not fix it.

This codebase has `lat`/`lon` on four different records (`Coord`, `PathNodeJSON`,
`CoordJSON`, `SuggestResult`), `nodeId` on three, and `tags` on two — so it hits
the problem everywhere. Two extensions solve it, and they do different jobs:

### `DuplicateRecordFields`

Lets several records in the same module share a field name, and lets *record
construction and pattern matching* disambiguate by the constructor:

```haskell
{-# LANGUAGE DuplicateRecordFields #-}

Coord { lat = 1, lon = 2 }        -- unambiguous: the constructor says which
```

It does **not** make the bare selector `lat` usable — that is still ambiguous,
because there is no constructor to disambiguate from.

### `OverloadedRecordDot`

Gives you C#-style dot access, resolved by the *type of the value*:

```haskell
{-# LANGUAGE OverloadedRecordDot #-}

coordinate.lat                    -- unambiguous: coordinate is a Coord
outcome.originCoord.lat           -- chains, too
```

Together they cover reads and writes, and this codebase enables both per module,
with a pragma at the top of each file that needs them. They are enabled
per-module rather than project-wide precisely so that the pragma is a visible
signal: *this module juggles overlapping field names.*

### The one gotcha with `OverloadedRecordDot`

It works through the `HasField` type class, and **that requires the field
selector to be in scope**. So this fails:

```haskell
import Geo.Types (Coord)          -- type only, no fields
...
coordinate.lat                    -- error: No instance for HasField "lat" Coord
```

and this works:

```haskell
import Geo.Types (Coord (..))     -- (..) brings the fields in
```

The `(..)` is easy to leave off, and the resulting error — *"No instance for
`GHC.Records.HasField "lat" Coord Double`"* — does not say "add `(..)` to your
import", so it is worth recognising on sight. Three modules in this port needed
exactly that fix.

### The second gotcha: inference does not flow backwards through dots

`HasField` does not drive type inference, so this is ambiguous:

```haskell
response <- fetchJSON manager url        -- polymorphic result
case response of
  Right result -> result.displayName     -- which record is this?
```

The fix is an annotation naming the decoder, which is what `Geo.Reverse` does:

```haskell
response <- fetchJSON manager url :: IO (Either GeoError ReverseResult)
```

The Go equivalent is naming the struct you unmarshal into — Haskell just lets
you postpone the decision further, until it can't.
