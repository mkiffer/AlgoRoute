package graph_tests

import (
	"algoroute/geo"
	"algoroute/graph"
	"testing"
)

func TestNetwork_AddNodesAndEdges_Adjacency(t *testing.T) {
	net := graph.NewNetwork()
	// Add nodes 1,2,3
	net.AddNode(graph.Node{ID: graph.NodeID(1), Coord: geo.Coord{Lat: -37.81, Lon: 144.96}})
	net.AddNode(graph.Node{ID: graph.NodeID(2), Coord: geo.Coord{Lat: -37.82, Lon: 144.97}})
	net.AddNode(graph.Node{ID: graph.NodeID(3), Coord: geo.Coord{Lat: -37.83, Lon: 144.98}})
	// Add edges 1->2 (5), 2->3 (7)
	if err := net.AddEdge(graph.Edge{From: graph.NodeID(1), To: graph.NodeID(2), Weight: 5}); err != nil {
		t.Fatalf("AddEdge 1->2: %v", err)
	}
	if err := net.AddEdge(graph.Edge{From: graph.NodeID(2), To: graph.NodeID(3), Weight: 7}); err != nil {
		t.Fatalf("AddEdge 2->3: %v", err)
	}

	// Neighbors(1) should have exactly one edge: 1->2 (5)
	n1 := net.Neighbours(graph.NodeID(1))
	if got := len(n1); got != 1 {
		t.Fatalf("Neighbors(1) length: got %d, want 1", got)
	}
	if n1[0].To != graph.NodeID(2) {
		t.Fatalf("Neighbors(1)[0].To: got %v, want %v", n1[0].To, graph.NodeID(2))
	}
	if n1[0].Weight != 5 {
		t.Fatalf("Neighbors(1)[0].Weight: got %v, want %v", n1[0].Weight, 5.0)
	}

	// Neighbors(2) should have exactly one edge: 2->3 (7)
	n2 := net.Neighbours(graph.NodeID(2))
	if got := len(n2); got != 1 {
		t.Fatalf("Neighbors(2) length: got %d, want 1", got)
	}
	if n2[0].To != graph.NodeID(3) {
		t.Fatalf("Neighbors(2)[0].To: got %v, want %v", n2[0].To, graph.NodeID(3))
	}
	if n2[0].Weight != 7 {
		t.Fatalf("Neighbors(2)[0].Weight: got %v, want %v", n2[0].Weight, 7.0)
	}

	// Neighbors(3) should be empty in this directed setup
	n3 := net.Neighbours(graph.NodeID(3))
	if got := len(n3); got != 0 {
		t.Fatalf("Neighbors(3) length: got %d, want 0", got)
	}
}

func TestNetwork_AddEdge_FailsWhenNodeMissing(t *testing.T) {
	net := graph.NewNetwork()

	// Only add node 1
	net.AddNode(graph.Node{ID: graph.NodeID(1), Coord: geo.Coord{Lat: 0, Lon: 0}})

	// Try to add edge 1->2 where node 2 doesn't exist
	if err := net.AddEdge(graph.Edge{From: graph.NodeID(1), To: graph.NodeID(2), Weight: 1}); err == nil {
		t.Fatalf("expected error when adding edge to missing node, got nil")
	}
}
