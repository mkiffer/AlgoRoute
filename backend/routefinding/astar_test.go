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

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1, 2, 3})

	if result.Distance != 2 {
		t.Fatalf("distance: got %v want %v", result.Distance, 2.0)
	}
}

func TestAStar_Unreachable_ReturnsError(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}

	// Only 1 -> 2 exists. Node 3 is disconnected.
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err == nil {
		t.Fatalf("expected error for unreachable target, got nil (path=%v)", result.Path)
	}
}

func TestAStar_StartEqualsGoal_ReturnsTrivialPath(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1})

	if result.Distance != 0 {
		t.Fatalf("distance: got %v want %v", result.Distance, 0.0)
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
	_, err := AStar(net, graph.NodeID(2), graph.NodeID(1))
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

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("expected nil error, got: %v", err)
	}

	assertPathEquals(t, result.Path, []graph.NodeID{1, 2, 3})
}

// --- visited-nodes tests ---

func TestAStar_VisitedNodes_StartsAtStart(t *testing.T) {
	// The first settled node must always be the start — same reasoning as Dijkstra.
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
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

func TestAStar_VisitedNodes_ContainsGoal(t *testing.T) {
	net := graph.NewNetwork()
	for _, id := range []int64{1, 2, 3} {
		mustAddNode(t, net, id)
	}
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: 1})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: 1})

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(3))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !containsNode(result.VisitedNodes, graph.NodeID(3)) {
		t.Errorf("VisitedNodes does not contain goal node 3: %v", result.VisitedNodes)
	}
}

func TestAStar_StartEqualsGoal_VisitedNodesIsStart(t *testing.T) {
	net := graph.NewNetwork()
	mustAddNode(t, net, 1)

	result, err := AStar(net, graph.NodeID(1), graph.NodeID(1))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(result.VisitedNodes) != 1 || result.VisitedNodes[0] != graph.NodeID(1) {
		t.Errorf("VisitedNodes for trivial path: got %v want [1]", result.VisitedNodes)
	}
}

func TestAStar_VisitsFewerOrEqualNodesThanDijkstra(t *testing.T) {
	// On a graph with real Haversine-distance weights and coordinates pointing
	// toward the goal, A*'s heuristic biases expansion toward the goal and
	// should settle no more nodes than Dijkstra on the same query.
	//
	// Layout: five nodes in a straight east line. Dijkstra must explore all
	// branches; A*'s heuristic steers it directly along the correct axis.
	//
	//   1(0,0) -> 2(0,0.25) -> 3(0,0.5) -> 4(0,0.75) -> 5(0,1.0)
	//   Also: 1 -> detour (0,0.25 offset north) -> 5 (expensive penalty)
	net := graph.NewNetwork()

	c1 := geo.Coord{Lat: 0.0, Lon: 0.00}
	c2 := geo.Coord{Lat: 0.0, Lon: 0.25}
	c3 := geo.Coord{Lat: 0.0, Lon: 0.50}
	c4 := geo.Coord{Lat: 0.0, Lon: 0.75}
	c5 := geo.Coord{Lat: 0.0, Lon: 1.00}
	cD := geo.Coord{Lat: 1.0, Lon: 0.50} // detour node far north

	for id, coord := range map[int64]geo.Coord{1: c1, 2: c2, 3: c3, 4: c4, 5: c5, 6: cD} {
		net.AddNode(graph.Node{ID: graph.NodeID(id), Coord: coord})
	}

	// Cheap path: 1->2->3->4->5
	mustAddEdge(t, net, edgeSpec{from: 1, to: 2, weight: geo.DistanceMeters(c1, c2)})
	mustAddEdge(t, net, edgeSpec{from: 2, to: 3, weight: geo.DistanceMeters(c2, c3)})
	mustAddEdge(t, net, edgeSpec{from: 3, to: 4, weight: geo.DistanceMeters(c3, c4)})
	mustAddEdge(t, net, edgeSpec{from: 4, to: 5, weight: geo.DistanceMeters(c4, c5)})
	// Expensive detour: 1->6->5 (penalised weight so it's never optimal)
	mustAddEdge(t, net, edgeSpec{from: 1, to: 6, weight: geo.DistanceMeters(c1, cD) * 10})
	mustAddEdge(t, net, edgeSpec{from: 6, to: 5, weight: geo.DistanceMeters(cD, c5) * 10})

	dijkResult, err := Dijkstra(net, graph.NodeID(1), graph.NodeID(5))
	if err != nil {
		t.Fatalf("Dijkstra error: %v", err)
	}
	astarResult, err := AStar(net, graph.NodeID(1), graph.NodeID(5))
	if err != nil {
		t.Fatalf("A* error: %v", err)
	}

	// Both algorithms must find the same optimal path.
	assertPathEquals(t, astarResult.Path, dijkResult.Path)

	// A* must settle no more nodes than Dijkstra.
	if len(astarResult.VisitedNodes) > len(dijkResult.VisitedNodes) {
		t.Errorf(
			"A* settled %d nodes vs Dijkstra's %d — A* should never visit more nodes on admissible heuristic",
			len(astarResult.VisitedNodes), len(dijkResult.VisitedNodes),
		)
	}
}
