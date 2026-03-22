# AlgoRoute

A route-finding application that fetches road network data from OpenStreetMap (via the Overpass API), converts it into a graph, and finds optimal routes using Dijkstra and A*.

## Architecture

Layered design — each layer depends only on layers below it. Backend is Go; frontend is TypeScript + Vite.

### Backend (`backend/`) — Go module `algoroute`

| Package | Responsibility |
|---|---|
| `api/overpass` | Fetches raw OSM JSON from Overpass API, parses into DTOs |
| `geo` | Geographic primitives: coordinates, bounding boxes, Haversine distance, geocoding |
| `graph` | Directed graph with adjacency list; nodes keyed by `int64` NodeID |
| `mapping` | Converts OSM DTOs → `graph.Network` |
| `routefinding` | Dijkstra and A* implementations; indexed min-heap |
| `services` | Orchestrates full pipeline: load network, find route, return results |
| `server` | HTTP server, request handlers, CORS, static file serving |
| `main.go` | Entry point: flags (`-serve`, `-port`, `-frontend`) |

Tests live in `tests/` subdirectories within each package. Fixtures in `testdata/`.

### Frontend (`frontend/`) — TypeScript + Vite

| Module | Responsibility |
|---|---|
| `types.ts` | Shared TypeScript types (RouteRequest, RouteResponse, etc.) |
| `config.ts` | Runtime configuration (API base URL, defaults) |
| `api.ts` | Typed wrappers for all backend API calls |
| `map.ts` | Leaflet map initialisation and layer management |
| `ui.ts` | DOM manipulation and form controls |
| `autocomplete.ts` | Address autocomplete dropdown |
| `animation.ts` | Animated traversal visualisation (Dijkstra=blue, A*=orange) |
| `geo.ts` | Browser geolocation helpers |
| `main.ts` | Application entry point, wires modules together |

## Tech Stack

**Backend:** Go 1.25.5, module `algoroute`, stdlib only

**Frontend:** TypeScript, Vite (dev server + bundler), Leaflet (map), Vitest + jsdom (tests)

## HTTP API

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/route` | Find route between two addresses; returns polyline + `visited_nodes` |
| `GET` | `/api/suggest` | Address autocomplete suggestions (proxies Nominatim) |
| `GET` | `/api/reverse` | Reverse geocode a lat/lon to a human-readable address |

## Running the App

```bash
# Terminal 1 — backend (from backend/)
cd backend
go build -o /tmp/algoroute . && /tmp/algoroute -serve -port 8080

# Terminal 2 — frontend dev server (from frontend/) — proxies /api/* to :8080
cd frontend
npm run dev
```

## Commands

### Backend (run from `backend/`)

```bash
go test ./...                   # all tests
go test -v ./routefinding/...   # specific package
go build -o /tmp/algoroute .    # build binary
go mod tidy                     # tidy modules
```

### Frontend (run from `frontend/`)

```bash
npm test           # vitest (watch mode)
npm run typecheck  # tsc --noEmit
npm run build      # build → frontend/dist/
```

## Development Practices

All new code must follow these skills — apply them without being asked:

- **Clean Code** (`clean-code` skill): descriptive naming, self-documenting structure, explained design decisions.
- **Test-Driven Development** (`test-driven-development` skill): write a failing test first, then implement the minimum code to pass, then refactor. Never write implementation before a test.

## Conventions
- Test packages use `_test` suffix (e.g., `package overpass_test`)
- External test packages live in a `tests/` subdirectory (e.g., `geo/tests/`, `services/tests/`)
- Errors wrapped with context: `fmt.Errorf("read file %q: %w", path, err)`
- Helper functions in tests prefixed `must` (e.g., `mustAddNode`, `mustAddEdge`)
- Maps for O(1) lookups; adjacency list for graph traversal
- All source files formatted with `gofmt`

## Project State

Current component status and test counts are tracked in [`PROJECT_STATE.md`](PROJECT_STATE.md).
