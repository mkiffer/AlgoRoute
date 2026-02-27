/*
Tests for: server/handlers.go — HTTP handlers for POST /api/route and GET /api/suggest.
Coverage intent:
  - /api/route: valid request → 200 with path and distance; missing fields → 400;
    invalid JSON → 400.
  - /api/suggest: empty query → 200 with []; valid query → 200 with parsed suggestions;
    Nominatim failure → 200 with [] (graceful degradation).

Uses httptest to call handlers directly — no live external calls.
Geocoding and Overpass are stubbed via URL override fields on server.Options.
*/
package server_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"algoroute/server"
)

// nominatimStubHandler returns a minimal Nominatim JSON response for the
// given coordinates. The returned handler serves the same coordinate for
// any address query (sufficient for handler-level tests).
func nominatimStubHandler(lat, lon string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		result := []map[string]string{{"lat": lat, "lon": lon}}
		body, _ := json.Marshal(result)
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	}
}

// overpassStubHandler returns the sample_overpass.json fixture as if it were
// a live Overpass API response.
func overpassStubHandler(t *testing.T) http.HandlerFunc {
	t.Helper()
	// Navigate up two directories: server/tests → backend → services/tests/testdata
	fixtureData, err := os.ReadFile("../services/tests/testdata/sample_overpass.json")
	if err != nil {
		t.Fatalf("overpassStubHandler: could not read fixture: %v", err)
	}
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixtureData)
	}
}

func TestHandleRoute_ValidRequest_Returns200WithPathAndDistance(t *testing.T) {
	// Verifies that a well-formed POST /api/route request produces a 200
	// response containing a non-empty path and a positive distance.
	originStub := httptest.NewServer(nominatimStubHandler("-37.809", "144.959"))
	defer originStub.Close()
	destStub := httptest.NewServer(nominatimStubHandler("-37.831", "144.981"))
	defer destStub.Close()
	overpassStub := httptest.NewServer(overpassStubHandler(t))
	defer overpassStub.Close()

	srv := server.NewWithOptions(server.Options{
		StaticDir:           ".",
		GeocoderBaseURL:     originStub.URL,
		DestGeocoderBaseURL: destStub.URL,
		OverpassBaseURL:     overpassStub.URL,
	})

	body, _ := json.Marshal(map[string]string{
		"origin":      "near node 1001",
		"destination": "near node 1003",
		"algorithm":   "dijkstra",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/route", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf(
			"POST /api/route: got status %d, want 200. Body: %s",
			recorder.Code, recorder.Body.String(),
		)
	}

	var response map[string]interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &response); err != nil {
		t.Fatalf("POST /api/route: response is not valid JSON: %v", err)
	}
	path, ok := response["path"].([]interface{})
	if !ok || len(path) == 0 {
		t.Errorf("POST /api/route: expected non-empty 'path' array in response, got %v", response["path"])
	}
	distance, ok := response["distance_meters"].(float64)
	if !ok || distance <= 0 {
		t.Errorf(
			"POST /api/route: expected positive 'distance_meters', got %v",
			response["distance_meters"],
		)
	}
}

func TestHandleRoute_MissingOrigin_Returns400(t *testing.T) {
	// A request without an origin must be rejected with 400 before any
	// external calls are made — no geocoding or Overpass fetch should occur.
	srv := server.NewWithOptions(server.Options{StaticDir: "."})

	body, _ := json.Marshal(map[string]string{
		"destination": "Chapel St, South Yarra",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/route", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf(
			"POST /api/route missing origin: got status %d, want 400",
			recorder.Code,
		)
	}

	var errResponse map[string]string
	json.Unmarshal(recorder.Body.Bytes(), &errResponse)
	if errResponse["error"] == "" {
		t.Errorf(
			"POST /api/route missing origin: expected 'error' field in response body, got %v",
			errResponse,
		)
	}
}

