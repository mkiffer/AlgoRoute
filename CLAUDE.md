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
