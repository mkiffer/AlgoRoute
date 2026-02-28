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

// containsNode reports whether nodeID appears anywhere in nodes.
func containsNode(nodes []graph.NodeID, nodeID graph.NodeID) bool {
	for _, n := range nodes {
		if n == nodeID {
			return true
		}
	}
	return false
}

// --- path tests ---

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

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1, 2, 3})

	if result.Distance != 2 {
		t.Fatalf("distance: got %v want %v", result.Distance, 2.0)
	}
}

func TestDijkstra_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}

	// Only 1 -> 2 exists. Node 3 is disconnected.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatalf("expected error for unreachable target, got nil (path=%v)", result.Path)
	}
}

func TestDijkstra_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	// Expected behavior for a clean implementation:
	// path is [start], distance is 0.
	assertPathEquals(t, result.Path, []graph.NodeID{1})

	if result.Distance != 0 {
		t.Fatalf("distance: got %v want %v", result.Distance, 0.0)
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
	_, err := Dijkstra(net, graph.NodeID(2), graph.NodeID(1))
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

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1, 3, 4})

	if result.Distance != 2 {
		t.Fatalf("distance: got %v want %v", result.Distance, 2.0)
	}
}

// --- visited-nodes tests ---

func TestDijkstra_VisitedNodes_StartsAtStart(t *testing.T) {
	// The first settled node must always be the start — it is pushed with cost 0
	// and no cheaper path to it can exist.
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.VisitedNodes) == 0 {
		t.Fatal("VisitedNodes must not be empty")
	}
	if result.VisitedNodes[0] != graph.NodeID(1) {
		t.Errorf("VisitedNodes[0]: got %v want 1", result.VisitedNodes[0])
	}
}

func TestDijkstra_VisitedNodes_ContainsGoal(t *testing.T) {
	// The goal node must appear in VisitedNodes — the algorithm terminates when
	// it is settled, so it must have been recorded.
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !containsNode(result.VisitedNodes, graph.NodeID(3)) {
		t.Errorf("VisitedNodes does not contain goal node 3: %v", result.VisitedNodes)
	}
}

func TestDijkstra_VisitedNodes_ContainsAllPathNodes(t *testing.T) {
	// Every node on the optimal path must have been settled — the path is built
	// from the arrivedVia map, which is only populated when a node is relaxed
	// after being settled by its predecessor.
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3, 4, 5} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 4, weight: 10})
	mustAddEdge(t, net, edgeSpec{from: 4, to: 5, weight: 10})

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	for _, pathNode := range result.Path {
		if !containsNode(result.VisitedNodes, pathNode) {
			t.Errorf("path node %v missing from VisitedNodes: %v", pathNode, result.VisitedNodes)
		}
	}
}

func TestDijkstra_StartEqualsGoal_VisitedNodesIsStart(t *testing.T) {
	// Trivial path: only the start/goal node should appear as visited.
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.VisitedNodes) != 1 || result.VisitedNodes[0] != graph.NodeID(1) {
		t.Errorf("VisitedNodes for trivial path: got %v want [1]", result.VisitedNodes)
	}
}
