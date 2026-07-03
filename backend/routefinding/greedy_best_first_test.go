package routefinding

import (
	"testing"

	"algoroute/geo"
	"algoroute/graph"
)

func TestGreedyBestFirst_FindsAPath(t *testing.T) {
	// Simple linear graph with zero coordinates. When h=0 for all nodes,
	// greedy degenerates to first-discovered order — it still finds a valid path.
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := GreedyBestFirst(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Any valid path is acceptable; verify it starts at 1 and ends at 3.
	if len(result.Path) == 0 {
		t.Fatal("expected non-empty path")
	}
	if result.Path[0] != graph.NodeID(1) {
		t.Errorf("path should start at 1, got %v", result.Path[0])
	}
	if result.Path[len(result.Path)-1] != graph.NodeID(3) {
		t.Errorf("path should end at 3, got %v", result.Path[len(result.Path)-1])
	}
	if result.Distance != 2 {
		t.Errorf("distance: got %v want 2", result.Distance)
	}
}

// TestGreedyBestFirst_MayReturnSuboptimalPath demonstrates the core weakness of
// greedy best-first: it follows the node geometrically closest to the goal even
// when that path is expensive. The "trap" node sits near the goal in straight-
// line distance but is reached via a very heavy edge. The "safe" node is farther
// from the goal geographically but part of a cheap route. Greedy picks trap first.
func TestGreedyBestFirst_MayReturnSuboptimalPath(t *testing.T) {
	net := graph.NewNetwork()

	// goal at (lat=0, lon=1) so nodes at lon≈1 have small h.
	goalCoord := geo.Coord{Lat: 0, Lon: 1}

	net.AddNode(graph.Node{ID: 1, Coord: geo.Coord{Lat: 0, Lon: 0}})
	// trap: geographically close to goal (h ≈ 1.1 km), but reached via huge edge weight.
	net.AddNode(graph.Node{ID: 2, Coord: geo.Coord{Lat: 0, Lon: 0.99}})
	// safe: geographically far from goal (h ≈ 124 km), but part of the cheap path.
	net.AddNode(graph.Node{ID: 3, Coord: geo.Coord{Lat: 1, Lon: 0.5}})
	net.AddNode(graph.Node{ID: 4, Coord: goalCoord})

	// Cheap optimal path: start → safe → goal (total cost 4).
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 3, to: 4, weight: 2})

	// Expensive greedy-preferred path: start → trap → goal (total cost 1001).
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1000})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 4, weight: 1})

	greedyResult, err := GreedyBestFirst(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	dijkstraResult, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Greedy must still find a valid path — just not the optimal one.
	if len(greedyResult.Path) == 0 {
		t.Fatal("expected non-empty path from greedy")
	}

	// The whole point: greedy returns a worse path than Dijkstra.
	if greedyResult.Distance <= dijkstraResult.Distance {
		t.Errorf(
			"expected greedy to return a suboptimal path: greedy=%.1f dijkstra=%.1f",
			greedyResult.Distance, dijkstraResult.Distance,
		)
	}
}

func TestGreedyBestFirst_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	// Node 3 is disconnected.

	_, err := GreedyBestFirst(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatal("expected error for unreachable goal, got nil")
	}
}

func TestGreedyBestFirst_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := GreedyBestFirst(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1})
	if result.Distance != 0 {
		t.Fatalf("distance: got %v want 0", result.Distance)
	}
}

func TestGreedyBestFirst_VisitedNodes_ContainsStartAndGoal(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := GreedyBestFirst(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !containsNode(result.VisitedNodes, graph.NodeID(1)) {
		t.Errorf("VisitedNodes missing start (1): %v", result.VisitedNodes)
	}
	if !containsNode(result.VisitedNodes, graph.NodeID(3)) {
		t.Errorf("VisitedNodes missing goal (3): %v", result.VisitedNodes)
	}
}
