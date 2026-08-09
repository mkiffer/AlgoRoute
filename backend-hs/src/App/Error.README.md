# `App/Error.hs` — one error type for the whole request

## What it does

Collects every way a request can fail into a single type, and decides what the
client sees.

## The Go code it replaces

No single file. Go threads `error` through every layer, wrapping with
`fmt.Errorf("context: %w", err)` as it goes, and the HTTP handler turns whatever
arrives into a 500 with the accumulated message.

## The structure

Each layer keeps its own error type — `GeoError`, `OverpassError`, `GraphError`,
`SnapError`, `RouteError` — and `AppError` is where they converge:

```haskell
data AppError
  = InvalidRequest !Text
  | GeocodeFailed !Text !GeoError          -- which address, and why
  | AreaTooLarge !Double !Double           -- actual, limit
  | RoadDataUnavailable !OverpassError
  | NoRoadsInArea
  | NetworkBuildFailed !GraphError
  | SnapFailed !Text !SnapError            -- which endpoint
  | RoutingFailed !RouteError
```

**Each constructor wraps the lower-level error rather than flattening it to a
string.** Nothing is lost on the way up: a handler, a test, or a future logger
can still pattern match on the original cause.

That is the practical difference from Go's `%w` wrapping, which also preserves
the cause but only reaches it through `errors.As` and a type assertion. Here it
is a field.

The `Text` payloads on `GeocodeFailed` and `SnapFailed` answer "*which one*" —
the pipeline geocodes and snaps two things each, and a bare "geocoding failed"
would leave the user guessing.

## One wrinkle: qualified constructor names

`GeoError` and `OverpassError` both have `RequestFailed`, `BadStatus` and
`DecodeFailed` constructors. Rather than renaming one set, both are imported
qualified:

```haskell
import Geo.Nominatim qualified as Nominatim
import Overpass.Client qualified as Overpass

Nominatim.BadStatus status -> "nominatim returned status " <> ...
Overpass.BadStatus  status -> "overpass API returned status " <> ...
```

The prefix says which failure domain is meant, at the point of use. This is
worth noting because the alternative — prefixing constructor names in the
defining modules (`GeoRequestFailed`, `OverpassRequestFailed`) — is a common
Haskell habit that makes every *other* use site noisier to spare this one.

## Status codes: parity over correctness, deliberately

```haskell
errorStatus (InvalidRequest _) = 400
errorStatus _                  = 500
```

**This matches the Go backend rather than what is strictly correct.**

`server/handlers.go` returns 400 only for a malformed request body or an unknown
algorithm, and **500 for every failure inside `RouteByAddress`** — including
"area too large" and "address not found", which are arguably the client's fault
and would be better as 4xx.

Parity wins here for two reasons:

1. The frontend reads `data.error` for the message and only branches on
   `response.ok`, so changing these alters nothing the user sees.
2. While the two backends are meant to be interchangeable, a status-code
   difference is exactly the kind of thing that would show up as a confusing
   discrepancy in a comparison run.

Worth revisiting once the Go backend is retired. `AreaTooLarge` in particular
should be a 422.

## The error body

```haskell
toServantError appError =
  template { errBody    = encode (object ["error" .= errorMessage appError])
           , errHeaders = [("Content-Type", "application/json;charset=utf-8")] }
```

Matches Go's `errorResponse` struct — the `{"error": "..."}` shape
`frontend/src/api.ts` parses.

**Both lines are load-bearing.** Servant's `err400` and `err500` default to a
`text/plain` body, so replacing the body without replacing the header is the
usual reason a Servant error arrives at the browser as unparsed text. There is a
test asserting the response is valid JSON *and* carries a JSON content type.

## Message wording

The messages follow the Go handlers closely, because the frontend surfaces them
to the user directly and they have been written to be actionable:

> query area too large (1823 km²): maximum is 500 km² — try closer addresses

not "bbox validation failed". If you change one, change the Go one too.
