package routefinding

import (
	"testing"

	"algoroute/geo"
	"algoroute/graph"
)

func TestAStar_FindsShortestPath_UniqueBest(t *testing.T) {
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

	path, dist, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, path, []graph.NodeID{1, 2, 3})

	if dist != 2 {
		t.Fatalf("distance: got %v want %v", dist, 2.0)
	}
}

func TestAStar_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}

	// Only 1 -> 2 exists. Node 3 is disconnected.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	path, dist, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatalf("expected error for unreachable target, got nil (path=%v dist=%v)", path, dist)
	}
}

func TestAStar_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	path, dist, err := AStar(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, path, []graph.NodeID{1})

	if dist != 0 {
		t.Fatalf("distance: got %v want %v", dist, 0.0)
	}
}

func TestAStar_RespectsDirection_DirectedGraph(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2} {
		mustAddNode(t, net, id)
	}

	// One-way edge: 1 -> 2 only
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	// Route 2 -> 1 should be unreachable
	_, _, err := AStar(net, graph.NodeID(2), graph.NodeID(1))
	if err == nil {
		t.Fatalf("expected error for unreachable route in directed graph, got nil")
	}
}

func TestAStar_WithRealCoords_AdmissibleHeuristic(t *testing.T) {
	// Nodes laid out so that 1->2->3 is shorter than 1->3 direct.
	// Edge weights are actual Haversine distances so the heuristic is admissible.
	//
	//   1 (0°N, 0°E) --detour via-- 2 (0°N, 0.5°E) -- 3 (0°N, 1°E)
	//
	// dist(1,2) ≈ 55,597 m   dist(2,3) ≈ 55,597 m   total ≈ 111,194 m
	// dist(1,3) ≈ 111,195 m  (direct, slightly longer due to great-circle arc vs sum)
	//
	// With a high-cost direct edge and cheap via-2 path, A* should pick via-2.
	net := graph.NewNetwork()

	c1 := geo.Coord{Lat: 0.0, Lon: 0.0}
	c2 := geo.Coord{Lat: 0.0, Lon: 0.5}
	c3 := geo.Coord{Lat: 0.0, Lon: 1.0}

	net.AddNode(graph.Node{ID: 1, Coord: c1})
	net.AddNode(graph.Node{ID: 2, Coord: c2})
	net.AddNode(graph.Node{ID: 3, Coord: c3})

	// Use actual Haversine distances as weights so the heuristic is admissible.
	d12 := geo.DistanceMeters(c1, c2)
	d23 := geo.DistanceMeters(c2, c3)
	// Direct edge is heavily penalised so the via-2 route wins.
	d13penalty := geo.DistanceMeters(c1, c3) * 10

	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: d12})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: d23})
	mustAddEdge(t, net, edgeSpec{from: 1, to: 3, weight: d13penalty})

	path, _, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, path, []graph.NodeID{1, 2, 3})
}
