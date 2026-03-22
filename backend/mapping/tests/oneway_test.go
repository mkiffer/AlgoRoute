/*
Tests for: mapping/road_mapper.go — OSM oneway tag handling.
Coverage intent:
  - oneway=yes  → forward edge only  (A→B exists, B→A does not)
  - oneway=-1   → backward edge only (A→B does not exist, B→A does)
  - oneway=no   → explicitly bidirectional even when AssumeBidirectional=false
  - No oneway tag + AssumeBidirectional=true → bidirectional (unchanged behaviour)

Not covered here: multi-segment ways, missing nodes, highway type filtering.
*/
package mapping_tests

import (
	"algoroute/api/overpass"
	"algoroute/graph"
	"algoroute/mapping"
	"testing"
)

// buildTwoNodeWay creates an in-memory Overpass response containing two nodes
// joined by a single way. onewayTag is added to the way's Tags if non-empty;
// an empty string means no oneway tag is present (untagged = bidirectional default).
func buildTwoNodeWay(fromID, toID int64, onewayTag string) overpass.Response {
	// Non-zero, non-equal coordinates so Haversine distances are positive.
	lat1, lon1 := 1.0, 1.0
	lat2, lon2 := 2.0, 2.0

	fromNode := overpass.Element{Type: "node", Id: fromID, Lat: &lat1, Lon: &lon1}
	toNode := overpass.Element{Type: "node", Id: toID, Lat: &lat2, Lon: &lon2}

	tags := map[string]string{}
	if onewayTag != "" {
		tags["oneway"] = onewayTag
	}

	way := overpass.Element{
		Type:  "way",
		Id:    9999,
		Nodes: []int64{fromID, toID},
		Tags:  tags,
	}

	return overpass.Response{
		Ways:  []overpass.Element{way},
		Nodes: []overpass.Element{fromNode, toNode},
		NodeByID: map[int64]overpass.Element{
			fromID: fromNode,
			toID:   toNode,
		},
	}
}

func TestBuildNetwork_OneWayYes_HasOnlyForwardEdge(t *testing.T) {
	// A way tagged oneway=yes must produce only the A→B forward edge.
	// The reverse edge B→A must be absent — allowing it would let the
	// routing engine plan routes against traffic flow.

	// Arrange
	const fromID, toID = int64(100), int64(200)
	resp := buildTwoNodeWay(fromID, toID, "yes")
	opts := mapping.BuildOptions{AssumeBidirectional: true}

	// Act
	net, _, err := mapping.BuildNetwork(resp, opts)

	// Assert
	if err != nil {
		t.Fatalf("BuildNetwork: %v", err)
	}
	forwardEdges := net.Neighbours(graph.NodeID(fromID))
	if len(forwardEdges) != 1 {
		t.Errorf(
			"oneway=yes: expected 1 forward edge from node %d, got %d — "+
				"the A→B edge must be present",
			fromID, len(forwardEdges),
		)
	}
	backwardEdges := net.Neighbours(graph.NodeID(toID))
	if len(backwardEdges) != 0 {
		t.Errorf(
			"oneway=yes: expected 0 backward edges from node %d, got %d — "+
				"oneway=yes must suppress the reverse edge even when AssumeBidirectional=true",
			toID, len(backwardEdges),
		)
	}
}

func TestBuildNetwork_OneWayMinusOne_HasOnlyBackwardEdge(t *testing.T) {
	// A way tagged oneway=-1 means travel is allowed only in the reverse
	// direction (B→A). OSM uses this when a way's node sequence runs
	// opposite to the legal traffic direction.

	// Arrange
	const fromID, toID = int64(100), int64(200)
	resp := buildTwoNodeWay(fromID, toID, "-1")
	opts := mapping.BuildOptions{AssumeBidirectional: true}

	// Act
	net, _, err := mapping.BuildNetwork(resp, opts)

	// Assert
	if err != nil {
		t.Fatalf("BuildNetwork: %v", err)
	}
	forwardEdges := net.Neighbours(graph.NodeID(fromID))
	if len(forwardEdges) != 0 {
		t.Errorf(
			"oneway=-1: expected 0 forward edges from node %d, got %d — "+
				"oneway=-1 must suppress the forward edge A→B",
			fromID, len(forwardEdges),
		)
	}
	backwardEdges := net.Neighbours(graph.NodeID(toID))
	if len(backwardEdges) != 1 {
		t.Errorf(
			"oneway=-1: expected 1 backward edge from node %d, got %d — "+
				"the reverse edge B→A must exist for reverse-direction ways",
			toID, len(backwardEdges),
		)
	}
}

func TestBuildNetwork_NoOneWayTag_IsBidirectionalWithAssumeBidirectional(t *testing.T) {
	// A way with no oneway tag and AssumeBidirectional=true must produce edges
	// in both directions. Most OSM roads are untagged and bidirectional.

	// Arrange
	const fromID, toID = int64(100), int64(200)
	resp := buildTwoNodeWay(fromID, toID, "") // no oneway tag
	opts := mapping.BuildOptions{AssumeBidirectional: true}

	// Act
	net, _, err := mapping.BuildNetwork(resp, opts)

	// Assert
	if err != nil {
		t.Fatalf("BuildNetwork: %v", err)
	}
	if n := len(net.Neighbours(graph.NodeID(fromID))); n != 1 {
		t.Errorf(
			"no oneway tag + AssumeBidirectional=true: expected 1 forward edge from node %d, got %d",
			fromID, n,
		)
	}
	if n := len(net.Neighbours(graph.NodeID(toID))); n != 1 {
		t.Errorf(
			"no oneway tag + AssumeBidirectional=true: expected 1 backward edge from node %d, got %d",
			toID, n,
		)
	}
}

func TestBuildNetwork_OneWayNo_IsBidirectionalRegardlessOfOption(t *testing.T) {
	// oneway=no explicitly marks a way as bidirectional. This must produce
	// both edges even when AssumeBidirectional=false, because an explicit
	// tag must take precedence over the build option.

	// Arrange
	const fromID, toID = int64(100), int64(200)
	resp := buildTwoNodeWay(fromID, toID, "no")
	opts := mapping.BuildOptions{AssumeBidirectional: false} // option says do not assume...

	// Act
	net, _, err := mapping.BuildNetwork(resp, opts)

	// Assert
	if err != nil {
		t.Fatalf("BuildNetwork: %v", err)
	}
	if n := len(net.Neighbours(graph.NodeID(fromID))); n != 1 {
		t.Errorf(
			"oneway=no: expected 1 forward edge from node %d, got %d",
			fromID, n,
		)
	}
	if n := len(net.Neighbours(graph.NodeID(toID))); n != 1 {
		t.Errorf(
			"oneway=no with AssumeBidirectional=false: expected 1 backward edge from node %d, got %d — "+
				"explicit oneway=no must override AssumeBidirectional=false",
			toID, n,
		)
	}
}
