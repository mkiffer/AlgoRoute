# `Geo/Geocode.hs` — address text to coordinate

## What it does

Turns `"Chapel St, South Yarra"` into a `Coord`, by asking Nominatim.

## The Go code it replaces

`backend/geo/geocode.go` — and, notably, also its twin
`GeocodeWithBaseURL`, which exists purely so tests can point at an
`httptest.Server`. See the section below.

## The mechanics

All the HTTP work is in `Geo.Nominatim`. What remains here is the endpoint's own
two facts:

**Query parameters.** `format=json`, `q=<address>`, `limit=1`.

**`limit=1` is deliberate.** We want Nominatim's best guess and nothing else. If
the address is ambiguous, the user has already disambiguated through the
autocomplete dropdown (`Geo.Suggest`) before this is ever called.

**Response shape.** An array of hits; take the first. The coordinates arrive as
JSON *strings*, so `NominatimHit` holds them as `Text` and `toCoord` converts in
one explicit step.

Modelling the wire shape faithfully and converting separately beats a clever
`FromJSON` instance that hides the conversion: when Nominatim sends something
unparseable, the error names the field and carries the offending text.

## Failure is fatal here, unlike the other two endpoints

An unresolvable address means there is no route to compute, so
`Services.Routing` propagates the error and the request fails — matching Go's
`fmt.Errorf("geocode origin: %w", err)`.

Note that `NoResults` carries the address. An empty result array is not an HTTP
failure; it is a successful "no such place", and the message should say *which*
place. `Services.Routing` wraps it further with `"origin"` or `"destination"`,
because the pipeline geocodes two addresses and a bare "not found" would leave
the user guessing which one.

## The design decision: `geocodeURL` takes a base URL

```haskell
geocodeURL :: Text -> Text -> Text     -- base URL, address
geocode    :: Manager -> Text -> Text -> IO (Either GeoError Coord)
```

Go's testability approach is a parallel function per call site:

```go
func Geocode(address string) (Coord, error) {
    return GeocodeWithBaseURL(address, nominatimBaseURL)
}
func GeocodeWithBaseURL(address, baseURL string) (Coord, error) { ... }
```

plus `geocodeWithOptionalOverride` in the service layer, plus
`suggestWithOptionalOverride` and `reverseGeocodeWithOptionalOverride` in the
server layer, plus three test-only URL fields on `server.Options` and three more
on `services.AddressRouteRequest`. That is six extra functions and six extra
record fields existing purely so tests can redirect a hostname — and the
function production actually calls, `Geocode`, is *never* the one under test.

Here there is one `geocode`, and it reads its base URL from
`App.Env.Endpoints`. Tests build an `Env` pointing at a local stub; production
builds one pointing at Nominatim. **The production code path and the tested code
path are the same path**, which the Go arrangement cannot quite claim.

`geocodeURL` stays exported for the same reason Go exports `NominatimURL` — so
the query structure can be asserted without a network call — but it is the same
function production uses, not a parallel one.

See `src/App/Env.README.md` for the full argument.
