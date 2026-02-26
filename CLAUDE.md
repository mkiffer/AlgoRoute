# AlgoRoute

A route-finding application written in Go that fetches road network data from OpenStreetMap (via the Overpass API), converts it into a graph, and finds optimal routes using graph algorithms (Dijkstra, A*).

## Project Structure

```
backend/
├── api/overpass/       # Overpass API client — fetches OSM road data
├── geo/                # Coordinate types, bounding box, Haversine distance
├── graph/              # Core graph: Node, Edge, Network (adjacency list)
├── mapping/            # Converts OSM API responses → graph representation
├── routefinding/       # Dijkstra and A* algorithm implementations
├── services/           # High-level routing orchestration
└── main.go             # Entry point
frontend/               # (empty)
```

## Tech Stack
- **Language:** Go 1.25.5 (module: `algoroute`)
- **Dependencies:** stdlib only — no external packages
- **Data source:** OpenStreetMap via Overpass API

## Commands

```bash
# Run all tests
go test ./...

# Run tests for a specific package
go test -v ./backend/routefinding

# Build
go build -o algoroute ./backend

# Tidy modules
go mod tidy
```

Tests live in `tests/` subdirectories within each package. Test fixtures are in `testdata/` directories.

## Architecture

Layered design — each layer depends only on layers below it:

1. **`api/overpass`** — fetches raw OSM JSON, parses into DTOs
2. **`mapping`** — converts OSM DTOs → internal `graph.Network`
3. **`graph`** — directed graph with adjacency list; nodes keyed by `int64` NodeID
4. **`geo`** — geographic primitives (coordinates, bounding boxes, Haversine distance)
5. **`routefinding`** — path-finding algorithms operating on `graph.Network`
6. **`services`** — orchestrates the full pipeline (load network, find route, return results)

## Conventions
- Test packages use `_test` suffix (e.g., `package overpass_test`)
- External test packages live in a `tests/` subdirectory (e.g., `geo/tests/`, `services/tests/`)
- Errors wrapped with context: `fmt.Errorf("read file %q: %w", path, err)`
- Helper functions in tests prefixed `must` (e.g., `mustAddNode`, `mustAddEdge`)
- Maps for O(1) lookups; adjacency list for graph traversal
- All source files formatted with `gofmt`

## Current State

| Component | Status |
|-----------|--------|
| Graph core (`graph/`) | Complete — 2 passing tests |
| OSM API client (`api/overpass/`) | Complete — 1 passing test |
| Data mapping (`mapping/`) | Complete — 1 passing test |
| Geo utilities (`geo/`) | Complete — 6 passing tests |
| Dijkstra algorithm (`routefinding/dijkstra.go`) | Complete — 5 passing tests |
| A* algorithm (`routefinding/astar.go`) | Complete — 5 passing tests |
| Router interface (`routefinding/router.go`) | Complete — `DijkstraRouter` and `AStarRouter` wrappers |
| Service layer (`services/`) | Complete — 8 passing tests |
| `main.go` | Complete — flag-based CLI (`-data`, `-start`, `-end`, `-algo`) |
| Frontend | Empty |

All 28 tests pass across 6 packages (`go test ./...`).
