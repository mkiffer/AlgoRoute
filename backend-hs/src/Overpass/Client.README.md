# `Overpass/Client.hs` — building queries and fetching road data

## What it does

Two jobs, deliberately kept apart: build the Overpass QL query string (pure),
and fetch a response from the API or from disk (`IO`).

## The Go code it replaces

`backend/api/overpass/fetch.go` and the file-loading half of `client.go`.

## The pure/effectful split

```haskell
buildQuery   :: BBox -> Text                                  -- pure
fetchFromAPI :: Manager -> Text -> BBox -> IO (Either OverpassError Response)
```

`buildQuery` has no `IO` in its type, so the compiler guarantees it cannot touch
the network — which makes it exhaustively testable with no stub server and no
mocking. Go's `BuildOverpassQuery` is equally pure in practice, and its comment
says it is "exported so it can be unit-tested without making live HTTP calls",
but only convention keeps it that way.

## The query

```
[out:json];(way["highway"~"^(motorway|trunk|...)$"](south,west,north,east);>;);out body;
```

Three details worth knowing, all of which produce *silently wrong results* if
you get them wrong rather than errors:

**1. Bounding-box argument order is `(south, west, north, east)`** — i.e.
`minLat, minLon, maxLat, maxLon`. Latitude first, unlike almost every other geo
API, which puts longitude first. Getting it backwards yields an *empty result*
rather than an error, and there is a test asserting the exact rendered string.

**2. The `>;` idiom is not optional.** The filter matches *ways*, and an OSM way
is just an ordered list of node IDs — no coordinates. `>;` means "also emit
everything these ways refer to", so the response contains the member nodes as
well. Without it, `Mapping` has references it cannot resolve and builds an
**empty network**, which then fails as "no route found".

**3. Six decimal places**, matching Go's `%.6f`. That is about 11 cm at the
equator — far finer than OSM data warrants, but it is what the Go backend emits,
so the two produce identical query strings.

## The highway filter

```haskell
driveableHighwayTypes =
  "motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street"
```

Verbatim from Go. Footways, cycleways and service roads are excluded on purpose:
including them would let the router send a car down a pedestrian mall.

This is the single most consequential constant in the backend. Widening it
changes what "a route" means; narrowing it fragments the network.

## Limits

| Limit | Value | What it prevents |
|---|---|---|
| Response timeout | 30 s | Spurious failures. A city-scale box can take Overpass 10+ seconds to answer; a shorter timeout turns a slow response into an error. |
| Body cap | 10 MB | Out-of-memory kills. A Melbourne→Geelong box can return well over 100 MB. |

**Reading with a cap.** `withResponse` + `brReadSome` reads at most
`maxResponseBytes + 1` bytes and stops — it does not buffer the whole body and
then check. Asking for *one byte past* the limit is what makes "exactly at the
limit" distinguishable from "over it", which is the same trick as Go's
`io.LimitReader(body, max+1)`.

`Services.Routing` also rejects oversized *bounding boxes* before the request is
made. This cap is the backstop for when that estimate is wrong.

## `OverpassError`

```haskell
data OverpassError
  = RequestFailed !Text   -- DNS, connection, timeout
  | BadStatus !Int
  | ResponseTooLarge
  | DecodeFailed !Text
  | FileReadFailed !Text
```

Go returns `fmt.Errorf` strings, so a caller wanting to react differently to
"too large" than to "timed out" would have to match on message text. These
constructors let `App.Error` map each cause to its own response and message.

## The base URL is a parameter

Not a constant with a `…WithBaseURL` twin, as in Go. `App.Env.Endpoints` supplies
it, so tests point at a local stub and production points at
`overpass-api.de` — with the *same* function on both paths. See
`src/App/Env.README.md`.

## `loadFromFile`

Ports `LoadNetworkFromJSON`. Backs the CLI mode of the executable — routing
against a saved fixture with no network access at all — and the tests.

Because `Overpass.Types` does its indexing inside the `FromJSON` instance, this
function is four lines and shares every behaviour with `fetchFromAPI`. In Go the
two functions each carry their own copy of the indexing loop.

## Poke it in the REPL

```
ghci> import Overpass.Client
ghci> import Geo.Types
ghci> buildQuery (BBox (-37.9) 145.09 (-37.88) 145.11)
"[out:json];(way[\"highway\"~\"^(motorway|...)$\"](-37.900000,145.090000,-37.880000,145.110000);>;);out body;"
ghci> r <- loadFromFile "test/testdata/sample_overpass.json"
ghci> fmap (length . ways) r
Right 55
```

Paste that query into <https://overpass-turbo.eu> to see exactly what the
backend asks for.
