/*
Tests for: services — routing orchestration.
Coverage intent: NewRoutingService (valid and invalid algorithms),
                 RoutingService.Route (both algorithms, missing file),
                 LoadNetworkFromFile (valid file, missing file).
Not covered here: concurrent use; performance on large networks.

Test fixture: testdata/sample_overpass.json
  Contains nodes 1001, 1002, 1003 connected in a line: 1001→1002→1003.
  All tests that call Route use AssumeBidirectional: true.
*/
package services_test

import (
	"path/filepath"
	"testing"

	"algoroute/graph"
	"algoroute/mapping"
	"algoroute/services"
)

const fixtureFile = "testdata/sample_overpass.json"

var bidirectionalOpts = mapping.BuildOptions{AssumeBidirectional: true}

// --- NewRoutingService ---

func TestNewRoutingService_Dijkstra_ReturnsService(t *testing.T) {
	service, err := services.NewRoutingService(services.AlgorithmDijkstra)

	if err != nil {
		t.Fatalf("NewRoutingService(AlgorithmDijkstra): unexpected error: %v", err)
	}
	if service == nil {
		t.Errorf("NewRoutingService(AlgorithmDijkstra): expected non-nil service, got nil")
	}
}

func TestNewRoutingService_AStar_ReturnsService(t *testing.T) {
	service, err := services.NewRoutingService(services.AlgorithmAStar)

	if err != nil {
		t.Fatalf("NewRoutingService(AlgorithmAStar): unexpected error: %v", err)
	}
	if service == nil {
		t.Errorf("NewRoutingService(AlgorithmAStar): expected non-nil service, got nil")
	}
}

func TestNewRoutingService_UnknownAlgorithm_ReturnsError(t *testing.T) {
	// Unsupported algorithm names must produce a descriptive error rather
	// than silently returning a nil service or panicking at route time.
	service, err := services.NewRoutingService("bellman-ford")

	if err == nil {
		t.Errorf("NewRoutingService(unknown): expected error, got nil (service=%v)", service)
	}
}

// --- RoutingService.Route ---

func TestRoute_Dijkstra_FindsPathBetweenFixtureNodes(t *testing.T) {
	service, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.RouteRequest{
		DataFile:  filepath.Join("testdata", "sample_overpass.json"),
		StartNode: graph.NodeID(1001),
		GoalNode:  graph.NodeID(1003),
		Algorithm: services.AlgorithmDijkstra,
		MapOpts:   bidirectionalOpts,
	}

	result, err := service.Route(request)

	if err != nil {
		t.Fatalf("Route: %v", err)
	}
	if len(result.Path) == 0 {
		t.Errorf("Route: expected non-empty path, got []")
	}
	if result.Path[0] != graph.NodeID(1001) {
		t.Errorf("Route: path[0] = %v, want 1001", result.Path[0])
	}
	if result.Path[len(result.Path)-1] != graph.NodeID(1003) {
		t.Errorf("Route: path[-1] = %v, want 1003", result.Path[len(result.Path)-1])
	}
	if result.Distance <= 0 {
		t.Errorf("Route: distance = %v, want > 0", result.Distance)
	}
	if result.Algorithm != services.AlgorithmDijkstra {
		t.Errorf("Route: algorithm = %q, want %q", result.Algorithm, services.AlgorithmDijkstra)
	}
}

func TestRoute_AStar_FindsPathBetweenFixtureNodes(t *testing.T) {
	// A* must produce the same start/end as Dijkstra on this network.
	// Algorithm correctness is covered in routefinding/; this test verifies
	// the service wires the algorithm through end-to-end correctly.
	service, _ := services.NewRoutingService(services.AlgorithmAStar)
	request := services.RouteRequest{
		DataFile:  filepath.Join("testdata", "sample_overpass.json"),
		StartNode: graph.NodeID(1001),
		GoalNode:  graph.NodeID(1003),
		Algorithm: services.AlgorithmAStar,
		MapOpts:   bidirectionalOpts,
	}

	result, err := service.Route(request)

	if err != nil {
		t.Fatalf("Route: %v", err)
	}
	if result.Path[0] != graph.NodeID(1001) || result.Path[len(result.Path)-1] != graph.NodeID(1003) {
		t.Errorf("Route: expected path 1001→…→1003, got %v", result.Path)
	}
	if result.Algorithm != services.AlgorithmAStar {
		t.Errorf("Route: algorithm = %q, want %q", result.Algorithm, services.AlgorithmAStar)
	}
}

func TestRoute_MissingDataFile_ReturnsError(t *testing.T) {
	service, _ := services.NewRoutingService(services.AlgorithmDijkstra)
	request := services.RouteRequest{
		DataFile:  "nonexistent.json",
		StartNode: graph.NodeID(1),
		GoalNode:  graph.NodeID(2),
		MapOpts:   mapping.BuildOptions{},
	}

	_, err := service.Route(request)

	if err == nil {
		t.Errorf("Route with missing file: expected error, got nil")
	}
}

// --- LoadNetworkFromFile ---

func TestLoadNetworkFromFile_ValidFile_ReturnsPopulatedNetwork(t *testing.T) {
	network, err := services.LoadNetworkFromFile(fixtureFile, bidirectionalOpts)

	if err != nil {
		t.Fatalf("LoadNetworkFromFile: %v", err)
	}
	if len(network.Nodes) == 0 {
		t.Errorf("LoadNetworkFromFile: expected nodes in network, got 0")
	}
}

func TestLoadNetworkFromFile_MissingFile_ReturnsError(t *testing.T) {
	_, err := services.LoadNetworkFromFile("nonexistent.json", mapping.BuildOptions{})

	if err == nil {
		t.Errorf("LoadNetworkFromFile with missing file: expected error, got nil")
	}
}
