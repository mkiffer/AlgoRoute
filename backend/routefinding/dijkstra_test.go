package routefinding

import (
	"testing"

	"algoroute/geo"
	"algoroute/graph"
)

// --- helpers ---

type edgeSpec struct {
	from   int64
	to     int64
	weight float64
}

func mustAddNode(t *testing.T, net *graph.Network, id int64) {
	t.Helper()
	net.AddNode(graph.Node{
		ID:    graph.NodeID(id),
		Coord: geo.Coord{Lat: 0, Lon: 0}, // coords irrelevant for Dijkstra unit tests
	})
}

func mustAddEdge(t *testing.T, net *graph.Network, e edgeSpec) {
	t.Helper()
	if err := net.AddEdge(graph.Edge{
		From:   graph.NodeID(e.from),
		To:     graph.NodeID(e.to),
		Weight: e.weight,
	}); err != nil {
		t.Fatalf("AddEdge %d->%d (w=%v) failed: %v", e.from, e.to, e.weight, err)
	}
}

func assertPathEquals(t *testing.T, got []graph.NodeID, want []graph.NodeID) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("path length: got %d want %d. got=%v want=%v", len(got), len(want), got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("path[%d]: got %v want %v. got=%v want=%v", i, got[i], want[i], got, want)
		}
	}
}

// --- tests ---

func TestDijkstra_FindsShortestPath_UniqueBest(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3, 4, 5} {
		mustAddNode(t, net, id)
	}

	// Unique best path from 1 to 3 is: 1 -> 2 -> 3 (cost 2)
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	// A longer direct edge exists
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: 5})
	// Another longer alternative path exists
	mustAddEdge(t, net, edgeSpec{from: 1, to: 4, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 4, to: 5, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 5, to: 3, weight: 2})
	path, dist, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, path, []graph.NodeID{1, 2, 3})

	if dist != 2 {
		t.Fatalf("distance: got %v want %v", dist, 2.0)
	}
}

func TestDijkstra_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}

	// Only 1 -> 2 exists. Node 3 is disconnected.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	path, dist, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatalf("expected error for unreachable target, got nil (path=%v dist=%v)", path, dist)
	}
}

func TestDijkstra_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	path, dist, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	// Expected behavior for a clean implementation:
	// path is [start], distance is 0.
	assertPathEquals(t, path, []graph.NodeID{1})

	if dist != 0 {
		t.Fatalf("distance: got %v want %v", dist, 0.0)
	}
}

func TestDijkstra_RespectsDirection_DirectedGraph(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2} {
		mustAddNode(t, net, id)
	}

	// One-way edge: 1 -> 2 only
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	// Route 2 -> 1 should be unreachable
	_, _, err := Dijkstra(net, graph.NodeID(2), graph.NodeID(1))
	if err == nil {
		t.Fatalf("expected error for unreachable route in directed graph, got nil")
	}
}

func TestDijkstra_ChoosesCheapestAmongManyOutgoing(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3, 4} {
		mustAddNode(t, net, id)
	}

	// From 1 there are multiple options:
	// 1->2 (10), 1->3 (1), 3->4 (1), 2->4 (1)
	// Cheapest 1->4 is: 1->3->4 cost 2.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 10})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 3, to: 4, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 4, weight: 1})

	path, dist, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, path, []graph.NodeID{1, 3, 4})

	if dist != 2 {
		t.Fatalf("distance: got %v want %v", dist, 2.0)
	}
}
