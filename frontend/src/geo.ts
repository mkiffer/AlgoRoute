// geo.ts — geographic utility functions used by the frontend.
// Mirrors the Go backend's geo package for distance calculations that must
// be performed client-side (e.g. validating click distance before routing).

import type { Coord } from './types';

// haversineMeters returns the great-circle distance between two coordinates
// in metres. Mirrors geo.DistanceMeters in the Go backend so that the
// frontend radius check uses the same formula as the backend bbox guard.
export function haversineMeters(a: Coord, b: Coord): number {
  const R = 6_371_000; // Earth radius in metres
  const toRad = (deg: number) => (deg * Math.PI) / 180;

  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);

  const sinDLat = Math.sin(dLat / 2);
  const sinDLon = Math.sin(dLon / 2);

  const chord =
    sinDLat * sinDLat +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinDLon * sinDLon;

  return 2 * R * Math.asin(Math.sqrt(chord));
}
