package routefinding

import (
	"fmt"
	"math"

	"algoroute/geo"
	"algoroute/graph"
)

// GreedyBestFirst returns a path from start to goal by always expanding the
// node geographically closest to the goal (pure heuristic, no path-cost term).
//
// This is identical to A* except the heap priority is h(n) alone rather than
// g(n)+h(n). The resulting path is often suboptimal: the algorithm sprints
// toward the goal along whatever corridor looks shortest in straight-line
// distance, ignoring actual edge weights. Comparing its animation to A* makes
// the cost of discarding the path-cost term immediately visible.
//
// The returned Distance is the true edge-weight sum of the path found, not the
// heuristic value — so callers can directly observe how far the result deviates
// from the Dijkstra optimum.
func GreedyBestFirst(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
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

	// bestKnownCostTo tracks actual path cost for accurate Distance reporting
	// and to drive arrivedViaNode updates when a cheaper actual path is found.
	bestKnownCostTo := make(map[graph.NodeID]float64, len(net.Nodes))
	arrivedViaNode := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	for id := range net.Nodes {
		bestKnownCostTo[id] = math.Inf(1)
	}
	bestKnownCostTo[start] = 0

	openSet := newIndexedHeap()
	openSet.Push(start, estimateCostToGoal(start))

	var visitedOrder []graph.NodeID

	for openSet.Len() > 0 {
		current := openSet.Pop()

		visitedOrder = append(visitedOrder, current.node)

		if current.node == goal {
			break
		}

		for _, edge := range net.Neighbours(current.node) {
			tentativeCostToReach := bestKnownCostTo[current.node] + edge.Weight
			if tentativeCostToReach < bestKnownCostTo[edge.To] {
				bestKnownCostTo[edge.To] = tentativeCostToReach
				arrivedViaNode[edge.To] = current.node

				// Key difference from A*: priority = h(n) only, no g-cost.
				// This causes greedy to expand toward the goal geographically
				// even when the actual path cost to get there is enormous.
				heuristic := estimateCostToGoal(edge.To)
				if openSet.Contains(edge.To) {
					openSet.DecreasePriority(edge.To, heuristic)
				} else {
					openSet.Push(edge.To, heuristic)
				}
			}
		}
	}

	if math.IsInf(bestKnownCostTo[goal], 1) {
		return RouteResult{}, fmt.Errorf("greedy: no path from %v to %v", start, goal)
	}

	var path []graph.NodeID
	for current := goal; current != start; current = arrivedViaNode[current] {
		path = append(path, current)
	}
	path = append(path, start)

	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}

	return RouteResult{
		Path:         path,
		Distance:     bestKnownCostTo[goal],
		VisitedNodes: visitedOrder,
	}, nil
}
