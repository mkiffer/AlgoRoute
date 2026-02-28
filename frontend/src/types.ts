// types.ts — TypeScript interfaces that mirror the Go backend JSON shapes.
// These are the single source of truth for the API contract between
// frontend/src/api.ts and backend/server/handlers.go. Any backend struct
// change (routeResponse, pathNode, coordJSON, SuggestResult) must be
// reflected here so the TypeScript compiler catches mismatches at build time.

// RouteResponse mirrors routeResponse in backend/server/handlers.go.
export interface RouteResponse {
  algorithm: string;
  distance_meters: number;
  path: PathNode[];
  visited_nodes: Coord[];
  origin_coord: Coord;
  destination_coord: Coord;
}

// PathNode mirrors pathNode in backend/server/handlers.go.
export interface PathNode {
  node_id: number;
  lat: number;
  lon: number;
}

// Coord mirrors coordJSON in backend/server/handlers.go.
export interface Coord {
  lat: number;
  lon: number;
}

// SuggestResult mirrors geo.SuggestResult in backend/geo/suggest.go.
export interface SuggestResult {
  display_name: string;
  lat: number;
  lon: number;
}

// Algorithm is the set of routing algorithm identifiers the backend accepts.
export type Algorithm = 'dijkstra' | 'astar';

// AnimationSpeed maps to the keys in SPEED_CONFIG.
export type AnimationSpeed = 'slow' | 'medium' | 'fast';
