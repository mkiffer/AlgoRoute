package overpass_test

import (
	"algoroute/api/overpass"
	"path/filepath"
	"testing"
)

func TestLoadNetworkFromJSON_ParsesElementsAndSplitsWaysNodes(t *testing.T) {
	// In your repo, copy a small JSON sample into testdata/sample_overpass.json.
	// Keep it small so tests stay fast and stable.
	path := filepath.Join("testdata", "sample_overpass.json")

	resp, err := overpass.LoadNetworkFromJson(path)
	if err != nil {
		t.Fatalf("LoadNetworkFromJSON returned error: %v", err)
	}

	if len(resp.Elements) == 0 {
		t.Fatalf("expected Elements to be non-empty")
	}
	if len(resp.Ways) == 0 {
		t.Fatalf("expected at least one way")
	}
	if len(resp.Nodes) == 0 {
		t.Fatalf("expected at least one node")
	}

	// Basic sanity checks on a way
	var someWay overpass.Element
	for _, w := range resp.Ways {
		if len(w.Nodes) > 1 {
			someWay = w
			break
		}
	}
	if someWay.Id == 0 {
		t.Fatalf("expected to find a way with at least 2 nodes")
	}

	// Check tags are available (not all ways have 'name', so check for any tag)
	if len(someWay.Tags) == 0 {
		t.Fatalf("expected way to have tags")
	}

	// Basic sanity checks on a node
	var someNode overpass.Element
	for _, n := range resp.Nodes {
		if n.Lat != nil && n.Lon != nil {
			someNode = n
			break
		}
	}
	if someNode.Id == 0 {
		t.Fatalf("expected to find a node with lat/lon")
	}
}
