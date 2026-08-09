# `Geo/Suggest.hs` — address autocomplete

## What it does

Up to five address suggestions for a partial query, for the dropdown under the
origin and destination inputs.

## The Go code it replaces

`backend/geo/suggest.go`.

## Same endpoint as geocoding, different limit

Nominatim serves both from `/search`. The only differences are `limit=5` instead
of `limit=1`, and that the display name is kept rather than discarded.

**Why five.** It fills a compact dropdown without scrolling, and Nominatim's
fair-use policy asks for modest limits. Same value as Go.

## `SuggestResult` is part of two contracts

Unlike `Geo.Geocode.NominatimHit`, this type is also part of the **outgoing**
JSON contract — `GET /api/suggest` returns a list of them directly, and
`frontend/src/types.ts` declares the matching interface:

```typescript
export interface SuggestResult {
  display_name: string;
  lat: number;
  lon: number;
}
```

Hence the hand-written `ToJSON` emitting `display_name`, not `displayName`.
There is a `FromJSON` too, so a client — or a test asserting the wire contract —
can read back what the server writes. Note the coordinates are **numbers** in
our shape, even though Nominatim sends **strings** in theirs: `SuggestHit` is
the wire shape coming in, `SuggestResult` is the wire shape going out, and they
are deliberately different types.

## Bad entries are skipped, not fatal

```haskell
Right hits -> Right (mapMaybe toResult hits)
```

If one hit has an unparseable coordinate, it is dropped and the rest are
returned. Failing the whole response would blank the user's dropdown because of
one malformed row.

`mapMaybe` says that in one word: keep every `Just`, discard every `Nothing`.
Go writes the same policy as two `continue` statements inside the loop.

**A known issue, inherited.** `PROJECT_STATE.md` lists this under "Error
Handling" — the skipping is silent, so failures are invisible. That is equally
true here. The fix is to log before discarding, and it is confined to
`toResult`: about two lines, in one place. Worth doing; not done, so that the
port matches the Go behaviour it is being compared against.

## A transport failure is still an error

`suggest` returns `Left` when the request itself fails. Turning that into an
empty list is the **handler's** decision, not this module's — see
`API.Handlers.handleSuggest`, which returns `[]` with a 200 for any failure.

Keeping the policy at the boundary rather than burying it here means the
function is still usable by a caller who wants to know about the failure. It
also means the graceful-degradation behaviour is stated in exactly one place,
where someone reading the HTTP layer will find it.
