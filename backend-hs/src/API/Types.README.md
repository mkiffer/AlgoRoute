# `API/Types.hs` — the HTTP surface as a type

## What it does

Declares the entire API — three endpoints plus a static-file fallback — as a
single Haskell **type**, and defines the JSON records that cross the wire.

## The Go code it replaces

The request/response structs in `backend/server/handlers.go` and the route
registration in `backend/server/server.go`.

## The API type

```haskell
type API =
  "api" :> "route" :> ReqBody '[JSON] RouteRequestJSON :> Post '[JSON] RouteResponseJSON
    :<|> "api" :> "suggest" :> QueryParam "q" Text :> Get '[JSON] [SuggestResult]
    :<|> "api" :> "reverse" :> QueryParam "lat" Text :> QueryParam "lon" Text
                            :> Get '[JSON] ReverseResponseJSON
    :<|> Raw
```

**Reading it.** `:>` is "then": `"api" :> "route" :> ReqBody '[JSON] r :> Post
'[JSON] s` is *the path `/api/route`, then a JSON request body of type `r`, then
a POST returning JSON of type `s`*. `:<|>` separates alternative endpoints and
reads as "or".

**Why the unfamiliarity is worth it.** Servant *derives* the handler type from
this declaration, so the compiler checks that `API.Handlers` implements exactly
this API. A wrong response shape, a missing endpoint, or handlers in the wrong
order are all **type errors**, not runtime 500s.

Go's `mux.HandleFunc("POST /api/route", s.handleRoute)` associates a path with a
function and checks nothing at all about what that function reads or writes. If
you rename a field in `routeResponse`, Go compiles happily and the frontend
breaks at runtime.

Try it: swap `handleSuggest` and `handleReverse` in `API.Handlers.handlers` and
build. You get a type error naming the mismatch, not a server that 500s on two
endpoints.

## `lat` and `lon` are `Text`, deliberately

`QueryParam "lat" Double` would have Servant parse and reject invalid values for
us — but with **Servant's** error body, not the `{"error": "invalid lat: …"}`
shape the Go backend returns.

Taking the raw text and parsing in the handler keeps the wire contract
identical. A deliberate trade of type-level convenience for byte-level
compatibility, and the sort of decision worth making consciously: if this were a
new API rather than a port, `Double` would be the better choice.

## The trailing `Raw`

Serves the built frontend for any path the API routes do not claim, replacing
Go's `mux.Handle("/", http.FileServer(http.Dir(staticDir)))`.

**It must come last.** Servant tries alternatives in order, and `Raw` matches
everything — put it first and the API endpoints become unreachable. This is one
of the few ordering constraints the type system does *not* catch for you.

## `api :: Proxy API`

```haskell
api = Proxy
```

`Proxy` carries no data. It exists only so a *type* can be passed to a function
that needs to know it — `serve api (server env)`. The `Proxy @API` spelling in
the plan is the same idea written with a type application.

This is the standard way Haskell passes type-level information to value-level
functions, and it looks stranger than it is: think of it as "the type, as an
argument".

## Hand-written JSON instances

`aeson` could derive these from `Generic` with a `fieldLabelModifier` turning
`distanceMeters` into `distance_meters`. That is less code. It is not used here,
and the reason is worth stating:

**Deriving makes the wire format a consequence of a naming convention.** Rename
a Haskell field and the JSON changes silently — and this JSON is a contract with
`frontend/src/types.ts`, which declares:

```typescript
export interface RouteResponse {
  algorithm: string;
  distance_meters: number;
  path: PathNode[];
  visited_nodes: Coord[];
  origin_coord: Coord;
  destination_coord: Coord;
}
```

Writing `"distance_meters" .= response.distanceMeters` puts the contract in
plain sight, in the one module where an external consumer is watching. Worth the
extra lines here; not worth it for an internal type.

Every response type also gets a `FromJSON`, so a test — or a future typed client
— can read back what the server writes. `test/API/HandlersSpec.hs` decodes real
responses off a real socket with these instances.

## `toRouteResponse` and one asymmetry

```haskell
path         = map toPathNode outcome.pathNodes        -- node_id, lat, lon
visitedNodes = map (toCoordJSON . (.coord)) outcome.visitedNodes  -- lat, lon only
```

`path` carries node IDs; `visited_nodes` carries coordinates only. Faithfully
preserved from Go, and the reason is size: the animation just draws dots and
does not need identity, while a long Dijkstra search can settle tens of
thousands of nodes. Dropping the IDs meaningfully shrinks the response.

## `algorithm` defaults to `""`

```haskell
<*> o .:? "algorithm" .!= ""
```

`Routefinding.Router.parseAlgorithm` maps `""` to `Dijkstra`, so an older client
that omits the field entirely keeps working — exactly as with Go's zero-valued
string.
