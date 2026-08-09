# `app/Main.hs` — entry point

## What it does

Parses command-line arguments and runs one of three things: a local HTTP server,
a one-shot route against a file, or — under a build flag — an AWS Lambda
handler.

## The Go code it replaces

`backend/main.go`, including both of its modes.

## One file, two executables

`backend-hs.cabal` compiles this module twice:

| Executable | Built by | `-DLAMBDA` | Entry point |
|---|---|---|---|
| `backend-hs-local` | `cabal build` | no | Warp `run` |
| `backend-hs` | `cabal build -f lambda` | yes | `wai-handler-hal` |

That is what the `cpp-options: -DLAMBDA` line in the `.cabal` file selects, and
it is the same trick as a C `#ifdef` because it **is** a C `#ifdef` — GHC runs
the C preprocessor over the file first when `CPP` is enabled.

The Lambda executable sits behind a **default-off cabal flag** because
`wai-handler-hal` pulls in the `hal` custom-runtime client and its dependency
closure, which is irrelevant until you actually deploy. A plain `cabal build`
never touches it.

## Two modes, made exclusive

```haskell
data Command
  = Serve ServeOptions
  | RouteFile FileOptions
```

Go uses a single flat set of `flag` variables and decides between modes by
testing `*serveMode`, so `-serve -start 42` is accepted and the extra flags are
silently ignored.

A sum type makes the two exclusive: a `Serve` carries no node IDs because
serving does not have any. `optparse-applicative` generates the alternation in
`--help` too:

```
Usage: backend-hs-local (--serve [--port PORT] [--frontend DIR]
                        | --data FILE --start NODE_ID --end NODE_ID [--algo NAME])
```

## `optparse-applicative` vs `flag`

Parsers are built from small pieces combined with `<$>` and `<*>`, the same way
`aeson` builds decoders. The payoff over Go's `flag` package is that `--help` is
generated **from the same description that does the parsing**, so the two cannot
drift apart. The algorithm list in the help text comes from
`Routefinding.Router.allAlgorithms`, so it stays correct if an algorithm is
added.

## What Warp does for free

Go builds an `http.Server`, starts it in a goroutine, waits on a
`signal.NotifyContext`, and calls `Shutdown` with a five-second grace period —
about thirty lines.

Warp's `run` already installs the equivalent: on `SIGINT`/`SIGTERM` it stops
accepting new connections and lets in-flight requests finish. Those thirty lines
have no counterpart here.

## The UTF-8 lines are not decoration

```haskell
hSetEncoding stdout utf8
hSetEncoding stderr utf8
```

**This is a real bug that this port hit during development.**

Haskell picks a `Handle`'s encoding from the process locale. On a machine with
`LANG=C` or `LANG=POSIX` — the default in many containers and CI images —
writing a single non-ASCII character throws
`commitBuffer: invalid argument` and kills the program.

The em dash in the `--help` text triggers it. So would a street name like
`Grüner Weg` coming back from OSM in the CLI's path listing.

Go has no equivalent failure mode: its strings are already UTF-8 bytes and it
writes them unchanged. Two lines buy the same behaviour. The test suite's
`Spec.hs` needs the same treatment, for the same reason.

## The Lambda branch

```haskell
runServer options = do
  env <- newEnv options.frontendDir
  runWithOptions defaultOptions (application env)
```

`wai-handler-hal` adapts a WAI `Application` to the Lambda custom runtime: it
owns the invocation loop, decodes each API Gateway event into a WAI `Request`,
and encodes the response back. **The application code is unchanged** — the same
`application env` the Warp server runs.

The Lambda runtime executes a binary named `bootstrap`; `flake.nix` renames this
executable accordingly when packaging the zip.

Port and frontend directory are meaningless there: nothing listens on a socket,
and the frontend would be on S3 or a CDN. The static directory is still set so a
request reaching the `Raw` fallback produces a clean 404 rather than an
exception.

**Not verified.** This branch has never been compiled in this repository — see
the top-level `README.md` for what is and is not tested.

## CLI mode

```
backend-hs-local --data test/testdata/sample_overpass.json \
                 --start 27347732 --end 27347552 --algo astar
```

The original CLI behaviour, preserved. Useful for exercising the algorithms
against a fixture with no network access at all — and it is how this port's
output was checked against the Go backend's, byte for byte, for all four
algorithms.
