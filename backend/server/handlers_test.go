/*
Tests for: server/handlers.go — POST /api/route HTTP handler.
Coverage intent: valid request produces a 200 with path and distance, missing
fields produce a 400, and an unroutable request produces a 500 with an error
body. Uses httptest to call the handler directly — no live external calls.

The handler under test itself calls RouteByAddress, so both geocoding and
Overpass are stubbed via the GeocoderBaseURL/OverpassBaseURL fields on
AddressRouteRequest. Because handleRoute constructs the request internally, the
handler must be wired to accept override URLs for testing; those are injected
via ServerOptions.
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
