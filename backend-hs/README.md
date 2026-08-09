# AlgoRoute — Haskell backend

A port of the Go backend in [`../backend/`](../backend/) to Haskell, following
[`../haskell-rewrite-plan.html`](../haskell-rewrite-plan.html) and
[`TUTOR.md`](TUTOR.md).

**This exists to be read.** It is a reference implementation to work alongside
while you write your own — so every module ships a `README.md` explaining its
algorithm, its complexity, and why the Haskell shape differs from the Go code it
replaces. The code is heavily commented for the same reason. If you only want to
read four of them, read these:

| | Why |
|---|---|
| [`src/Overpass/Types.README.md`](src/Overpass/Types.README.md) | Sum types vs. a struct with a string tag. The clearest single win. |
| [`src/Routefinding/Search.README.md`](src/Routefinding/Search.README.md) | Three Go files become one function plus three lambdas. |
| [`src/Routefinding/Router.README.md`](src/Routefinding/Router.README.md) | Where Go's idiom and Haskell's genuinely disagree, and why. |
| [`src/App/Env.README.md`](src/App/Env.README.md) | How the environment removes six test-only functions. |

## Status

| | |
|---|---|
| Library + local server | Compiles clean under `-Wall -Wcompat -Wredundant-constraints` |
| Test suite | **161 examples, 0 failures** (`cabal test`) |
| CLI parity with Go | Byte-identical output for all four algorithms on the shared fixture |
| Nix flake | **Not verified here** — see [Nix and Lambda](#nix-and-lambda) |
| AWS Lambda entry point | **Not verified here** — written, never compiled |

Built and tested with **GHC 9.4.7** and **cabal-install 3.8.1**.

## Quick start

```bash
cd backend-hs

cabal build                 # library + backend-hs-local
cabal test                  # the HSpec suite
cabal repl backend-hs       # poke at functions interactively

# Serve the API and the built frontend
cabal run backend-hs-local -- --serve --port 8080 --frontend ../frontend/dist

# Route between two node IDs in a local OSM file, no network needed
cabal run backend-hs-local -- --data test/testdata/sample_overpass.json \
                              --start 27347732 --end 27347552 --algo astar
```

With the Vite dev server in another terminal (`cd frontend && npm run dev`),
which proxies `/api/*` to `:8080`, the existing frontend talks to this backend
unchanged.

There is also `./check.sh`, which typechecks individual modules against the
already-built dependency closure — useful while a module is half-written and
`cabal build` cannot run yet.

## Layout

```
backend-hs/
├── README.md               ← you are here
├── TUTOR.md                ← how to learn this with Claude Code as a tutor
├── backend-hs.cabal        ← modules, dependencies, build flags
├── flake.nix               ← Nix dev shell + Lambda packaging (untested here)
├── check.sh                ← fast per-module typecheck
├── app/
│   ├── Main.hs             ← CLI, Warp server, Lambda branch
│   └── Main.README.md
├── src/                    ← every .hs has a sibling .README.md
│   ├── App/{Env,Error}.hs
│   ├── Geo/{Types,Distance,BBox,Nominatim,Geocode,Suggest,Reverse}.hs
│   ├── Graph.hs, Graph/Snap.hs
│   ├── Overpass/{Types,Client}.hs
│   ├── Mapping.hs
│   ├── Routefinding/{Types,Heap,Search,Dijkstra,AStar,
│   │                 GreedyBestFirst,Bidirectional,Router}.hs
│   ├── Services/{Cache,Routing}.hs
│   └── API/{Types,Handlers}.hs
└── test/
    ├── Spec.hs, SpecTree.hs      ← entry point + hspec-discover
    ├── TestSupport.hs            ← network builders, stub upstreams
    ├── **/*Spec.hs
    └── testdata/sample_overpass.json   ← copied from ../backend/mapping/testdata/
```

Naming: `Heap.hs` ↔ `Heap.README.md`. One directory cannot hold two files called
`README.md`, so per-module docs are named after their module.

## Where each Go package went

| Go | Haskell | Note |
|---|---|---|
| `graph/` (4 files) | `Graph.hs`, `Graph/Snap.hs` | `Network` is an immutable value |
| `geo/coords.go`, `bbox.go` | `Geo/Types.hs`, `Geo/BBox.hs` | types split from operations |
| `geo/distance.go` | `Geo/Distance.hs` | identical formula |
| `geo/{geocode,suggest,reverse}.go` | `Geo/{Geocode,Suggest,Reverse}.hs` + `Geo/Nominatim.hs` | shared plumbing factored out |
| `api/overpass/` | `Overpass/{Types,Client}.hs` | `Element` becomes a sum type |
| `mapping/` | `Mapping.hs` | |
| `routefinding/` (4 algorithms) | `Routefinding/` (8 modules) | 3 algorithms share one search |
| `services/` | `Services/{Cache,Routing}.hs`, `App/{Env,Error}.hs` | |
| `server/` | `API/{Types,Handlers}.hs` | API declared as a type |
| `main.go` | `app/Main.hs` | |

## The HTTP contract is unchanged

Fixed by `frontend/src/types.ts` and asserted by the tests:

| Method | Path | Body / params |
|---|---|---|
| `POST` | `/api/route` | `{origin, destination, algorithm}` → `{algorithm, distance_meters, path[], visited_nodes[], origin_coord, destination_coord}` |
| `GET` | `/api/suggest` | `?q=` → `[{display_name, lat, lon}]` |
| `GET` | `/api/reverse` | `?lat=&lon=` → `{address}` |

Algorithm names: `dijkstra`, `astar`, `greedy`, `bidijkstra`.

## The four algorithms

All four are ported, matching the current Go backend (the rewrite plan predates
the last two).

| | Priority | Optimal? | Animation |
|---|---|---|---|
| Dijkstra | `g` | yes | even circle |
| A* | `g + h` | yes | cone toward the goal |
| Greedy best-first | `h` | **no** | sprint, then back out |
| Bidirectional Dijkstra | `g`, from both ends | yes | two circles meeting |

The first three are one function with three different lambdas — see
[`src/Routefinding/Search.README.md`](src/Routefinding/Search.README.md).
Bidirectional is genuinely different and has its own implementation.

## Testing

```bash
cabal test
```

161 examples, ported from the Go suite in `backend/**/tests/` and
`backend/routefinding/*_test.go`. Notable choices:

- **The HTTP tests drive a real Warp server** over a real socket
  (`testWithApplication` + `http-client`), rather than invoking the WAI
  `Application` in process with `hspec-wai`. Slower, but it exercises CORS,
  content negotiation and status codes — the parts most likely to be wrong. It
  is the direct equivalent of Go's `httptest.Server`.
- **Stub upstreams come from `App.Env.Endpoints`**, so the code under test is
  the production code path, not a `…WithBaseURL` twin.
- **Two QuickCheck properties** where they earn their place: heap pops are
  non-decreasing whatever the insertion order, and Haversine is symmetric for
  all coordinate pairs.
- **The fixture is shared** with the Go suite — the same
  `sample_overpass.json`, so both are asserting against identical bytes.

Adding a `*Spec.hs` file under `test/` is enough to have it run; `hspec-discover`
finds it. Add it to `other-modules` in the `.cabal` file too.

## Parity with the Go backend

Verified directly, not assumed:

```bash
cd backend && go build -o /tmp/algoroute-go .
for algo in dijkstra astar greedy bidijkstra; do
  diff <(/tmp/algoroute-go        -data  ../backend-hs/test/testdata/sample_overpass.json \
                                  -start 27347732 -end 27347552 -algo  $algo) \
       <(cabal run -v0 backend-hs-local -- \
                                  --data test/testdata/sample_overpass.json \
                                  --start 27347732 --end 27347552 --algo $algo)
done
```

All four produce **byte-identical output**, including path and distance
(349.24 m). That is not free — it needed `Graph.finalizeAdjacency` to preserve
Go's edge insertion order, because tie-breaking in the heap follows adjacency
order and changes which of two equal-cost routes is returned.

Two places where this port is deliberately *more* deterministic than Go, because
Go randomises map iteration order:

- `Graph.Snap.nearestNode` always returns the lowest node ID among ties.
- `Routefinding.Bidirectional.reverseAdjacency` builds its lists in a fixed
  order.

Both mean the Haskell backend gives the same answer every run, which Go cannot
promise even against itself.

## Nix and Lambda

**Neither has been exercised in this repository.** Nix is not installed in the
environment this port was written in, and the Lambda entry point has never been
compiled. The files are in place and documented; treat them as unverified.

To check them locally:

```bash
nix develop ./backend-hs      # toolchain shell: ghc, cabal, HLS, hlint, fourmolu
nix build ./backend-hs        # dynamically-linked binary
nix build ./backend-hs#lambda # static musl binary, zipped as `bootstrap`
```

The Lambda executable is behind a **default-off cabal flag** so that
`wai-handler-hal` and its dependency closure never block a plain build:

```bash
cabal build -f lambda
```

If `wai-handler-hal` does not build against your GHC, nothing else is affected —
that is the entire reason for the flag.

## Toolchain notes

This port was built with a system GHC and `cabal`, not through Nix:

```bash
apt-get install -y ghc cabal-install
cabal update
```

One environment-specific wrinkle worth recording: `cabal update` failed behind a
filtering proxy because `hackage-security` resolves a mirror
(`hackage-mirror.s3.…dream.io`) that was blocked, while `hackage.haskell.org`
itself was reachable. Setting `secure: False` on the repository in
`~/.cabal/config` skips the mirror lookup and fetches the index directly. Not
needed on an unrestricted network, and not needed at all under Nix.

## Conventions

Following [`../CLAUDE.md`](../CLAUDE.md):

- Test helpers that abort on failure are prefixed `must` (`mustNetwork`,
  `mustRight`, `mustLoadFixture`).
- `Data.Map.Strict`, never lazy `Map` — the space-leak footgun `TUTOR.md` warns
  about.
- `DerivingStrategies`, `LambdaCase` and `OverloadedStrings` are project-wide in
  the `.cabal` file, because they are boilerplate.
- `DuplicateRecordFields` and `OverloadedRecordDot` are **per module**, because
  they are design decisions — the pragma is a visible signal that the module
  juggles overlapping field names. See
  [`src/Geo/Types.README.md`](src/Geo/Types.README.md), which explains that trap
  in full.
- Errors are closed sum types per layer, converged into `App.Error.AppError` at
  the boundary.

## Known gaps

Inherited from the Go backend and listed in
[`../PROJECT_STATE.md`](../PROJECT_STATE.md):

- No rate limiting, no input length validation.
- `Geo.BBox.fromCoords` does not enforce ±90°/±180° bounds.
- `Geo.Suggest` drops unparseable results silently, without logging.
- `Services.Cache` is unbounded — no eviction, no TTL.
- `Graph.Snap.nearestNode` is an O(n) scan.

New to this port:

- `Mapping` reproduces a Go quirk where an *unrecognised* `oneway` value
  (a typo, or a conditional restriction) makes a way one-way rather than
  falling back to the untagged behaviour. Asserted by a test, with the
  reasoning written out. Change both backends together.
- Status codes follow Go rather than what is strictly correct — `AreaTooLarge`
  is a 500 where 422 would be better. See
  [`src/App/Error.README.md`](src/App/Error.README.md).
