/*
Tests for: geo/bbox_helpers.go — BBoxFromCoords utility.
Coverage intent: the padded bounding box contains both input points and applies
padding symmetrically in all four directions.
Not covered here: BBox.Contains (see geo_test.go).
*/
package geo_test

import (
	"testing"

	"algoroute/geo"
)

func TestBBoxFromCoords_ContainsBothInputPoints(t *testing.T) {
	// Both geocoded coordinates must lie inside the bounding box so that the
	// Overpass query actually covers the origin and destination nodes.
	a := geo.Coord{Lat: -37.81, Lon: 144.96}
	b := geo.Coord{Lat: -37.85, Lon: 145.01}

	bbox := geo.BBoxFromCoords(a, b, 0.01)

	if !bbox.Contains(a) {
		t.Errorf(
			"BBoxFromCoords: expected bbox to contain point a %+v, got bbox %+v",
			a, bbox,
		)
	}
	if !bbox.Contains(b) {
		t.Errorf(
			"BBoxFromCoords: expected bbox to contain point b %+v, got bbox %+v",
			b, bbox,
		)
	}
}

func TestBBoxFromCoords_PaddingExpandsBeyondBothPoints(t *testing.T) {
	// The padding must push each edge outward so that roads near the geocoded
	// coordinates (but not exactly at them) are included in the Overpass fetch.
	a := geo.Coord{Lat: -37.81, Lon: 144.96}
	b := geo.Coord{Lat: -37.85, Lon: 145.01}
	const padding = 0.01

	bbox := geo.BBoxFromCoords(a, b, padding)

	// MinLat must be strictly south of the southernmost point.
	if bbox.MinLat >= -37.85 {
		t.Errorf(
			"BBoxFromCoords: MinLat %.6f should be less than southernmost lat -37.85 (padding not applied south)",
			bbox.MinLat,
		)
	}
	// MaxLat must be strictly north of the northernmost point.
	if bbox.MaxLat <= -37.81 {
		t.Errorf(
			"BBoxFromCoords: MaxLat %.6f should be greater than northernmost lat -37.81 (padding not applied north)",
			bbox.MaxLat,
		)
	}
	// MinLon must be strictly west of the westernmost point.
	if bbox.MinLon >= 144.96 {
		t.Errorf(
			"BBoxFromCoords: MinLon %.6f should be less than westernmost lon 144.96 (padding not applied west)",
			bbox.MinLon,
		)
	}
	// MaxLon must be strictly east of the easternmost point.
	if bbox.MaxLon <= 145.01 {
		t.Errorf(
			"BBoxFromCoords: MaxLon %.6f should be greater than easternmost lon 145.01 (padding not applied east)",
			bbox.MaxLon,
		)
	}
}

func TestBBoxApproxAreaKm2_OneByOneDegreeAtEquator(t *testing.T) {
	// At the equator 1° lat ≈ 111.32 km and 1° lon ≈ 111.32 km (cos(0)=1),
	// so a 1°×1° box should be approximately 111.32² ≈ 12,392 km².
	box := geo.BBox{MinLat: 0, MaxLat: 1, MinLon: 0, MaxLon: 1}
	const wantKm2 = 12_392.0
	const tolerance = 100.0 // ~0.8% — accounts for approximation

	area := box.ApproxAreaKm2()

	if area < wantKm2-tolerance || area > wantKm2+tolerance {
		t.Errorf("ApproxAreaKm2 equator 1°×1°: got %.1f km², want %.1f ±%.0f", area, wantKm2, tolerance)
	}
}

func TestBBoxApproxAreaKm2_MelbourneToGeelong_LargeArea(t *testing.T) {
	// Melbourne (-37.81, 144.96) to Geelong (-38.15, 144.36) with 0.01 padding.
	// Lat span: 0.35°, Lon span: 0.61° → area ≈ 0.35*111.32 * 0.61*111.32*cos(-37.98°) ≈ 1,840 km².
	box := geo.BBoxFromCoords(
		geo.Coord{Lat: -37.81, Lon: 144.96},
		geo.Coord{Lat: -38.15, Lon: 144.36},
		0.01,
	)

	area := box.ApproxAreaKm2()

	if area < 1500 {
		t.Errorf("ApproxAreaKm2 Melbourne→Geelong: got %.1f km², expected > 1500", area)
	}
	if area > 2500 {
		t.Errorf("ApproxAreaKm2 Melbourne→Geelong: got %.1f km², expected < 2500", area)
	}
}

func TestBBoxApproxAreaKm2_TinyBox_NearZero(t *testing.T) {
	// A very small box (< 0.001° per side) should produce near-zero area.
	box := geo.BBox{MinLat: -37.810, MaxLat: -37.809, MinLon: 144.960, MaxLon: 144.961}

	area := box.ApproxAreaKm2()

	if area > 0.02 {
		t.Errorf("ApproxAreaKm2 tiny box: got %.4f km², expected < 0.02", area)
	}
}

func TestBBoxFromCoords_ZeroPadding_ExactBoundsOfInputPoints(t *testing.T) {
	// With zero padding the bbox edges must equal the coordinates of the two
	// input points exactly — no implicit expansion.
	a := geo.Coord{Lat: -37.81, Lon: 144.96}
	b := geo.Coord{Lat: -37.85, Lon: 145.01}

	bbox := geo.BBoxFromCoords(a, b, 0)

	if bbox.MinLat != -37.85 {
		t.Errorf("BBoxFromCoords(padding=0): MinLat got %.6f, want -37.85", bbox.MinLat)
	}
	if bbox.MaxLat != -37.81 {
		t.Errorf("BBoxFromCoords(padding=0): MaxLat got %.6f, want -37.81", bbox.MaxLat)
	}
	if bbox.MinLon != 144.96 {
		t.Errorf("BBoxFromCoords(padding=0): MinLon got %.6f, want 144.96", bbox.MinLon)
	}
	if bbox.MaxLon != 145.01 {
		t.Errorf("BBoxFromCoords(padding=0): MaxLon got %.6f, want 145.01", bbox.MaxLon)
	}
}
