package routefinding

import (
	"container/heap"
	"fmt"
	"math"

	"algoroute/geo"
	"algoroute/graph"
)

// AStar returns the shortest path and its cost from start to goal using the
// A* algorithm with Haversine distance as the heuristic.
func AStar(net *graph.Network, start, goal graph.NodeID) ([]graph.NodeID, float64, error) {
	if start == goal {
		return []graph.NodeID{start}, 0, nil
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

	openSet := &priorityQueue{{node: start, cost: estimateCostToGoal(start)}}
	heap.Init(openSet)

	for openSet.Len() > 0 {
		currentEntry := heap.Pop(openSet).(*heapEntry)

		// Lazy-deletion stale check: heapEntry.cost stores f = g + h at push time.
		// We compare it against the current best f (recomputed from the latest g)
		// rather than against g directly, because g is not stored in the entry —
		// only f is. An alternative would be to add a gCost field to heapEntry, but
		// that would require modifying the struct shared with Dijkstra. Entries where
		// a cheaper g (and therefore cheaper f) was found since the push are discarded.
		if currentEntry.cost > bestKnownCostTo[currentEntry.node]+estimateCostToGoal(currentEntry.node) {
			continue
		}
		if currentEntry.node == goal {
			break
		}

		for _, edge := range net.Neighbours(currentEntry.node) {
			tentativeCostToReach := bestKnownCostTo[currentEntry.node] + edge.Weight
			if tentativeCostToReach < bestKnownCostTo[edge.To] {
				bestKnownCostTo[edge.To] = tentativeCostToReach
				arrivedViaNode[edge.To] = currentEntry.node
				heap.Push(openSet, &heapEntry{node: edge.To, cost: tentativeCostToReach + estimateCostToGoal(edge.To)})
			}
		}
	}

	if math.IsInf(bestKnownCostTo[goal], 1) {
		return nil, 0, fmt.Errorf("astar: no path from %v to %v", start, goal)
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

	return path, bestKnownCostTo[goal], nil
}
