package routefinding

import (
	"container/heap"
	"fmt"
	"math"

	"algoroute/graph"
)

// priorityQueue implements heap.Interface as a binary min-heap ordered by cost.
//
// A binary min-heap is used so that popping the lowest-cost node costs O(log n)
// rather than O(n) for a linear scan. This matters because Dijkstra performs one
// pop per settled node and up to one push per edge relaxation.
//
// Go's container/heap does not support decrease-key, so we use lazy deletion
// instead: when a node is relaxed we push a new entry rather than updating the
// existing one. Stale entries (those whose stored cost is higher than the current
// best) are discarded when popped. This trades a modest increase in heap size for
// a much simpler implementation than a Fibonacci heap or an indexed heap with
// decrease-key.
type heapEntry struct {
	node graph.NodeID
	cost float64
	idx  int
}

type priorityQueue []*heapEntry

func (pq priorityQueue) Len() int           { return len(pq) }
func (pq priorityQueue) Less(i, j int) bool { return pq[i].cost < pq[j].cost }
func (pq priorityQueue) Swap(i, j int) {
	pq[i], pq[j] = pq[j], pq[i]
	pq[i].idx = i
	pq[j].idx = j
}
func (pq *priorityQueue) Push(x any) {
	entry := x.(*heapEntry)
	entry.idx = len(*pq)
	*pq = append(*pq, entry)
}
func (pq *priorityQueue) Pop() any {
	old := *pq
	n := len(old)
	entry := old[n-1]
	old[n-1] = nil
	*pq = old[:n-1]
	return entry
}

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

	openSet := &priorityQueue{{node: start, cost: 0}}
	heap.Init(openSet)

	// visitedOrder records nodes in the order they are settled (finalized). A node
	// is settled when it is popped from the heap and its stored cost matches the
	// current best known cost — meaning no cheaper path to it will be found later.
	// This ordering drives the traversal animation on the frontend.
	var visitedOrder []graph.NodeID

	for openSet.Len() > 0 {
		currentEntry := heap.Pop(openSet).(*heapEntry)

		// Lazy-deletion stale check: skip entries pushed before a cheaper path
		// to this node was found. Without this, we would re-expand the node and
		// redundantly relax its neighbours using a suboptimal cost.
		if currentEntry.cost > bestKnownCostTo[currentEntry.node] {
			continue
		}

		// Record settlement before the early-exit so the goal appears in
		// visitedOrder even though we break immediately after.
		visitedOrder = append(visitedOrder, currentEntry.node)

		if currentEntry.node == goal {
			break
		}

		for _, edge := range net.Neighbours(currentEntry.node) {
			newCost := bestKnownCostTo[currentEntry.node] + edge.Weight
			if newCost < bestKnownCostTo[edge.To] {
				bestKnownCostTo[edge.To] = newCost
				arrivedViaNode[edge.To] = currentEntry.node
				heap.Push(openSet, &heapEntry{node: edge.To, cost: newCost})
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
