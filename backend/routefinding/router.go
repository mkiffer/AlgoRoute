package routefinding

import "algoroute/graph"

// Router finds the shortest path between two nodes in a network.
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
