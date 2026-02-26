package routefinding

import "algoroute/graph"

// Router finds the shortest path between two nodes in a network.
//
// This is the Strategy pattern: the algorithm is chosen once at construction
// (in NewRoutingService) and stored as a Router, so the service's Route method
// calls through the interface without any per-call branching.
//
// The alternative — a switch on an algorithm name inside RoutingService.Route —
// was rejected because it would couple the service to every algorithm by name,
// requiring a change to the service each time a new algorithm is added.
type Router interface {
	Route(net *graph.Network, start, goal graph.NodeID) ([]graph.NodeID, float64, error)
}

// DijkstraRouter implements Router using Dijkstra's algorithm.
type DijkstraRouter struct{}

func (DijkstraRouter) Route(net *graph.Network, start, goal graph.NodeID) ([]graph.NodeID, float64, error) {
	return Dijkstra(net, start, goal)
}

// AStarRouter implements Router using the A* algorithm.
type AStarRouter struct{}

func (AStarRouter) Route(net *graph.Network, start, goal graph.NodeID) ([]graph.NodeID, float64, error) {
	return AStar(net, start, goal)
}
