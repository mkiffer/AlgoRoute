# `Geo/Nominatim.hs` — shared plumbing for the three Nominatim endpoints

## What it does

The request-response-decode sequence that geocoding, autocomplete and reverse
geocoding all need, written once.

## The Go code it replaces

**Nothing directly — and that is the point.**

`backend/geo/geocode.go`, `suggest.go` and `reverse.go` each repeat the same
forty lines: build a URL from `url.Values`, set the `User-Agent`, do the
request, check the status, read the body, unmarshal, handle four error cases.
Three copies, three chances to fix a bug in only two of them.

Here that sequence is `fetchJSON`, and the three endpoint modules are a dozen
lines each: their own query parameters and their own response shape, nothing
more.

## `fetchJSON` and why the type class earns its keep

```haskell
fetchJSON :: FromJSON a => Manager -> Text -> IO (Either GeoError a)
```

The `FromJSON a` constraint means the **caller's expected type** decides how the
body is parsed. `Geo.Geocode` asks for a `[NominatimHit]`, `Geo.Reverse` asks
for a single `ReverseResult`, and this function needs to know nothing about
either.

Go cannot express that. It would need `interface{}` plus a type assertion at
every call site, or — what it actually does — a separate copy of the whole
function per response shape.

The cost is the inference gotcha described in `Types.README.md`: when nothing
downstream pins `a` down, you have to annotate. `Geo.Reverse` carries exactly
that annotation, with a comment.

## Sorted query parameters

```haskell
buildURL base params =
  base <> renderSimpleQuery True (map encodePair (sortOn fst params))
```

The `sortOn` is not cosmetic. Go's `url.Values.Encode` sorts keys alphabetically,
so sorting here means the two backends emit **byte-identical URLs** — which is
what lets the ported URL-shape tests (`NominatimURL`, `SuggestURL`,
`ReverseGeocodeURL` in the Go suite) still be meaningful assertions rather than
tautologies.

## The `User-Agent` is not optional politeness

```haskell
userAgent = "AlgoRoute/1.0 (https://github.com/algoroute)"
```

Nominatim's usage policy **requires** a descriptive agent identifying the
application. Requests without one are rate-limited hard or refused outright.
Same string as the Go backend.

## Timeouts and limits

| Setting | Value | Why |
|---|---|---|
| Response timeout | 10 s | A geocode is a small lookup; a slow one would stall an entire route request before any real work began. Overpass gets 30 s because its queries are genuinely heavy. |
| Body cap | 1 MB | Nominatim responses are tiny. Anything larger is a sign something is wrong. |

## `parseCoordinateText` — the string-coordinate trap

Nominatim reports coordinates as JSON **strings**:

```json
[{"lat": "-37.8467", "lon": "144.9781", "display_name": "..."}]
```

Not numbers. Quoted. Every one of the three endpoints has to deal with it, and
forgetting produces a decode error that reads like a network problem.

Go declares the DTO field as `string` and calls `strconv.ParseFloat`. This is
the same two-step, with the failure in the return type instead of a second
return value.

## `formatCoordinate` — the reverse trap

Going the other way, for the reverse-geocoding query string:

```haskell
formatCoordinate value = T.pack (showFFloat Nothing value "")
```

**Not `show`.** Haskell's `show` for `Double` switches to scientific notation for
small magnitudes — `show 0.01` is `"1.0e-2"` — and Nominatim rejects that.
`showFFloat Nothing` is fixed notation with the shortest round-tripping
representation, which is exactly what Go's
`strconv.FormatFloat(v, 'f', -1, 64)` produces.

This is a genuinely easy bug to ship: it works for every coordinate in Melbourne
and fails near the equator or the prime meridian.

## `GeoError`

```haskell
data GeoError
  = RequestFailed !Text          -- connection, DNS, timeout
  | BadStatus !Int
  | DecodeFailed !Text
  | NoResults !Text              -- carries the query
  | UnparseableCoordinate !Text
```

Go returns a formatted `error` at each of these points. As a sum type, the
caller can decide per case — and the three endpoints genuinely **do** decide
differently:

| Endpoint | On failure |
|---|---|
| `geocode` | Abort the whole route request; there is nothing to route between. |
| `suggest` | Return `[]`. Autocomplete fires per keystroke; a red banner would be worse than no suggestions. |
| `reverse` | Return `{"address": ""}` with a 200. The pin still drops; the user types the label. |

Those policies live in `API.Handlers`, and they only make sense because the
error is a value the handler can inspect rather than a string it must forward.
