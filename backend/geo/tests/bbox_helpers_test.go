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
