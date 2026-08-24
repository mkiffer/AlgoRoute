# Checking your work — commands & tests

Run everything from `backend-hs/`, inside the toolchain shell:

```bash
cd backend-hs
nix develop        # first thing every session — gives you ghc, cabal, hlint, fourmolu
```

Test scaffolding already exists under `test/` (hspec + QuickCheck + hspec-wai).
`hspec-discover` auto-collects every `*Spec.hs`; when you add a new one, also add
its module name to `other-modules` in `backend-hs.cabal` (one line).

---

## Correctness

```bash
cabal test                                            # run the whole suite
cabal test --test-show-details=direct                 # show each example as it runs
cabal test --test-options='--match "Dijkstra"'        # run one module/group
cabal test --test-options='--match "Geo.Distance"'    # match by describe/it text
cabal test --test-options='--seed 42'                 # reproduce a QuickCheck failure
```

**TDD loop:** a stub is `undefined`, so its test fails (red) until you implement
it — that's expected. Fill the body, re-run the matching test, watch it go green,
then move to the next module. Work bottom-up in the order in
[`STUBS_GUIDE.html`](STUBS_GUIDE.html) so a test never depends on an
`undefined` you haven't reached.

**REPL — the fastest feedback loop** (much quicker than a full `cabal test`):

```bash
cabal repl backend-hs
ghci> import Geo.Types
ghci> import Geo.Distance
ghci> distanceMeters (Coord 0 0) (Coord 1 0)     -- expect ~111194.93
ghci> :reload                                    -- after editing, re-run
ghci> :type bboxFromCoords                        -- ask the compiler, not yourself
```

**Live recompile (optional, very nice):** add `ghcid` to the dev shell, then
`ghcid -c 'cabal repl backend-hs'` shows errors on every save.

### What each spec verifies

| Spec file | Module under test | What it pins down |
|---|---|---|
| `Geo/TypesSpec.hs` | `Geo.Types` | `contains` boundaries; area ≈0 for a zero-span box; **padding invariant** — a padded box must still contain both input points (catches a wrong-sign `bboxFromCoords`) |
| `Geo/DistanceSpec.hs` | `Geo.Distance` | zero distance to self; golden ~111195 m per degree (also the Go cross-check); symmetry property |
| `Routefinding/HeapSpec.hs` | `Routefinding.Heap` | property: draining pops priorities in sorted order; `decreaseKey` reorders; `member` |
| `Routefinding/DijkstraSpec.hs` | `Routefinding.Dijkstra` | trivial `start==goal`; cheapest path + distance through a diamond; `Left` when unreachable |
| `Overpass/TypesSpec.hs` | `Overpass.Types` | the fixture parses; `mkResponse` fills the ways list + node index; every way is a `WayElement` |
| `MappingSpec.hs` | `Mapping` | fixture yields nodes+edges; bidirectional ≥ one-way edge count |
| `API/HandlersSpec.hs` | `API.Handlers` | 400 on missing/malformed route body; `/api/suggest` → `[]`; 400 on missing reverse params (no network hit) |

### Cross-check against the Go backend

The Haskell port must match the existing Go behavior. Pull exact golden numbers
from the Go tests and pin them in the Haskell specs (see the `TODO` in
`MappingSpec.hs`):

```bash
cd ../backend
go test ./...                     # confirm the reference suite is green
go test -v ./mapping/...          # read the exact node/edge counts to assert on
go test -v ./routefinding/...     # reference path/distance results
```

---

## Quality

```bash
cabal build                       # -Wall is on (see the shared stanza) — treat warnings as TODOs
cabal build --ghc-options=-Werror # optional: make warnings hard failures
hlint src app test                # idiom & simplification suggestions
fourmolu --mode check src app test   # fail if anything is unformatted
fourmolu -i src app test          # auto-format in place
```

Suggested pre-commit gate — all four green:

```bash
fourmolu --mode check src app test && hlint src app test && cabal build && cabal test
```

While bodies are still `undefined` you'll see `-Wall` "defined but not used"
warnings for helpers — harmless until the module is finished. The `_`-prefixed
stub helpers are named that way on purpose to stay quiet.

---

## End-to-end smoke test (once handlers + Main are done)

```bash
cabal run backend-hs-local -- --port 8080         # start the Haskell server
curl -s localhost:8080/api/suggest?q=melbourne    # expect a JSON array
curl -s -X POST localhost:8080/api/route \
  -H 'content-type: application/json' \
  -d '{"origin":"Flinders St Station, Melbourne","destination":"MCG, Melbourne","algorithm":"dijkstra"}'
```

Then point the existing frontend at it — the JSON field names are unchanged, so
it should work without edits:

```bash
cd ../frontend && npm run dev     # Vite proxies /api/* to :8080
```
```
