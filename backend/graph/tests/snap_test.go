/*
Tests for: graph/snap.go — NearestNode coordinate snapping.
Coverage intent: happy path (returns closest node), edge cases (single node,
all equidistant nodes), and error case (empty network).
Not covered here: performance on large networks (out of scope for unit tests).
*/
package graph_tests

import (
	"testing"

	"algoroute/geo"
	"algoroute/graph"
)

func TestNearestNode_ReturnsClosestNodeToTarget(t *testing.T) {
	// The geocoded coordinate rarely falls exactly on a graph node. NearestNode
	// must snap to the node with the shortest Haversine distance so that the
	// routing algorithm starts and ends as close to the requested location as
	// possible.
	network := graph.NewNetwork()
	network.AddNode(graph.Node{ID: 1, Coord: geo.Coord{Lat: -37.81, Lon: 144.96}})
	network.AddNode(graph.Node{ID: 2, Coord: geo.Coord{Lat: -37.82, Lon: 144.97}})
	network.AddNode(graph.Node{ID: 3, Coord: geo.Coord{Lat: -37.83, Lon: 144.98}})

	// Target is placed very close to node 2.
	target := geo.Coord{Lat: -37.821, Lon: 144.971}

	nearestID, err := graph.NearestNode(network, target)

	if err != nil {
		t.Fatalf("NearestNode: unexpected error: %v", err)
	}
	if nearestID != graph.NodeID(2) {
		t.Errorf(
			"NearestNode: got node %d, want 2 — target %+v should snap to the closest node",
			nearestID, target,
		)
	}
}

func TestNearestNode_SingleNodeNetwork_ReturnsThatNode(t *testing.T) {
	// When there is only one node in the network there is no ambiguity: that
	// node must always be returned regardless of the target position.
	network := graph.NewNetwork()
	network.AddNode(graph.Node{ID: 42, Coord: geo.Coord{Lat: -37.81, Lon: 144.96}})

	target := geo.Coord{Lat: -37.90, Lon: 145.10}

	nearestID, err := graph.NearestNode(network, target)

	if err != nil {
		t.Fatalf("NearestNode single-node: unexpected error: %v", err)
	}
	if nearestID != graph.NodeID(42) {
		t.Errorf("NearestNode single-node: got node %d, want 42", nearestID)
	}
}

func TestNearestNode_EmptyNetwork_ReturnsError(t *testing.T) {
	// An empty network means there is no valid snap target. Returning a zero
	// NodeID would silently route from a nonexistent node, causing a confusing
	// downstream error. An explicit error here surfaces the problem clearly.
	network := graph.NewNetwork()
	target := geo.Coord{Lat: -37.81, Lon: 144.96}

	_, err := graph.NearestNode(network, target)

	if err == nil {
		t.Errorf(
			"NearestNode on empty network: expected an error, got nil — " +
				"a zero NodeID return would silently corrupt the routing request",
		)
	}
}
