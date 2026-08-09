# `App/Env.hs` — the environment, and the application monad

Two ideas live here, and both are worth arguing about.

## The Go code it replaces

Nothing in one place. Go scatters this across:

- two package-level `http.Client` values (`geo/geocode.go`, `api/overpass/fetch.go`)
- a `NetworkCache` hanging off `server.Server`
- five test-only base-URL fields on `server.Options`
- three more on `services.AddressRouteRequest`
- three `…WithOptionalOverride` helper functions

All of it becomes one record built at startup and threaded through the pipeline.

---

## Part 1 — `Endpoints`, and the testability argument

```haskell
data Endpoints = Endpoints
  { nominatimSearch     :: !Text
  , nominatimReverse    :: !Text
  , overpassInterpreter :: !Text
  }
```

### What Go does

Every external call has a production function and a test twin:

```go
func Geocode(address string) (Coord, error) {
    return GeocodeWithBaseURL(address, nominatimBaseURL)
}
func GeocodeWithBaseURL(address, baseURL string) (Coord, error) { /* the real code */ }
```

Because the override has to reach the bottom of the call stack, it also needs:

- `geocodeWithOptionalOverride` in `services/address_routing.go`
- `suggestWithOptionalOverride` and `reverseGeocodeWithOptionalOverride` in `server/handlers.go`
- `GeocoderBaseURL`, `DestGeocoderBaseURL`, `OverpassBaseURL` on `AddressRouteRequest`
- five more URL fields on `server.Options`

**Six functions and eight record fields exist purely so tests can redirect a
hostname.** And the function production actually calls — `Geocode` — is never
the one under test; the tests exercise `GeocodeWithBaseURL`.

There is also `DestGeocoderBaseURL`, a *second* geocoder URL, which exists only
because Go's tests need origin and destination to resolve differently and cannot
tell them apart on a shared stub server.

### What this does instead

One `geocode`, which reads its base URL from the environment. Tests build an
`Env` pointing at a local stub; production builds one pointing at Nominatim.

```haskell
env <- newEnvWith Endpoints { nominatimSearch = stubUrl <> "/search", ... } "."
```

**The production code path and the tested code path are the same path.** That is
the property the Go arrangement cannot claim, and it is the whole argument.

The origin/destination problem disappears too: `test/Services/RoutingSpec.hs`
reads the `q` parameter in its stub and answers differently, which is two lines
instead of a second URL field threaded through three layers.

---

## Part 2 — `Env`, and why one `Manager`

```haskell
data Env = Env
  { httpManager  :: !Manager
  , networkCache :: !NetworkCache
  , endpoints    :: !Endpoints
  , staticDir    :: !FilePath
  }
```

If you know ASP.NET Core: this is the set of services you would register as
**singletons** in `Startup` — created once, shared by every request, never
rebuilt per call.

**`httpManager` is the one that matters.** An `http-client` `Manager` owns a
connection pool, so sharing it means TLS handshakes to Nominatim and Overpass
are paid once rather than per request. Creating one per call — the mistake this
field exists to prevent — leaks connections and is measurably slower. It is a
common enough error that the `http-client` documentation leads with it.

Go gets this right too, with package-level `var httpClient = &http.Client{...}`.
The difference is that a package-level var is invisible at the call site and
cannot be swapped for a test; a field can.

---

## Part 3 — `AppM`, and a deliberate deviation from the plan

```haskell
type AppM = ReaderT Env (ExceptT AppError IO)
```

Read it outside-in: a computation that can **read an `Env`** (`ReaderT`), can
**fail with an `AppError`** (`ExceptT`), and can **perform I/O**.

### The deviation

`haskell-rewrite-plan.html` sketches the pipeline as

```haskell
type Pipeline a = ExceptT AppError IO a
routeByAddress :: Env -> AddressRouteRequest -> Pipeline AddressRouteResult
```

with the environment passed by hand. This port uses `ReaderT` instead, so `Env`
is ambient and reached with `ask`.

**It is the same stack.** `ReaderT Env (ExceptT AppError IO)` *is*
`ExceptT AppError IO` with the environment moved from an argument into the
monad. Nothing about the error handling changes.

**Why.** With an explicit parameter, every helper grows an `Env` argument it
only forwards. `geocodeAddress`, `fetchRoadData`, `resolveNodes` — three
helpers, three parameters that do nothing but get passed along, and the noise
scales with the call graph. The `ReaderT`-over-`IO` shape is what most
production Haskell converges on for exactly this reason; it is the pattern
Bellroy's engineering posts recommend, and it is why the pipeline in
`Services.Routing` reads as a flat list of steps.

**If you prefer the plan's version**, it is a mechanical change: drop `ReaderT`,
add `Env ->` to about six signatures, replace each `ask` with the parameter. The
`do` block in `routeByAddress` is untouched. Genuinely worth doing once as an
exercise — you will see exactly what the transformer is buying.

### Why a type synonym, not a `newtype`

A `type` synonym inherits `Monad`, `MonadIO`, `MonadReader` and `MonadError`
instances for free — no deriving boilerplate, no lifting to write. A `newtype`
would let you *hide* those instances from callers, which is valuable in a large
codebase where you want to control what effects are reachable. At this size that
is a cost, not a benefit.

### The C# analogy

`async Task<T>` that can throw a typed `AppError` and has an ambient injected
`Env`. The difference is that here both the failure and the dependency are
**visible in the type**, so a function that cannot fail says so, and a function
that needs no environment says that too — which is why
`Services.Routing.loadNetworkFromFile` is plain `IO`.

---

## The two combinators

```haskell
attempt  :: (e -> AppError) -> IO (Either e a) -> AppM a   -- for effectful steps
failWith :: (e -> AppError) -> Either e a      -> AppM a   -- for pure steps
```

Every layer below has its own error type — `GeoError`, `OverpassError`,
`GraphError`, `SnapError`, `RouteError` — and this is the one place they are
adapted. In Go the same job is `if err != nil { return fmt.Errorf("…: %w", err) }`
repeated after each call; here it is a combinator applied at each call, **and
the wrapping constructor is checked by the compiler**.

That last part is the practical difference. Go's `%w` preserves the cause but
reaching it needs `errors.As` and a type assertion. Here the cause is a field of
the constructor, so a handler, a test, or a future logger can pattern match on
it directly.

## Poke it in the REPL

```
ghci> import App.Env
ghci> import Control.Monad.Reader (ask)
ghci> env <- newEnv "."
ghci> runAppM env (fmap endpoints ask)
Right (Endpoints {nominatimSearch = "https://nominatim.openstreetmap.org/search", ...})
ghci> :type runAppM
runAppM :: Env -> AppM a -> IO (Either AppError a)
```
