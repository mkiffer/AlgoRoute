/*
Tests for: api/overpass/fetch.go — live Overpass API HTTP fetch.
Coverage intent: Overpass QL query construction (unit-testable), and response
parsing + Response field population via an httptest server.
Not covered here: live Overpass API calls (require network access and are
non-deterministic in CI environments).
*/
package overpass_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"algoroute/api/overpass"
	"algoroute/geo"
)

func TestBuildOverpassQuery_ContainsHighwayFilter(t *testing.T) {
	// The query must filter by highway type so that only driveable roads are
	// returned. Without this filter, pedestrian paths and footways would be
	// included in the graph, leading the router to suggest non-driveable routes.
	bbox := geo.BBox{MinLat: -37.85, MinLon: 144.95, MaxLat: -37.80, MaxLon: 145.00}

	query := overpass.BuildOverpassQuery(bbox)

	if !strings.Contains(query, "highway") {
		t.Errorf(
			"BuildOverpassQuery: expected 'highway' filter in query, got:\n%s",
			query,
		)
	}
}

func TestBuildOverpassQuery_ContainsBBoxCoordinates(t *testing.T) {
	// The bounding box coordinates must appear in the query so that Overpass
	// returns only roads within the area between origin and destination.
	bbox := geo.BBox{MinLat: -37.850000, MinLon: 144.950000, MaxLat: -37.800000, MaxLon: 145.000000}

	query := overpass.BuildOverpassQuery(bbox)

	// Overpass QL bbox order: south, west, north, east = MinLat, MinLon, MaxLat, MaxLon.
	if !strings.Contains(query, "-37.850000") {
		t.Errorf("BuildOverpassQuery: MinLat -37.850000 not found in query:\n%s", query)
	}
	if !strings.Contains(query, "144.950000") {
		t.Errorf("BuildOverpassQuery: MinLon 144.950000 not found in query:\n%s", query)
	}
	if !strings.Contains(query, "-37.800000") {
		t.Errorf("BuildOverpassQuery: MaxLat -37.800000 not found in query:\n%s", query)
	}
	if !strings.Contains(query, "145.000000") {
		t.Errorf("BuildOverpassQuery: MaxLon 145.000000 not found in query:\n%s", query)
	}
}

func TestBuildOverpassQuery_RequestsJSONOutput(t *testing.T) {
	// The query must include [out:json] so that Overpass returns JSON, which
	// is what the overpass.Response parser expects.
	bbox := geo.BBox{MinLat: -37.85, MinLon: 144.95, MaxLat: -37.80, MaxLon: 145.00}

	query := overpass.BuildOverpassQuery(bbox)

	if !strings.Contains(query, "out:json") {
		t.Errorf(
			"BuildOverpassQuery: expected 'out:json' directive in query, got:\n%s",
			query,
		)
	}
}

func TestFetchFromAPIWithBaseURL_PopulatesWaysNodesAndNodeByID(t *testing.T) {
	// Verifies that the derived fields (Ways, Nodes, NodeByID) are populated
	// after fetching, mirroring the behaviour of LoadNetworkFromJSON. Without
	// these fields the mapping layer cannot build a graph.
	fakeResponse := map[string]interface{}{
		"version": 0.6,
		"elements": []map[string]interface{}{
			{
				"type": "node",
				"id":   float64(1001),
				"lat":  -37.81,
				"lon":  144.96,
			},
			{
				"type":  "way",
				"id":    float64(2001),
				"nodes": []int{1001},
				"tags":  map[string]string{"highway": "residential"},
			},
		},
	}
	responseBody, _ := json.Marshal(fakeResponse)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write(responseBody)
	}))
	defer server.Close()

	bbox := geo.BBox{MinLat: -37.85, MinLon: 144.95, MaxLat: -37.80, MaxLon: 145.00}

	response, err := overpass.FetchFromAPIWithBaseURL(bbox, server.URL)

	if err != nil {
		t.Fatalf("FetchFromAPIWithBaseURL: unexpected error: %v", err)
	}
	if len(response.Ways) != 1 {
		t.Errorf("FetchFromAPIWithBaseURL: Ways count got %d, want 1", len(response.Ways))
	}
	if len(response.Nodes) != 1 {
		t.Errorf("FetchFromAPIWithBaseURL: Nodes count got %d, want 1", len(response.Nodes))
	}
	if _, ok := response.NodeByID[1001]; !ok {
		t.Errorf(
			"FetchFromAPIWithBaseURL: NodeByID missing entry for node 1001 — " +
				"mapping layer requires NodeByID for coordinate lookups",
		)
	}
}
