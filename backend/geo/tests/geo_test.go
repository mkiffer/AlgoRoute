/*
Tests for: geo — geographic primitives.
Coverage intent: DistanceMeters (Haversine formula), BBox.Contains.
Not covered here: Coord struct (data-only, no behaviour to test).
*/
package geo_test

import (
	"math"
	"testing"

	"algoroute/geo"
)

// --- DistanceMeters ---

func TestDistanceMeters_SamePoint_ReturnsZero(t *testing.T) {
	// The zero-distance case confirms the formula has no constant offset.
	point := geo.Coord{Lat: -37.81, Lon: 144.96}

	distance := geo.DistanceMeters(point, point)

	if distance != 0 {
		t.Errorf("DistanceMeters(p, p): got %.6fm, want 0", distance)
	}
}

func TestDistanceMeters_OneDegreeLongitudeAtEquator_MatchesKnownValue(t *testing.T) {
	// One degree of longitude at the equator is exactly 2π·R/360 ≈ 111,195 m
	// (where R = 6,371,000 m). The equator simplifies the formula to isolate
	// the longitude term (cos(lat) = 1), making this a clean regression check
	// against a known ground-truth value.
	const wantMeters = 111_195.0
	const toleranceMeters = 1.0

	a := geo.Coord{Lat: 0, Lon: 0}
	b := geo.Coord{Lat: 0, Lon: 1}

	distance := geo.DistanceMeters(a, b)

	if math.Abs(distance-wantMeters) > toleranceMeters {
		t.Errorf(
			"DistanceMeters equator 1°: got %.2fm, want %.2fm ±%.1fm",
			distance, wantMeters, toleranceMeters,
		)
	}
}

func TestDistanceMeters_IsSymmetric(t *testing.T) {
	// d(a,b) must equal d(b,a): symmetry is a required property of any
	// distance metric. An asymmetric result would indicate a sign error in
	// one of the delta terms.
	a := geo.Coord{Lat: -37.81, Lon: 144.96}
	b := geo.Coord{Lat: -37.82, Lon: 144.97}

	distAB := geo.DistanceMeters(a, b)
	distBA := geo.DistanceMeters(b, a)

	if distAB != distBA {
		t.Errorf(
			"DistanceMeters not symmetric: d(a,b)=%.6fm, d(b,a)=%.6fm",
			distAB, distBA,
		)
	}
}

// --- BBox.Contains ---

func TestBBoxContains_PointInsideBounds_ReturnsTrue(t *testing.T) {
	box := geo.BBox{MinLat: -38.0, MaxLat: -37.0, MinLon: 144.0, MaxLon: 145.0}
	inside := geo.Coord{Lat: -37.5, Lon: 144.5}

	if !box.Contains(inside) {
		t.Errorf("BBox.Contains: expected true for point inside bounds, got false")
	}
}

func TestBBoxContains_PointOutsideBounds_ReturnsFalse(t *testing.T) {
	box := geo.BBox{MinLat: -38.0, MaxLat: -37.0, MinLon: 144.0, MaxLon: 145.0}
	outside := geo.Coord{Lat: -39.0, Lon: 144.5}

	if box.Contains(outside) {
		t.Errorf("BBox.Contains: expected false for point south of MinLat, got true")
	}
}

func TestBBoxContains_PointOnBoundary_ReturnsTrue(t *testing.T) {
	// Boundary is inclusive: a point exactly on an edge is inside the box.
	// This matches the >= / <= comparisons in BBox.Contains.
	box := geo.BBox{MinLat: -38.0, MaxLat: -37.0, MinLon: 144.0, MaxLon: 145.0}
	onCorner := geo.Coord{Lat: -38.0, Lon: 144.0}

	if !box.Contains(onCorner) {
		t.Errorf("BBox.Contains: expected true for point on boundary corner, got false")
	}
}
