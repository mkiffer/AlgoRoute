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
	"strings"
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

func TestHandleRoute_ValidRequest_ReturnsVisitedNodes(t *testing.T) {
	// visited_nodes must be present and non-empty so the frontend can animate
	// the traversal. Each entry must have lat and lon fields.
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
		t.Fatalf("response is not valid JSON: %v", err)
	}

	visitedRaw, ok := response["visited_nodes"].([]interface{})
	if !ok || len(visitedRaw) == 0 {
		t.Fatalf(
			"expected non-empty 'visited_nodes' array in response, got %v",
			response["visited_nodes"],
		)
	}

	// Every entry must carry lat and lon so the frontend can place circle markers.
	for i, entry := range visitedRaw {
		node, ok := entry.(map[string]interface{})
		if !ok {
			t.Errorf("visited_nodes[%d] is not an object: %v", i, entry)
			continue
		}
		if _, hasLat := node["lat"]; !hasLat {
			t.Errorf("visited_nodes[%d] missing 'lat' field", i)
		}
		if _, hasLon := node["lon"]; !hasLon {
			t.Errorf("visited_nodes[%d] missing 'lon' field", i)
		}
	}
}

func TestHandleRoute_OversizedBody_Returns400WithTooLargeError(t *testing.T) {
	// Without a body-size cap, a malicious client can send an arbitrarily large
	// JSON payload to exhaust server memory (denial-of-service). The handler must
	// reject bodies that exceed 1 MB and report a human-readable error.
	//
	// A valid JSON body (rather than garbage) is used here so that — before the
	// fix — the decoder would succeed and proceed to geocoding (returning 500),
	// making the test correctly RED before MaxBytesReader is applied.
	srv := server.NewWithOptions(server.Options{StaticDir: "."})

	// Build a valid JSON object whose "origin" value inflates the body past 1 MB.
	const limitBytes = 1 << 20 // 1 MB
	origin := strings.Repeat("x", limitBytes)
	bodyStr := `{"origin":"` + origin + `","destination":"b","algorithm":"dijkstra"}`

	req := httptest.NewRequest(http.MethodPost, "/api/route", strings.NewReader(bodyStr))
	req.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusBadRequest {
		t.Errorf(
			"POST /api/route with %d-byte body: got status %d, want 400 — "+
				"oversized bodies must be rejected before geocoding is attempted",
			len(bodyStr), recorder.Code,
		)
	}

	var errResp map[string]string
	if err := json.Unmarshal(recorder.Body.Bytes(), &errResp); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if !strings.Contains(errResp["error"], "too large") {
		t.Errorf(
			"POST /api/route oversized body: error message = %q, want it to contain \"too large\" — "+
				"the client must know the body was rejected for size, not a JSON parse error",
			errResp["error"],
		)
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

func TestCORS_RegularRequest_HasCORSHeaders(t *testing.T) {
	// Every API response must include CORS headers so browsers allow cross-origin
	// requests. Without these headers the frontend (served on a different port
	// in dev) cannot read the response.
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

	allowOrigin := recorder.Header().Get("Access-Control-Allow-Origin")
	if allowOrigin != "*" {
		t.Errorf(
			"POST /api/route: Access-Control-Allow-Origin = %q, want \"*\"",
			allowOrigin,
		)
	}
	allowMethods := recorder.Header().Get("Access-Control-Allow-Methods")
	if !strings.Contains(allowMethods, "POST") {
		t.Errorf(
			"POST /api/route: Access-Control-Allow-Methods = %q, want it to contain \"POST\"",
			allowMethods,
		)
	}
	allowHeaders := recorder.Header().Get("Access-Control-Allow-Headers")
	if !strings.Contains(allowHeaders, "Content-Type") {
		t.Errorf(
			"POST /api/route: Access-Control-Allow-Headers = %q, want it to contain \"Content-Type\"",
			allowHeaders,
		)
	}
}

func TestCORS_PreflightRequest_Returns204WithCORSHeaders(t *testing.T) {
	// Browsers send an OPTIONS preflight before cross-origin POST requests.
	// The server must respond 204 with CORS headers — without this the browser
	// blocks the actual request before it is sent.
	srv := server.NewWithOptions(server.Options{StaticDir: "."})

	req := httptest.NewRequest(http.MethodOptions, "/api/route", nil)
	recorder := httptest.NewRecorder()

	srv.ServeHTTP(recorder, req)

	if recorder.Code != http.StatusNoContent {
		t.Errorf(
			"OPTIONS /api/route: got status %d, want 204 — preflight must be answered immediately",
			recorder.Code,
		)
	}
	allowOrigin := recorder.Header().Get("Access-Control-Allow-Origin")
	if allowOrigin != "*" {
		t.Errorf(
			"OPTIONS /api/route: Access-Control-Allow-Origin = %q, want \"*\"",
			allowOrigin,
		)
	}
	allowMethods := recorder.Header().Get("Access-Control-Allow-Methods")
	if !strings.Contains(allowMethods, "POST") {
		t.Errorf(
			"OPTIONS /api/route: Access-Control-Allow-Methods = %q, want it to contain \"POST\"",
			allowMethods,
		)
	}
	allowHeaders := recorder.Header().Get("Access-Control-Allow-Headers")
	if !strings.Contains(allowHeaders, "Content-Type") {
		t.Errorf(
			"OPTIONS /api/route: Access-Control-Allow-Headers = %q, want it to contain \"Content-Type\"",
			allowHeaders,
		)
	}
}
