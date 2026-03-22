/*
Tests for: geo/reverse.go — coordinate-to-address conversion via Nominatim.
Coverage intent: URL construction (unit-testable without HTTP), happy-path
response parsing, non-OK HTTP status propagation, and missing display_name.
Live Nominatim calls are not made in tests.
*/
package geo_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"algoroute/geo"
)

func TestReverseGeocodeURL_ContainsRequiredQueryParameters(t *testing.T) {
	// The URL sent to Nominatim must include format=json, lat=, and lon= so the
	// API knows how to format the response and which point to reverse-geocode.
	coord := geo.Coord{Lat: -37.8136, Lon: 144.9631}

	rawURL := geo.ReverseGeocodeURL(coord)

	if !strings.Contains(rawURL, "format=json") {
		t.Errorf(
			"ReverseGeocodeURL: missing 'format=json' in URL %q — Nominatim requires this to return JSON",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "lat=") {
		t.Errorf(
			"ReverseGeocodeURL: missing 'lat=' in URL %q — Nominatim requires the latitude parameter",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "lon=") {
		t.Errorf(
			"ReverseGeocodeURL: missing 'lon=' in URL %q — Nominatim requires the longitude parameter",
			rawURL,
		)
	}
}

func TestReverseGeocode_ParsesDisplayNameFromNominatimResponse(t *testing.T) {
	// Verifies that ReverseGeocodeWithBaseURL correctly extracts display_name
	// from a well-formed Nominatim reverse geocoding response.
	fakeResult := map[string]string{
		"display_name": "Test Street, Melbourne, Australia",
	}
	responseBody, _ := json.Marshal(fakeResult)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(responseBody)
	}))
	defer server.Close()

	address, err := geo.ReverseGeocodeWithBaseURL(geo.Coord{Lat: -37.8136, Lon: 144.9631}, server.URL)

	if err != nil {
		t.Fatalf("ReverseGeocodeWithBaseURL: unexpected error: %v", err)
	}
	if address != "Test Street, Melbourne, Australia" {
		t.Errorf(
			"ReverseGeocodeWithBaseURL: got %q, want %q",
			address, "Test Street, Melbourne, Australia",
		)
	}
}

func TestReverseGeocode_ReturnsErrorOnNonOKHTTPStatus(t *testing.T) {
	// A non-200 response from Nominatim must surface as an error rather than
	// returning an empty address that would silently mislabel a pin.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	_, err := geo.ReverseGeocodeWithBaseURL(geo.Coord{Lat: -37.8136, Lon: 144.9631}, server.URL)

	if err == nil {
		t.Errorf(
			"ReverseGeocodeWithBaseURL: expected an error for a 503 response, got nil",
		)
	}
}

func TestReverseGeocode_ReturnsErrorWhenDisplayNameMissing(t *testing.T) {
	// A Nominatim response with no display_name field must return an error so
	// the caller can decide whether to show a fallback rather than an empty label.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{}`))
	}))
	defer server.Close()

	_, err := geo.ReverseGeocodeWithBaseURL(geo.Coord{Lat: -37.8136, Lon: 144.9631}, server.URL)

	if err == nil {
		t.Errorf(
			"ReverseGeocodeWithBaseURL: expected an error when display_name is missing, got nil",
		)
	}
}
