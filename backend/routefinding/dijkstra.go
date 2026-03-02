package routefinding

import (
	"fmt"
	"math"

	"algoroute/graph"
)

// Dijkstra returns the shortest path, its cost, and the list of settled nodes
// from start to goal.
func Dijkstra(
	net *graph.Network,
	start graph.NodeID,
	goal graph.NodeID,
) (RouteResult, error) {
	if start == goal {
		return RouteResult{
			Path:         []graph.NodeID{start},
			Distance:     0,
			VisitedNodes: []graph.NodeID{start},
		}, nil
	}

	bestKnownCostTo := make(map[graph.NodeID]float64, len(net.Nodes))
	arrivedViaNode := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	for id := range net.Nodes {
		bestKnownCostTo[id] = math.Inf(1)
	}
	bestKnownCostTo[start] = 0

	openSet := newIndexedHeap()
	openSet.Push(start, 0)

	// visitedOrder records nodes in the order they are settled (finalized). A node
	// is settled when it is popped from the heap — with an indexed heap every pop
	// is guaranteed to carry the optimal cost, so no stale-check is needed.
	// This ordering drives the traversal animation on the frontend.
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
			newCost := bestKnownCostTo[current.node] + edge.Weight
			if newCost < bestKnownCostTo[edge.To] {
				bestKnownCostTo[edge.To] = newCost
				arrivedViaNode[edge.To] = current.node
				if openSet.Contains(edge.To) {
					openSet.DecreasePriority(edge.To, newCost)
				} else {
					openSet.Push(edge.To, newCost)
				}
			}
		}
	}

	if math.IsInf(bestKnownCostTo[goal], 1) {
		return RouteResult{}, fmt.Errorf("dijkstra: no path from %v to %v", start, goal)
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
