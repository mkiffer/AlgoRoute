/*
Tests for: geo/geocode.go — address-to-coordinate conversion via Nominatim.
Coverage intent: URL construction (unit-testable without HTTP), and response
parsing via an httptest server. Live Nominatim calls are not made in tests.
Not covered here: network timeouts (require test infrastructure beyond stdlib httptest).
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

func TestNominatimURL_ContainsRequiredQueryParameters(t *testing.T) {
	// The URL sent to Nominatim must include the address query, JSON format,
	// and result limit so the API returns exactly one parseable result.
	address := "Chapel St, South Yarra"

	rawURL := geo.NominatimURL(address)

	if !strings.Contains(rawURL, "format=json") {
		t.Errorf(
			"NominatimURL: missing 'format=json' in URL %q — Nominatim requires this to return JSON",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "limit=1") {
		t.Errorf(
			"NominatimURL: missing 'limit=1' in URL %q — without a limit the response may contain many results",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "Chapel") {
		t.Errorf(
			"NominatimURL: address not present in URL %q — the query string must include the address",
			rawURL,
		)
	}
}

func TestGeocode_ParsesLatLonFromNominatimResponse(t *testing.T) {
	// Verifies that Geocode correctly extracts lat/lon from a well-formed
	// Nominatim JSON response. Uses an httptest server to avoid live HTTP calls.
	fakeResult := []map[string]string{
		{"lat": "-37.8410", "lon": "144.9890"},
	}
	responseBody, _ := json.Marshal(fakeResult)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(responseBody)
	}))
	defer server.Close()

	// Act
	coord, err := geo.GeocodeWithBaseURL("Chapel St, South Yarra", server.URL)

	// Assert
	if err != nil {
		t.Fatalf("GeocodeWithBaseURL: unexpected error: %v", err)
	}
	if coord.Lat != -37.8410 {
		t.Errorf("GeocodeWithBaseURL: Lat got %.4f, want -37.8410", coord.Lat)
	}
	if coord.Lon != 144.9890 {
		t.Errorf("GeocodeWithBaseURL: Lon got %.4f, want 144.9890", coord.Lon)
	}
}

func TestGeocode_ReturnsErrorWhenNoResults(t *testing.T) {
	// Nominatim returns an empty array when an address is not recognised.
	// Geocode must surface this as an error rather than returning a zero Coord,
	// which would silently snap to a node near (0,0) — the Gulf of Guinea.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[]`))
	}))
	defer server.Close()

	// Act
	_, err := geo.GeocodeWithBaseURL("zzz not a real address", server.URL)

	// Assert
	if err == nil {
		t.Errorf(
			"GeocodeWithBaseURL: expected an error for an address with no results, got nil",
		)
	}
}
