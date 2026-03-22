// api.ts — typed wrappers around the AlgoRoute backend REST API.
// All network I/O lives here. No other module calls fetch() directly.

import type { RouteResponse, SuggestResult, Algorithm, ReverseGeocodeResponse } from './types';

export interface RouteRequest {
  origin: string;
  destination: string;
  algorithm: Algorithm;
}

// fetchRoute sends a route request to POST /api/route and returns a typed
// RouteResponse. Throws an Error with the backend's error message on failure.
export async function fetchRoute(req: RouteRequest): Promise<RouteResponse> {
  const response = await fetch('/api/route', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req),
  });

  const data = await response.json() as { error?: string } & RouteResponse;

  if (!response.ok || data.error) {
    throw new Error(data.error ?? response.statusText);
  }

  return data;
}

// fetchSuggestions fetches address autocomplete results from GET /api/suggest.
// Returns an empty array on any failure — suggestions are non-critical.
export async function fetchSuggestions(query: string): Promise<SuggestResult[]> {
  try {
    const response = await fetch('/api/suggest?q=' + encodeURIComponent(query));
    if (!response.ok) return [];
    return response.json() as Promise<SuggestResult[]>;
  } catch {
    return [];
  }
}

// fetchReverseGeocode converts a coordinate into a human-readable address by
// calling GET /api/reverse. Returns "" on any failure — the pin is still
// placed and the user can type an address manually.
export async function fetchReverseGeocode(lat: number, lon: number): Promise<string> {
  try {
    const url = '/api/reverse?lat=' + encodeURIComponent(lat) + '&lon=' + encodeURIComponent(lon);
    const response = await fetch(url);
    if (!response.ok) return '';
    const data = await response.json() as ReverseGeocodeResponse;
    return data.address;
  } catch {
    return '';
  }
}
