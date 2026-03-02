package routefinding

import (
	"fmt"
	"math"

	"algoroute/geo"
	"algoroute/graph"
)

// AStar returns the shortest path, its cost, and the list of settled nodes
// from start to goal using the A* algorithm with Haversine distance as the heuristic.
func AStar(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	if start == goal {
		return RouteResult{
			Path:         []graph.NodeID{start},
			Distance:     0,
			VisitedNodes: []graph.NodeID{start},
		}, nil
	}

	goalCoord := net.Nodes[goal].Coord
	estimateCostToGoal := func(nodeID graph.NodeID) float64 {
		return geo.DistanceMeters(net.Nodes[nodeID].Coord, goalCoord)
	}

	bestKnownCostTo := make(map[graph.NodeID]float64, len(net.Nodes))
	arrivedViaNode := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	for id := range net.Nodes {
		bestKnownCostTo[id] = math.Inf(1)
	}
	bestKnownCostTo[start] = 0

	openSet := newIndexedHeap()
	openSet.Push(start, estimateCostToGoal(start))

	// visitedOrder records nodes in the order they are settled — same semantics as
	// Dijkstra, but A*'s heuristic causes the frontier to expand toward the goal
	// rather than radially, so this slice will typically be shorter than Dijkstra's.
	var visitedOrder []graph.NodeID

	for openSet.Len() > 0 {
		current := openSet.Pop()

		// Record settlement before the early-exit so the goal appears in
		// visitedOrder even though we break immediately after.
		visitedOrder = append(visitedOrder, current.node)

		if current.node == goal {
			break
		}

		for _, edge := range net.Neighbours(current.node) {
			tentativeCostToReach := bestKnownCostTo[current.node] + edge.Weight
			if tentativeCostToReach < bestKnownCostTo[edge.To] {
				bestKnownCostTo[edge.To] = tentativeCostToReach
				arrivedViaNode[edge.To] = current.node
				fCost := tentativeCostToReach + estimateCostToGoal(edge.To)
				if openSet.Contains(edge.To) {
					openSet.DecreasePriority(edge.To, fCost)
				} else {
					openSet.Push(edge.To, fCost)
				}
			}
		}
	}

	if math.IsInf(bestKnownCostTo[goal], 1) {
		return RouteResult{}, fmt.Errorf("astar: no path from %v to %v", start, goal)
	}

	// Reconstruct path by walking arrivedViaNode map backwards.
	var path []graph.NodeID
	for current := goal; current != start; current = arrivedViaNode[current] {
		path = append(path, current)
	}
	path = append(path, start)

	// Reverse in-place.
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}

	return RouteResult{
		Path:         path,
		Distance:     bestKnownCostTo[goal],
		VisitedNodes: visitedOrder,
	}, nil
}
