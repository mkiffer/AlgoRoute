/*
Tests for: geo/suggest.go — address autocomplete suggestions via Nominatim.
Coverage intent: URL construction, happy-path response parsing, empty results,
non-200 HTTP errors, and skipping of results with malformed coordinates.
Not covered here: network timeouts (require infrastructure beyond stdlib httptest).
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

func TestSuggestURL_ContainsRequiredQueryParameters(t *testing.T) {
	// The URL sent to Nominatim must include the query, JSON format, and a
	// limit of 5 so the dropdown never shows more than 5 options.
	// Mirrors TestNominatimURL_ContainsRequiredQueryParameters in geocode_test.go.
	query := "Chapel St"

	rawURL := geo.SuggestURL(query)

	if !strings.Contains(rawURL, "format=json") {
		t.Errorf(
			"SuggestURL: missing 'format=json' in URL %q — Nominatim requires this to return JSON",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "limit=5") {
		t.Errorf(
			"SuggestURL: missing 'limit=5' in URL %q — autocomplete dropdown must show at most 5 results",
			rawURL,
		)
	}
	if !strings.Contains(rawURL, "Chapel") {
		t.Errorf(
			"SuggestURL: query string not present in URL %q — address must be included for Nominatim to search",
			rawURL,
		)
	}
}

func TestSuggestWithBaseURL_ParsesSuggestionsFromNominatimResponse(t *testing.T) {
	// Verifies the happy path: a well-formed Nominatim response is parsed into
	// SuggestResult values with correct DisplayName, Lat, and Lon.
	fakeHits := []map[string]string{
		{
			"display_name": "Chapel Street, South Yarra, Melbourne",
			"lat":          "-37.8410",
			"lon":          "144.9890",
		},
		{
			"display_name": "Chapel Street, Prahran, Melbourne",
			"lat":          "-37.8510",
			"lon":          "144.9940",
		},
	}
	responseBody, _ := json.Marshal(fakeHits)

	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(responseBody)
	}))
	defer stub.Close()

	// Act
	suggestions, err := geo.SuggestWithBaseURL("Chapel St", stub.URL)

	// Assert
	if err != nil {
		t.Fatalf("SuggestWithBaseURL: unexpected error for valid response: %v", err)
	}
	if len(suggestions) != 2 {
		t.Fatalf(
			"SuggestWithBaseURL: got %d suggestions, want 2 — both results should be parsed",
			len(suggestions),
		)
	}
	if suggestions[0].DisplayName != "Chapel Street, South Yarra, Melbourne" {
		t.Errorf(
			"SuggestWithBaseURL: suggestions[0].DisplayName = %q, want %q",
			suggestions[0].DisplayName, "Chapel Street, South Yarra, Melbourne",
		)
	}
	if suggestions[0].Lat != -37.8410 {
		t.Errorf(
			"SuggestWithBaseURL: suggestions[0].Lat = %.4f, want -37.8410",
			suggestions[0].Lat,
		)
	}
	if suggestions[0].Lon != 144.9890 {
		t.Errorf(
			"SuggestWithBaseURL: suggestions[0].Lon = %.4f, want 144.9890",
			suggestions[0].Lon,
		)
	}
}

func TestSuggestWithBaseURL_ReturnsEmptySliceForEmptyNominatimResponse(t *testing.T) {
	// Nominatim returns [] when no addresses match the query.
	// Suggest must return an empty (non-nil) slice, not an error — the frontend
	// treats an empty array as "show no dropdown", not as a failure.
	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[]`))
	}))
	defer stub.Close()

	// Act
	suggestions, err := geo.SuggestWithBaseURL("zzz no such place", stub.URL)

	// Assert
	if err != nil {
		t.Errorf(
			"SuggestWithBaseURL: expected no error for empty Nominatim response, got %v — "+
				"zero results is a valid outcome, not an error",
			err,
		)
	}
	if len(suggestions) != 0 {
		t.Errorf(
			"SuggestWithBaseURL: got %d suggestions for an empty Nominatim response, want 0",
			len(suggestions),
		)
	}
}

func TestSuggestWithBaseURL_ReturnsErrorOnNonOKHTTPStatus(t *testing.T) {
	// A non-200 status from Nominatim (e.g. rate limiting, server error) must
	// be surfaced as an error so the caller can degrade gracefully rather than
	// silently parsing an error body as if it were a result list.
	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer stub.Close()

	// Act
	_, err := geo.SuggestWithBaseURL("Chapel St", stub.URL)

	// Assert
	if err == nil {
		t.Errorf(
			"SuggestWithBaseURL: expected an error for HTTP 429 response, got nil — "+
				"non-OK status codes must not be silently ignored",
		)
	}
}

func TestSuggestWithBaseURL_SkipsResultsWithMalformedCoordinates(t *testing.T) {
	// If Nominatim returns a result with an unparseable lat or lon, that result
	// must be silently skipped. A single malformed entry must not fail the whole
	// request — the remaining valid suggestions must still be returned.
	fakeHits := []map[string]string{
		{"display_name": "Good Place", "lat": "-37.84", "lon": "144.98"},
		{"display_name": "Bad Place", "lat": "not-a-number", "lon": "144.98"},
	}
	responseBody, _ := json.Marshal(fakeHits)

	stub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(responseBody)
	}))
	defer stub.Close()

	// Act
	suggestions, err := geo.SuggestWithBaseURL("test", stub.URL)

	// Assert
	if err != nil {
		t.Fatalf("SuggestWithBaseURL: unexpected error when one result has malformed coords: %v", err)
	}
	if len(suggestions) != 1 {
		t.Errorf(
			"SuggestWithBaseURL: got %d suggestions, want 1 — "+
				"the malformed result should be skipped, not the valid one",
			len(suggestions),
		)
	}
	if len(suggestions) == 1 && suggestions[0].DisplayName != "Good Place" {
		t.Errorf(
			"SuggestWithBaseURL: got DisplayName %q, want \"Good Place\" — wrong result was kept",
			suggestions[0].DisplayName,
		)
	}
}
