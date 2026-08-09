# `test/` — the HSpec suite

161 examples, ported from the Go tests in `backend/**/tests/` and
`backend/routefinding/*_test.go`.

```bash
cabal test                                    # everything
cabal run spec -- --match "/Routefinding/"    # one area
cabal run spec -- --seed 1983780963           # reproduce an ordering
```

## Layout

| File | Ports from |
|---|---|
| `Geo/DistanceSpec.hs` | `geo/tests/geo_test.go` (distance half) |
| `Geo/BBoxSpec.hs` | `geo/tests/bbox_helpers_test.go` + `BBoxContains` |
| `GraphSpec.hs` | `graph/tests/network_test.go` |
| `Graph/SnapSpec.hs` | `graph/tests/snap_test.go` |
| `Routefinding/HeapSpec.hs` | `routefinding/indexed_heap_test.go` |
| `Routefinding/DijkstraSpec.hs` | `routefinding/dijkstra_test.go` |
| `Routefinding/AStarSpec.hs` | `routefinding/astar_test.go` |
| `Routefinding/GreedyBestFirstSpec.hs` | `routefinding/greedy_best_first_test.go` |
| `Routefinding/BidirectionalSpec.hs` | `routefinding/bidirectional_dijkstra_test.go` |
| `Routefinding/RouterSpec.hs` | algorithm selection from `services/tests/routing_test.go` |
| `Overpass/TypesSpec.hs` | `api/overpass/tests/client_test.go` |
| `Overpass/ClientSpec.hs` | `api/overpass/tests/fetch_test.go` |
| `MappingSpec.hs` | `mapping/tests/{mapping,oneway}_test.go` |
| `Services/CacheSpec.hs` | `services/tests/network_cache_test.go` |
| `Services/RoutingSpec.hs` | `services/tests/address_routing_test.go` |
| `API/HandlersSpec.hs` | `server/{handlers,middleware}_test.go` |

`SpecTree.hs` is the `hspec-discover` shim — it scans for `*Spec.hs` and
stitches their `spec` values together, so adding a file is all that is needed to
have it run. Add it to `other-modules` in the `.cabal` file too.

`Spec.hs` is hand-written rather than a one-line shim only because of two
`hSetEncoding` calls. Test descriptions contain `km²` and `→`, and a Haskell
`Handle` takes its encoding from the process locale — under `LANG=C`, common in
containers, printing one of those kills the suite mid-run.

## Choices worth knowing

**HTTP tests drive a real server.** `API/HandlersSpec.hs` starts Warp on a free
port (`testWithApplication`) and talks to it with `http-client`, rather than
invoking the WAI `Application` in process with `hspec-wai`. Slower, but it
exercises CORS, content negotiation and status codes — the parts most likely to
be wrong. It is the direct equivalent of Go's `httptest.Server`.

**Stubs come from `Env`, not from parallel functions.** A stub upstream is a WAI
app served on a free port, and its URL goes into `App.Env.Endpoints`. So the code
under test is the production code path — not a `…WithBaseURL` twin that
production never calls. See `src/App/Env.README.md`.

One stub server stands in for Nominatim search, Nominatim reverse and Overpass,
dispatching on path. It tells origin from destination by reading the `q`
parameter, which is two lines — Go needs a second base-URL field threaded
through three layers to do the same thing.

**Fixtures are `aeson` `Value`s, not JSON string literals.** A literal with a
typo produces a confusing decode failure halfway through a test; building the
value means the compiler checks the structure. `MappingSpec` uses this heavily.

**The Overpass fixture is shared with the Go suite** — the same
`sample_overpass.json`, copied rather than regenerated, so both suites assert
against identical bytes. `Services/RoutingSpec.hs` asserts the exact distance
the Go backend reports (349.24 m) for the same node pair, which makes it a
parity test rather than a smoke test.

**Two QuickCheck properties, where they earn their place.** Heap pops are
non-decreasing whatever the insertion order — examples can only check the
orderings someone thought to write down, and the deep `siftDown` cases need a
dozen entries. And Haversine is symmetric for all coordinate pairs, because
swapping a subtraction in the wrong place leaves every hand-written example
passing. Everything else is an example, because everything else has a specific
behaviour worth naming.

## Two fixtures that took a second attempt

Worth knowing if you write your own, because both failed in the obvious form:

**"A* settles fewer nodes than Dijkstra" needs a *cheap* detour.** The first
version put an expensive detour to the north — which proves nothing, because
Dijkstra would not expand it either. Both algorithms settled the same four
nodes. What separates them is cheap roads leading *away* from the goal:
Dijkstra, ordering by `g` alone, settles all of them; A* adds `h`, which makes
those nodes look expensive, and never expands them.

**"A* and Dijkstra agree on the path" needs a unique optimum.** On a lattice
where many routes tie on cost, the two break ties differently and the assertion
fails for a reason that has nothing to do with correctness. The grid test
asserts only the *distance* — which is exactly the guarantee, and not more than
it — and a separate fixture with a unique optimum checks the path.