func TestHandleRoute_InvalidJSON_Returns400(t *testing.T) {
	// Malformed request bodies must return 400, not 500, so the client knows
	// the error is on its side and can correct the request.
	srv := server.NewWithOptions(server.Options{StaticDir: "."})

	req := httptest.NewRequest(http.MethodPost, "/api/route", bytes.NewReader([]byte(`not json`)))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf(
			"POST /api/route with invalid JSON: got status %d, want 400",
			recorder.Code,
		)
	}
}

// nominatimSuggestStubHandler returns a Nominatim-shaped JSON response for
// address autocomplete — includes display_name in addition to lat/lon.
func nominatimSuggestStubHandler(results []map[string]string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, _ := json.Marshal(results)
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	}
}

func TestHandleSuggest_EmptyQuery_Returns200WithEmptyJSONArray(t *testing.T) {
	// A request with no ?q= parameter must return 200 with an empty JSON array,
	// not a 400 or 500 — the frontend calls suggest on every keypress and an
	// empty field must simply yield no results.
	srv := server.NewWithOptions(server.Options{StaticDir: "."})

	req := httptest.NewRequest(http.MethodGet, "/api/suggest", nil)
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf(
			"GET /api/suggest with no query: got status %d, want 200",
			recorder.Code,
		)
	}
	var suggestions []interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &suggestions); err != nil {
		t.Fatalf("GET /api/suggest: response is not valid JSON: %v", err)
	}
	if len(suggestions) != 0 {
		t.Errorf(
			"GET /api/suggest with no query: got %d suggestions, want 0 — empty query must return []",
			len(suggestions),
		)
	}
}

func TestHandleSuggest_ValidQuery_ReturnsParsedSuggestions(t *testing.T) {
	// A well-formed ?q= request must return the display_name, lat, and lon from
	// Nominatim. The server proxies the response so the frontend avoids CORS issues.
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
	suggestStub := httptest.NewServer(nominatimSuggestStubHandler(fakeHits))
	defer suggestStub.Close()

	srv := server.NewWithOptions(server.Options{
		StaticDir:      ".",
		SuggestBaseURL: suggestStub.URL,
	})

	req := httptest.NewRequest(http.MethodGet, "/api/suggest?q=Chapel+St", nil)
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf(
			"GET /api/suggest?q=Chapel+St: got status %d, want 200. Body: %s",
			recorder.Code, recorder.Body.String(),
		)
	}
	var suggestions []map[string]interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &suggestions); err != nil {
		t.Fatalf("GET /api/suggest: response is not valid JSON: %v", err)
	}
	if len(suggestions) != 2 {
		t.Fatalf(
			"GET /api/suggest: got %d suggestions, want 2 — both stub results should be returned",
			len(suggestions),
		)
	}
	if suggestions[0]["display_name"] != "Chapel Street, South Yarra, Melbourne" {
		t.Errorf(
			"GET /api/suggest: suggestions[0].display_name = %v, want %q",
			suggestions[0]["display_name"], "Chapel Street, South Yarra, Melbourne",
		)
	}
}

func TestHandleSuggest_NominatimFailure_Returns200WithEmptyJSONArray(t *testing.T) {
	// When Nominatim is unavailable or rate-limits the request, the handler must
	// return 200 [] rather than propagating the error. Suggestions are a UX
	// enhancement — a Nominatim outage must not break the route-finding flow.
	failingStub := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer failingStub.Close()

	srv := server.NewWithOptions(server.Options{
		StaticDir:      ".",
		SuggestBaseURL: failingStub.URL,
	})

	req := httptest.NewRequest(http.MethodGet, "/api/suggest?q=Chapel+St", nil)
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusOK {
		t.Fatalf(
			"GET /api/suggest with failing Nominatim: got status %d, want 200 — "+
				"suggestions must degrade gracefully, not return an error",
			recorder.Code,
		)
	}
	var suggestions []interface{}
	if err := json.Unmarshal(recorder.Body.Bytes(), &suggestions); err != nil {
		t.Fatalf("GET /api/suggest: response is not valid JSON: %v", err)
	}
	if len(suggestions) != 0 {
		t.Errorf(
			"GET /api/suggest with failing Nominatim: got %d suggestions, want 0",
			len(suggestions),
		)
	}
}
