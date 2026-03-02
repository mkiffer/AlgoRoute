/*
Tests for: services/address_routing.go — address-based routing orchestration.
Coverage intent: successful end-to-end pipeline using httptest servers for
Nominatim and Overpass (no live HTTP calls), geocoding failure propagation,
and missing road data detection.

Fixture network (from testdata/sample_overpass.json):
  Nodes: 1001 (-37.81, 144.96), 1002 (-37.82, 144.97), 1003 (-37.83, 144.98)
  Way 2001: 1001→1002→1003, highway=residential
*/
package services_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"

	"algoroute/mapping"
	"algoroute/services"
)

// nominatimHandler returns an http.HandlerFunc that serves a Nominatim-shaped
// response for a single coordinate.
func nominatimHandler(lat, lon string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		result := []map[string]string{{"lat": lat, "lon": lon}}
		body, _ := json.Marshal(result)
		w.Header().Set("Content-Type", "application/json")
		w.Write(body)
	}
}

// overpassFixtureHandler returns an http.HandlerFunc that serves the contents
// of testdata/sample_overpass.json as an Overpass API response.
func overpassFixtureHandler(t *testing.T) http.HandlerFunc {
	t.Helper()
	fixtureData, err := os.ReadFile("testdata/sample_overpass.json")
	if err != nil {
		t.Fatalf("overpassFixtureHandler: could not read fixture: %v", err)
	}
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixtureData)
	}
}

func TestRouteByAddress_FindsRouteUsingFakeServers(t *testing.T) {
	// Verifies the full address-to-route pipeline: geocode both addresses,
	// fetch the road network, snap to nearest nodes, and route between them.
	// Uses httptest servers to avoid any live external HTTP calls.
	//
	// Origin coord (-37.809, 144.959) snaps to node 1001 (-37.81, 144.96).
	// Destination coord (-37.831, 144.981) snaps to node 1003 (-37.83, 144.98).
	originServer := httptest.NewServer(nominatimHandler("-37.809", "144.959"))
	defer originServer.Close()

	destServer := httptest.NewServer(nominatimHandler("-37.831", "144.981"))
	defer destServer.Close()

	overpassServer := httptest.NewServer(overpassFixtureHandler(t))
	defer overpassServer.Close()

	routingService, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.AddressRouteRequest{
		Origin:           "near node 1001",
		Destination:      "near node 1003",
		Algorithm:        services.AlgorithmDijkstra,
		MapOpts:          mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:  originServer.URL,
		DestGeocoderBaseURL: destServer.URL,
		OverpassBaseURL:  overpassServer.URL,
	}

	result, err := routingService.RouteByAddress(request)

	if err != nil {
		t.Fatalf("RouteByAddress: unexpected error: %v", err)
	}
	if len(result.Path) == 0 {
		t.Errorf("RouteByAddress: expected a non-empty path, got []")
	}
	if result.DistanceMeters <= 0 {
		t.Errorf(
			"RouteByAddress: distance got %.2f, want > 0 — fixture nodes have real coordinates",
			result.DistanceMeters,
		)
	}
	if result.Algorithm != services.AlgorithmDijkstra {
		t.Errorf("RouteByAddress: algorithm got %q, want %q", result.Algorithm, services.AlgorithmDijkstra)
	}
	// OriginCoord must match the geocoded coordinate, not the snapped node.
	if result.OriginCoord.Lat != -37.809 {
		t.Errorf(
			"RouteByAddress: OriginCoord.Lat got %.3f, want -37.809 — "+
				"result must carry the geocoded coordinate, not the snapped node coordinate",
			result.OriginCoord.Lat,
		)
	}
}

func TestRouteByAddress_GeocodingFailure_PropagatesError(t *testing.T) {
	// If the origin cannot be geocoded (e.g. nonsense address), RouteByAddress
	// must return a descriptive error rather than silently routing from (0,0).
	emptyResultServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`[]`)) // Nominatim returns empty array for unknown addresses.
	}))
	defer emptyResultServer.Close()

	overpassServer := httptest.NewServer(overpassFixtureHandler(t))
	defer overpassServer.Close()

	routingService, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.AddressRouteRequest{
		Origin:           "zzz not a real address",
		Destination:      "somewhere",
		GeocoderBaseURL:  emptyResultServer.URL,
		DestGeocoderBaseURL: emptyResultServer.URL,
		OverpassBaseURL:  overpassServer.URL,
	}

	_, err := routingService.RouteByAddress(request)

	if err == nil {
		t.Errorf(
			"RouteByAddress with unresolvable address: expected an error, got nil",
		)
	}
}

func TestRouteByAddress_OversizedBBox_ReturnsError(t *testing.T) {
	// Melbourne (-37.81, 144.96) and Geelong (-38.15, 144.36) are ~75 km apart.
	// The resulting bounding box is ~1,800 km², far exceeding the 500 km² limit.
	// RouteByAddress must reject this before hitting the Overpass API to prevent
	// out-of-memory crashes from enormous responses.
	originServer := httptest.NewServer(nominatimHandler("-37.81", "144.96"))
	defer originServer.Close()

	destServer := httptest.NewServer(nominatimHandler("-38.15", "144.36"))
	defer destServer.Close()

	overpassServer := httptest.NewServer(overpassFixtureHandler(t))
	defer overpassServer.Close()

	routingService, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.AddressRouteRequest{
		Origin:              "Melbourne",
		Destination:         "Geelong",
		Algorithm:           services.AlgorithmDijkstra,
		MapOpts:             mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:     originServer.URL,
		DestGeocoderBaseURL: destServer.URL,
		OverpassBaseURL:     overpassServer.URL,
	}

	_, err := routingService.RouteByAddress(request)

	if err == nil {
		t.Fatal("RouteByAddress Melbourne→Geelong: expected area-too-large error, got nil")
	}
	if !strings.Contains(err.Error(), "too large") {
		t.Errorf("RouteByAddress: error should mention 'too large', got: %v", err)
	}
}

func TestRouteByAddress_NoRoadsInBbox_ReturnsError(t *testing.T) {
	// If the Overpass response contains no driveable ways (e.g. the two
	// addresses are in the ocean or in an area with no OSM road data), the
	// method must return a meaningful error instead of panicking or routing
	// through an empty graph.
	geocodeServer := httptest.NewServer(nominatimHandler("-37.81", "144.96"))
	defer geocodeServer.Close()

	emptyOverpassServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"version":0.6,"elements":[]}`))
	}))
	defer emptyOverpassServer.Close()

	routingService, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.AddressRouteRequest{
		Origin:           "somewhere",
		Destination:      "somewhere else",
		GeocoderBaseURL:  geocodeServer.URL,
		DestGeocoderBaseURL: geocodeServer.URL,
		OverpassBaseURL:  emptyOverpassServer.URL,
	}

	_, err := routingService.RouteByAddress(request)

	if err == nil {
		t.Errorf(
			"RouteByAddress with empty road network: expected an error, got nil",
		)
	}
}
