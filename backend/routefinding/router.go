package routefinding

import "algoroute/graph"

// RouteResult bundles the output of a routing algorithm into a single value.
//
// Returning a struct rather than multiple positional returns allows new fields
// (such as VisitedNodes) to be added without changing every call site that
// already destructures the result.
type RouteResult struct {
	// Path is the ordered list of node IDs from start to goal.
	Path []graph.NodeID

	// Distance is the total edge-weight cost of the path (metres for real OSM data).
	Distance float64

	// VisitedNodes is the ordered list of nodes that were settled (popped from the
	// priority queue and confirmed optimal) during the search. The first entry is
	// always the start node; the last is the goal node. This slice drives the
	// traversal animation on the frontend — it shows the search frontier expanding
	// before the optimal path is revealed.
	VisitedNodes []graph.NodeID
}

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
	Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error)
}

// DijkstraRouter implements Router using Dijkstra's algorithm.
type DijkstraRouter struct{}

func (DijkstraRouter) Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	return Dijkstra(net, start, goal)
}

// AStarRouter implements Router using the A* algorithm.
type AStarRouter struct{}

func (AStarRouter) Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	return AStar(net, start, goal)
}

// GreedyBestFirstRouter implements Router using the Greedy Best-First algorithm.
type GreedyBestFirstRouter struct{}

func (GreedyBestFirstRouter) Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	return GreedyBestFirst(net, start, goal)
}

// BidirectionalDijkstraRouter implements Router using Bidirectional Dijkstra.
type BidirectionalDijkstraRouter struct{}

func (BidirectionalDijkstraRouter) Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	return BidirectionalDijkstra(net, start, goal)
}
