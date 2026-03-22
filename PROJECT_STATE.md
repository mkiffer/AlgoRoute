# AlgoRoute — Project State

> Companion to `CLAUDE.md`. Update this file as components are built or tests change.
> Do NOT use this file for architecture decisions or conventions — those live in CLAUDE.md.

## Component Status

| Component | Status | Notes |
|-----------|--------|-------|
| Graph core (`graph/`) | Complete | 5 passing tests (network + NearestNode snap) |
| OSM API client (`api/overpass/`) | Complete | 6 passing tests (client + BuildOverpassQuery/FetchFromAPIWithBaseURL + oversized response rejection) |
| Network cache (`services/network_cache.go`) | Complete | 2 passing tests (same-bbox cache hit; different-bbox fetches separately) |
| Data mapping (`mapping/`) | Complete | 5 passing tests (smoke + 4 oneway) |
| Geo utilities (`geo/`) | Complete | 19 passing tests (DistanceMeters, BBox, Geocode/NominatimURL, ReverseGeocode) |
| One-way street support (`mapping/road_mapper.go`) | Complete | 4 passing tests (oneway=yes, oneway=-1, oneway=no, untagged+bidirectional) |
| Dijkstra algorithm (`routefinding/dijkstra.go`) | Complete | 9 passing tests |
| A* algorithm (`routefinding/astar.go`) | Complete | 9 passing tests + 1 A*-vs-Dijkstra efficiency test |
| Router interface (`routefinding/router.go`) | Complete | `DijkstraRouter` and `AStarRouter` wrappers; returns `RouteResult` |
| Service layer (`services/`) | Complete | 14 passing tests (8 original + 3 RouteByAddress + 1 oversized bbox + 2 NetworkCache) |
| HTTP server (`server/`) | Complete | 15 passing tests (handleRoute: 200, 400 ×3, visited_nodes; suggest: empty, valid, failure; reverse: valid, missing lat, failure; CORS: regular + preflight; panic recovery: panic→500, normal→passthrough) |
| Reverse geocoding (`geo/reverse.go`) | Complete | `GET /api/reverse?lat=X&lon=Y` → `{"address":"..."}`, degrades gracefully |
| `main.go` | Complete | `-serve`, `-port`, `-frontend`, `-data`, `-start`, `-end`, `-algo` flags |
| Frontend map module (`map.ts`) | Complete | Click markers, radius circle, `onMapClick`/`offMapClick`, `clearRouteOverlays` vs `clearAll` split |
| Frontend geo module (`geo.ts`) | Complete | `haversineMeters` mirrors Go backend; used for client-side distance validation |
| Click-to-place routing (`main.ts`) | Complete | 2-click state machine, drag-to-reroute, 3rd-click reset, typed-input clears click state |
| Frontend (`frontend/`) | Complete | 54 TypeScript tests — api (8), config (16), map (12), autocomplete (8), ui (10) |

**Total: 70 Go + 54 TypeScript = 124 tests passing** (`go test ./...` from `backend/`; `npm test` from `frontend/`)

## Known Issues

### Security
- **No rate limiting** — autocomplete fires on every keystroke (debounced), but the backend has no per-IP throttling.
- **No input length validation** — addresses are forwarded to Nominatim without length or character checks.
- **Unvalidated bbox coordinates** — `BBoxFromCoords` does not enforce ±90° / ±180° bounds.

### Error Handling
- **Silent suggestion failures** — `geo/suggest.go` skips unparseable lat/lon with `continue` and no logging, making failures invisible.
- **Non-JSON error responses** — frontend (`index.html:414`) parses `data.error` but doesn't handle the case where the API returns non-JSON on error.

### Missing Test Coverage
- **Address-routing edge cases** — no test for when origin and destination geocode to the same graph node.
- **Malformed Overpass responses** — no test for truncated or structurally invalid JSON from the Overpass API.
- **Extreme coordinates** — no test for poles (±90°) or antimeridian (±180°) in geocoding / bbox helpers.
- **Duplicate-coordinate snapping** — no test for a network where multiple nodes share identical coordinates.

### Incomplete Features
- ~~**One-way street support**~~ ✓ Done — `mapping/road_mapper.go` now parses `oneway` tags (`yes`/`1`/`true`, `-1`/`reverse`, `no`/`0`/`false`).
- ~~**Click-to-place pins**~~ ✓ Done — 2-click state machine in `main.ts`; origin=green pin + radius circle, destination=red pin, auto-routes; drag to reroute; 3rd click resets.

### Performance
- ~~**No network caching**~~ ✓ Done — `services.NetworkCache` caches `overpass.Response` by `geo.BBox`; the `Server` holds a shared instance so Dijkstra/A* comparisons on the same route share one Overpass fetch.
- **O(n) nearest-node scan** — `graph.NearestNode()` is a linear scan; a spatial index (k-d tree / quadtree) would be needed for large networks.

### Code Quality
- **Hardcoded map center** — frontend initialises the Leaflet map at Melbourne (`[-37.82, 144.97]`); should derive centre from the routed coordinates.
- **Whitespace-only address check** — frontend trims input but does not enforce a minimum meaningful length before submitting.
- **Exported test-only helpers** — `NominatimURL()` and `SuggestURL()` are exported but only used in tests; could be unexported.

## Next Steps (Suggested Priority Order)

1. ~~Add panic-recovery middleware and graceful shutdown to `main.go`.~~ ✓ Done.
2. ~~Enforce a max request-body size in the HTTP handler.~~ ✓ Done (`http.MaxBytesReader`).
3. ~~Fix `writeJSON` to check and log the `json.Encode` error.~~ ✓ Already done.
4. ~~Guard against nil `Tags` map in `mapping/road_mapper.go`.~~ ✓ Covered by `Element.Tag()` helper.
5. ~~Implement one-way street support via the OSM `oneway` tag.~~ ✓ Done.
6. ~~Add a simple in-memory cache for recently fetched road networks (keyed by bbox).~~ ✓ Done (`services.NetworkCache`, shared across requests on `Server`).
7. ~~Centre the Leaflet map on the routed result.~~ ✓ Already done (`animation.ts` calls `fitToBounds` on start).
8. ~~Add click-to-place route points.~~ ✓ Done — `geo/reverse.go`, `GET /api/reverse`, `map.ts` click/drag methods, `main.ts` state machine.
9. Validate bbox coordinates in `BBoxFromCoords` (enforce ±90°/±180° bounds).
10. Add missing edge-case tests (same-node routing, malformed Overpass JSON, extreme coordinates).
11. Add cache eviction / TTL so stale road networks are eventually refreshed.
