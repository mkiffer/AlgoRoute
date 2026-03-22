package mapping_tests

import (
	"algoroute/api/overpass"
	"algoroute/graph"
	"algoroute/mapping"
	"path/filepath"
	"testing"
)

func TestBuildNetwork_Smoke(t *testing.T) {
	path := filepath.Join("testdata", "sample_overpass.json")

	resp, err := overpass.LoadNetworkFromJSON(path)
	if err != nil {
		t.Fatalf("LoadNetworkFromJSON: %v", err)
	}

	opts := mapping.BuildOptions{
		AssumeBidirectional: true,
	}

	net, stats, err := mapping.BuildNetwork(resp, opts)
	if err != nil {
		t.Fatalf("BuildNetwork: %v", err)
	}

	// Basic sanity
	if net == nil {
		t.Fatalf("net is nil")
	}
	if len(net.Nodes) == 0 {
		t.Fatalf("expected nodes > 0, got 0. stats=%+v", stats)
	}
	edgeCount := countEdges(net)
	if edgeCount == 0 {
		t.Fatalf("expected edges > 0, got 0. stats=%+v", stats)
	}

	// Optional: check no self-loops (common mapping bug)
	for from, edges := range net.AdjacencyList {
		for _, e := range edges {
			if e.From != from {
				t.Fatalf("edge.From mismatch: map key %v but edge.From %v", from, e.From)
			}
			if e.From == e.To {
				t.Fatalf("self-loop detected at node %v (edge=%+v)", from, e)
			}
		}
	}

	// Debug output only when running `go test -v`
	t.Logf("BuildStats: %+v", stats)
	t.Logf("Nodes=%d Edges=%d", len(net.Nodes), edgeCount)
}

func countEdges(net *graph.Network) int {
	total := 0
	for _, edges := range net.AdjacencyList {
		total += len(edges)
	}
	return total
}
