# `API/Handlers.hs` — handlers, CORS, and the WAI application

## What it does

Implements the three endpoints declared in `API.Types`, wraps them in CORS, and
produces the `Application` that Warp (or Lambda) serves.

## The Go code it replaces

`backend/server/handlers.go` and the middleware in `backend/server/server.go`.

## `ServerT` and `hoistServer`

Servant's own handler monad is `Handler`, which is `ExceptT ServerError IO`. Our
pipeline runs in `AppM`, which knows about `Env` and `AppError` and nothing
about HTTP.

```haskell
handlers :: FilePath -> ServerT API AppM        -- written in AppM

server env = hoistServer api toHandler (handlers env.staticDir)
  where
    toHandler action = do
      outcome <- liftIO (runAppM env action)
      either (throwError . toServantError) pure outcome
```

`hoistServer` applies **one** natural transformation — "how to run an `AppM` as
a `Handler`" — to every handler at once.

**Why bother.** It keeps HTTP vocabulary out of the business logic and confines
the `AppError → ServerError` translation to a single function. If you have met
the pattern in C#, it is the same instinct as keeping `ControllerBase` out of
your service classes and mapping exceptions to status codes in one filter.

The alternative — writing handlers directly in `Handler` — would mean every
handler doing its own `runAppM` and its own error conversion, and the temptation
to reach for `throwError err400` from inside the pipeline.

## Handler order is checked

```haskell
handlers staticPath =
  handleRoute :<|> handleSuggest :<|> handleReverse :<|> staticFiles staticPath
```

Servant matches these left to right against the `API` type, and **the compiler
checks that this list lines up with the type constructor for constructor**. Swap
two handlers and it will not compile.

## What is *not* here: panic recovery

Go wraps everything in `panicRecoveryMiddleware`, because an unhandled panic
would otherwise take down the whole process:

```go
defer func() {
    if rec := recover(); rec != nil { ... http.Error(w, ..., 500) }
}()
```

**Warp already does this.** It isolates each request: an exception escaping a
handler fails that request with a 500 and leaves the server running. There is
nothing to add.

About thirty lines of Go — the middleware plus its two tests — have no
counterpart here, because the platform does the job. Worth noticing as a
category: some of the port's brevity is Haskell, and some of it is just a more
opinionated server library.

## Three failure policies, and why they differ

This is the part of the module worth reading carefully, because the three
handlers deliberately behave differently on failure and the reasons are not
arbitrary.

| Endpoint | On upstream failure | Why |
|---|---|---|
| `POST /api/route` | error response | There is no route to return. Failing is the only honest answer. |
| `GET /api/suggest` | `[]` with **200** | Autocomplete fires on every keystroke. A transient hiccup becoming a red banner would be far worse than briefly showing no suggestions. |
| `GET /api/reverse` | `{"address": ""}` with **200** | The user clicked the map. Losing the label is an annoyance; losing the pin would break the click-to-route flow. |

And within `/api/reverse`, two *different* policies coexist:

- unparseable `lat`/`lon` → **400**. The caller sent something wrong and should
  be told.
- Nominatim failure → **200** with an empty address. The caller did nothing
  wrong.

The distinguishing question is **whose fault it is**. All of this is Go's
behaviour, and `frontend/src/autocomplete.ts` and `main.ts` depend on it — there
are tests for each case.

## Query-parameter parsing

```haskell
parseParam name value =
  case readMaybe (T.unpack (T.strip given)) of
    Just parsed -> pure parsed
    Nothing     -> throwError . InvalidRequest $
                     "invalid " <> name <> ": " <> T.pack (show given)
  where given = fromMaybe "" value
```

A **missing** parameter and an **unparseable** one get the same treatment,
because Go's `strconv.ParseFloat("")` fails just as `ParseFloat("abc")` does.
Matching that keeps the error messages identical.

## CORS

```haskell
corsMiddleware =
  cors . const . Just $ simpleCorsResourcePolicy
    { corsMethods        = ["GET", "POST", "OPTIONS"]
    , corsRequestHeaders = ["Content-Type"] }
```

Mirrors Go's `corsMiddleware`: any origin, those three methods, a `Content-Type`
request header. `wai-cors` answers the `OPTIONS` preflight itself, which is the
`if r.Method == http.MethodOptions` branch in the Go version.

Wide open is right for a public read-only API called from a Vite dev server on a
different port. It would **not** be right for anything authenticated — the
`corsOrigins = Nothing` default means credentials from any site.

## `staticFiles` captures the directory

A `Raw` endpoint is a plain WAI application and so cannot read `AppM`'s
environment. The directory is captured from `Env` when the server is built:

```haskell
server env = hoistServer api toHandler (handlers env.staticDir)
```

## `defaultBuildOptions`

`handleRoute` passes `assumeBidirectional = True`, matching
`server/handlers.go`. Most OSM residential streets carry no `oneway` tag, and
treating those as one-way would fragment the network past usefulness. See
`src/Mapping.README.md` for the trade-off.
