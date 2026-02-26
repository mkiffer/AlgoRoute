package mapping_tests

import (
	"algoroute/api/overpass"
	"algoroute/graph"
	"algoroute/mapping"
	"path/filepath"
	"sort"
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
		// AllowedHighwayTypes: nil, // start permissive
		SkipWaysWithMissingNodes: true,
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

	// Show a small sample so you can see structure
	//logNetworkSample(t, net, 3, 3) // 3 nodes, 3 edges each
}

// ignore (see below) - easiest is a direct graph.Network version
// return 0
// }

func countEdges(net *graph.Network) int {
	total := 0
	for _, edges := range net.AdjacencyList {
		total += len(edges)
	}
	return total
}

func logNetworkSample(t *testing.T, net *graph.Network, maxNodes int, maxEdgesPerNode int) {
	t.Helper()

	// Pick a stable set of node IDs (sorted) so output is deterministic
	ids := make([]graph.NodeID, 0, len(net.Nodes))
	for id := range net.Nodes {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })

	if len(ids) > maxNodes {
		ids = ids[:maxNodes]
	}

	for _, id := range ids {
		node := net.Nodes[id]
		edges := net.Neighbours(id)

		t.Logf("Node %v: (%.6f, %.6f) out=%d", id, node.Coord.Lat, node.Coord.Lon, len(edges))

		limit := len(edges)
		if limit > maxEdgesPerNode {
			limit = maxEdgesPerNode
		}
		for i := 0; i < limit; i++ {
			e := edges[i]
			t.Logf("  -> %v w=%.1f way=%d name=%q", e.To, e.Weight, e.WayID, e.Name)
		}
	}
}
