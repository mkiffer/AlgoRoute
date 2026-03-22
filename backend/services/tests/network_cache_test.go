/*
Tests for: services/network_cache.go — in-memory Overpass response cache.
Coverage intent:
  - Second RouteByAddress for the same bbox skips the Overpass fetch entirely.
  - Two requests for different bboxes each trigger their own Overpass fetch.

Uses httptest to serve a counting Overpass stub — no live external calls.
nominatimHandler is shared from address_routing_test.go (same package).
*/
package services_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"

	"algoroute/mapping"
	"algoroute/services"
)

func TestNetworkCache_SameBbox_SecondRequestSkipsOverpassFetch(t *testing.T) {
	// Verifies that a NetworkCache attached to a RoutingService prevents a
	// second Overpass fetch when the same origin/destination (and therefore
	// the same bounding box) is queried again.
	//
	// Scenario: user runs Dijkstra then switches to A* on the same route.
	// Without caching, each request re-fetches the full road network from
	// Overpass — potentially several seconds and tens of megabytes each time.

	var overpassCallCount int32 // atomic so a future parallel test is safe

	originServer := httptest.NewServer(nominatimHandler("-37.809", "144.959"))
	defer originServer.Close()
	destServer := httptest.NewServer(nominatimHandler("-37.831", "144.981"))
	defer destServer.Close()

	fixtureData, err := os.ReadFile("testdata/sample_overpass.json")
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	overpassServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&overpassCallCount, 1)
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixtureData)
	}))
	defer overpassServer.Close()

	// Arrange: RoutingService with an attached cache.
	cache := services.NewNetworkCache()
	svc, err := services.NewRoutingServiceWithCache(services.AlgorithmDijkstra, cache)
	if err != nil {
		t.Fatalf("NewRoutingServiceWithCache: %v", err)
	}

	req := services.AddressRouteRequest{
		Origin:              "near node 1001",
		Destination:         "near node 1003",
		Algorithm:           services.AlgorithmDijkstra,
		MapOpts:             mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:     originServer.URL,
		DestGeocoderBaseURL: destServer.URL,
		OverpassBaseURL:     overpassServer.URL,
	}

	// Act: first request — cold cache, must hit Overpass once.
	if _, err := svc.RouteByAddress(req); err != nil {
		t.Fatalf("first RouteByAddress: %v", err)
	}
	if got := atomic.LoadInt32(&overpassCallCount); got != 1 {
		t.Fatalf(
			"after first request: expected 1 Overpass call, got %d — "+
				"sanity check: the first call must always reach Overpass",
			got,
		)
	}

	// Act: second request — same coordinates → identical bbox → cache hit.
	if _, err := svc.RouteByAddress(req); err != nil {
		t.Fatalf("second RouteByAddress: %v", err)
	}

	// Assert: still only 1 call total.
	if got := atomic.LoadInt32(&overpassCallCount); got != 1 {
		t.Errorf(
			"after second request with same bbox: expected 1 total Overpass call (cache hit), got %d — "+
				"NetworkCache must serve the cached response without fetching again",
			got,
		)
	}
}

func TestNetworkCache_DifferentBboxes_EachFetchesSeparately(t *testing.T) {
	// Verifies that cache entries are keyed by bounding box, so requests for
	// different geographic areas are not incorrectly served from the same entry.

	var overpassCallCount int32

	fixtureData, err := os.ReadFile("testdata/sample_overpass.json")
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	overpassServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&overpassCallCount, 1)
		w.Header().Set("Content-Type", "application/json")
		w.Write(fixtureData)
	}))
	defer overpassServer.Close()

	cache := services.NewNetworkCache()
	svc, err := services.NewRoutingServiceWithCache(services.AlgorithmDijkstra, cache)
	if err != nil {
		t.Fatalf("NewRoutingServiceWithCache: %v", err)
	}

	// First request: Melbourne central (-37.8 area, 144.9 area).
	originA := httptest.NewServer(nominatimHandler("-37.809", "144.959"))
	defer originA.Close()
	destA := httptest.NewServer(nominatimHandler("-37.831", "144.981"))
	defer destA.Close()

	reqA := services.AddressRouteRequest{
		Origin:              "near node 1001",
		Destination:         "near node 1003",
		MapOpts:             mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:     originA.URL,
		DestGeocoderBaseURL: destA.URL,
		OverpassBaseURL:     overpassServer.URL,
	}
	if _, err := svc.RouteByAddress(reqA); err != nil {
		t.Fatalf("reqA RouteByAddress: %v", err)
	}

	// Second request: 2 degrees north-west — produces a clearly distinct bbox.
	originB := httptest.NewServer(nominatimHandler("-35.809", "142.959"))
	defer originB.Close()
	destB := httptest.NewServer(nominatimHandler("-35.831", "142.981"))
	defer destB.Close()

	reqB := services.AddressRouteRequest{
		Origin:              "far location 1",
		Destination:         "far location 2",
		MapOpts:             mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:     originB.URL,
		DestGeocoderBaseURL: destB.URL,
		OverpassBaseURL:     overpassServer.URL,
	}
	// Ignore the route result — the fixture nodes are in Melbourne so routing
	// with far coordinates will produce a trivial path. We only care that
	// Overpass was called again (not served from the reqA cache entry).
	svc.RouteByAddress(reqB) //nolint:errcheck

	if got := atomic.LoadInt32(&overpassCallCount); got != 2 {
		t.Errorf(
			"requests for different bboxes: expected 2 Overpass calls, got %d — "+
				"different bounding boxes must not share a NetworkCache entry",
			got,
		)
	}
}
