# `Geo/Reverse.hs` — coordinate to address

## What it does

Turns a lat/lon into a human-readable address. This is what makes click-to-place
routing work: you click the map, and the input box fills in with a street name.

## The Go code it replaces

`backend/geo/reverse.go`.

## The one structural difference from `/search`

Nominatim's reverse endpoint returns a single JSON **object**, not an array:

```json
{"display_name": "123 Chapel St, South Yarra, Victoria, Australia", ...}
```

That is the whole reason this cannot simply reuse `Geo.Geocode.geocode`. Same
plumbing, different container.

## `display_name` is optional, on purpose

```haskell
newtype ReverseResult = ReverseResult { displayName :: Maybe Text }
```

Nominatim omits the field entirely when the coordinate falls in the ocean or on
unmapped land. That is a legitimate "no address here" answer rather than a
malformed response, so the field is `Maybe` and the empty case is handled rather
than being a decode failure.

## Graceful degradation is the design

`reverseGeocode` returns `Left (NoResults ...)` for a missing or empty
`display_name`, and `API.Handlers` turns that into `{"address": ""}` with a
**200**.

The reasoning: the user clicked the map. Losing the address label is a small
annoyance — they can type it. Losing the *pin* would break the click-to-route
flow entirely. So an upstream failure must not fail the request.

Contrast with the other half of the same handler: an unparseable `lat` or `lon`
**is** a 400. The caller sent something wrong and should be told. Two different
failure policies in one handler, both taken from Go, and the reason they differ
is whose fault the failure is.

## The coordinate formatting trap

```haskell
[("lat", formatCoordinate coordinate.lat), ("lon", formatCoordinate coordinate.lon)]
```

`formatCoordinate` is `showFFloat Nothing`, not `show`. Haskell's `show` for
`Double` emits scientific notation for small magnitudes — `show 0.01` gives
`"1.0e-2"` — which Nominatim rejects.

Easy to ship, because it works for every coordinate in Melbourne and fails near
the equator or the prime meridian. See `Nominatim.README.md`.

## The type annotation

```haskell
response <- fetchJSON manager (reverseGeocodeURL baseUrl coordinate) ::
              IO (Either GeoError ReverseResult)
```

`fetchJSON` is polymorphic in its result, and nothing below pins the type down —
record-dot access goes through `HasField`, which does not drive inference. The
annotation says which decoder to use.

The Go equivalent is naming the struct you unmarshal into. Haskell just lets you
postpone that decision until it genuinely cannot be postponed, and this is one
of the few places in the codebase where it can't.
