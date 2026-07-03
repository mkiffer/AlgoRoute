package routefinding

import (
	"testing"

	"algoroute/graph"
)

func TestBidirectionalDijkstra_FindsShortestPath(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3, 4, 5} {
		mustAddNode(t, net, id)
	}

	// Unique best path 1→2→3 (cost 2); longer alternatives exist.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: 5})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 4, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 4, to: 5, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 5, to: 3, weight: 2})

	result, err := BidirectionalDijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Distance != 2 {
		t.Errorf("distance: got %v want 2", result.Distance)
	}

	// Dijkstra must agree on the optimal distance.
	dResult, _ := Dijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if result.Distance != dResult.Distance {
		t.Errorf("distance mismatch with Dijkstra: bidirectional=%v dijkstra=%v",
			result.Distance, dResult.Distance)
	}
}

func TestBidirectionalDijkstra_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	// Node 3 disconnected — no edge reaches it.

	_, err := BidirectionalDijkstra(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatal("expected error for unreachable goal, got nil")
	}
}

func TestBidirectionalDijkstra_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := BidirectionalDijkstra(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1})
	if result.Distance != 0 {
		t.Fatalf("distance: got %v want 0", result.Distance)
	}
}

func TestBidirectionalDijkstra_RespectsDirection_DirectedGraph(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2} {
		mustAddNode(t, net, id)
	}

	// One-way edge 1 → 2 only; route 2 → 1 must fail.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	_, err := BidirectionalDijkstra(net, graph.NodeID(2), graph.NodeID(1))
	if err == nil {
		t.Fatal("expected error for unreachable route in directed graph, got nil")
	}
}

// TestBidirectionalDijkstra_VisitedNodes_FewerThanDijkstra shows the efficiency
// gain on a graph where the optimal path is cheap but the forward search would
// have to settle a dead-end node before the termination condition fires.
//
// Graph:
//
//	1 → 2 → 4 (goal)   [cost 2+2=4, optimal path]
//	1 → 3               [cost 3, dead-end — Dijkstra must settle it;
//	                     bidirectional's termination fires before it does]
func TestBidirectionalDijkstra_VisitedNodes_FewerThanDijkstra(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3, 4} {
		mustAddNode(t, net, id)
	}

	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 4, weight: 2})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: 3}) // dead end

	biResult, err := BidirectionalDijkstra(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	dResult, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(4))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if len(biResult.VisitedNodes) >= len(dResult.VisitedNodes) {
		t.Errorf("expected bidirectional to visit fewer nodes: bidirectional=%d dijkstra=%d",
			len(biResult.VisitedNodes), len(dResult.VisitedNodes))
	}
}

func TestBidirectionalDijkstra_VisitedNodes_ContainsStartAndGoal(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := BidirectionalDijkstra(net, graph.NodeID(1), graph.NodeID(3))
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
