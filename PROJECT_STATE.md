# AlgoRoute — Project State

> Companion to `CLAUDE.md`. Update this file as components are built or tests change.
> Do NOT use this file for architecture decisions or conventions — those live in CLAUDE.md.

## Component Status

| Component | Status | Notes |
|-----------|--------|-------|
| Graph core (`graph/`) | Complete | 5 passing tests (network + NearestNode snap) |
| OSM API client (`api/overpass/`) | Complete | 5 passing tests (client + BuildOverpassQuery/FetchFromAPIWithBaseURL) |
| Data mapping (`mapping/`) | Complete | 1 passing test |
| Geo utilities (`geo/`) | Complete | 12 passing tests (DistanceMeters, BBox, Geocode/NominatimURL) |
| Dijkstra algorithm (`routefinding/dijkstra.go`) | Complete | 9 passing tests |
| A* algorithm (`routefinding/astar.go`) | Complete | 9 passing tests + 1 A*-vs-Dijkstra efficiency test |
| Router interface (`routefinding/router.go`) | Complete | `DijkstraRouter` and `AStarRouter` wrappers; returns `RouteResult` |
| Service layer (`services/`) | Complete | 11 passing tests (8 original + 3 RouteByAddress) |
| HTTP server (`server/`) | Complete | 4 passing tests (handleRoute: 200, 400 ×2, visited_nodes) |
| `main.go` | Complete | `-serve`, `-port`, `-frontend`, `-data`, `-start`, `-end`, `-algo` flags |
| Frontend (`frontend/index.html`) | Complete | Leaflet map, address inputs, traversal animation, speed slider |

**Total: 52 tests passing** (`go test ./...` from `backend/`)

## Known Issues

### Security
- **No CORS headers** — backend sets no CORS headers; frontend will fail if served from a different origin.
- **No request body size limit** — HTTP handlers accept arbitrarily large JSON bodies (DoS risk).
- **No rate limiting** — autocomplete fires on every keystroke (debounced), but the backend has no per-IP throttling.
- **No input length validation** — addresses are forwarded to Nominatim without length or character checks.
- **Unvalidated bbox coordinates** — `BBoxFromCoords` does not enforce ±90° / ±180° bounds.

### Error Handling
- **`json.Encode` error ignored** — `writeJSON()` in `server/handlers.go:50` discards the encoder error.
- **Nil `Tags` map** — `mapping/road_mapper.go:72,85` accesses `way.Tags["name"]` without guarding against a nil map (panics if `Tags` is nil).
- **Silent suggestion failures** — `geo/suggest.go` skips unparseable lat/lon with `continue` and no logging, making failures invisible.
- **Non-JSON error responses** — frontend (`index.html:414`) parses `data.error` but doesn't handle the case where the API returns non-JSON on error.

### Missing Test Coverage
- **Address-routing edge cases** — no test for when origin and destination geocode to the same graph node.
- **Malformed Overpass responses** — no test for truncated or structurally invalid JSON from the Overpass API.
- **Extreme coordinates** — no test for poles (±90°) or antimeridian (±180°) in geocoding / bbox helpers.
- **Duplicate-coordinate snapping** — no test for a network where multiple nodes share identical coordinates.

### Incomplete Features
- **One-way street support** — `mapping/road_mapper.go` notes that OSM `oneway` tag handling is a future enhancement; all roads are currently treated as bidirectional.

### Performance
- **No network caching** — every route request fetches the full road network from Overpass; repeated requests for the same area re-fetch from scratch.
- **O(n) nearest-node scan** — `graph.NearestNode()` is a linear scan; a spatial index (k-d tree / quadtree) would be needed for large networks.

### Code Quality
- **No graceful shutdown** — `main.go` calls `http.ListenAndServe()` with no signal handling or cleanup on exit.
- **No panic recovery** — HTTP handlers have no recovery middleware; a nil-map panic would crash the server.
- **Hardcoded map center** — frontend initialises the Leaflet map at Melbourne (`[-37.82, 144.97]`); should derive centre from the routed coordinates.
- **Whitespace-only address check** — frontend trims input but does not enforce a minimum meaningful length before submitting.
- **Exported test-only helpers** — `NominatimURL()` and `SuggestURL()` are exported but only used in tests; could be unexported.

## Next Steps (Suggested Priority Order)

1. Add CORS middleware to the HTTP server.
2. Add panic-recovery middleware and graceful shutdown to `main.go`.
3. Enforce a max request-body size in the HTTP handler (e.g., `http.MaxBytesReader`).
4. Fix `writeJSON` to check and log the `json.Encode` error.
5. Guard against nil `Tags` map in `mapping/road_mapper.go`.
6. Implement one-way street support via the OSM `oneway` tag.
7. Add a simple in-memory cache for recently fetched road networks (keyed by bbox).
8. Validate bbox coordinates in `BBoxFromCoords`.
9. Centre the Leaflet map on the routed result rather than a hardcoded Melbourne coordinate.
10. Add missing edge-case tests (same-node routing, malformed Overpass JSON, extreme coordinates).
