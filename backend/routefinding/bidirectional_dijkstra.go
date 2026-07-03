package routefinding

import (
	"fmt"
	"math"

	"algoroute/graph"
)

// BidirectionalDijkstra finds the shortest path from start to goal by running
// two simultaneous Dijkstra searches — one forward from start, one backward
// from goal — and terminating when their frontiers can no longer improve the
// best complete path found so far.
//
// On graphs where the search radius from each endpoint covers roughly half the
// total distance, bidirectional visits significantly fewer nodes than a one-
// directional search. The animation makes this visible: two expanding rings
// grow toward each other and stop when they meet in the middle.
func BidirectionalDijkstra(net *graph.Network, start, goal graph.NodeID) (RouteResult, error) {
	if start == goal {
		return RouteResult{
			Path:         []graph.NodeID{start},
			Distance:     0,
			VisitedNodes: []graph.NodeID{start},
		}, nil
	}

	// Build a reverse adjacency list so the backward search can traverse
	// incoming edges from the goal side. For each original edge u→v, we add
	// a reverse edge v→u with the same weight.
	reverseAdj := make(map[graph.NodeID][]graph.Edge, len(net.Nodes))
	for nodeID, edges := range net.AdjacencyList {
		for _, edge := range edges {
			reverseAdj[edge.To] = append(reverseAdj[edge.To], graph.Edge{
				From:   edge.To,
				To:     nodeID,
				Weight: edge.Weight,
			})
		}
	}

	// Initialise forward and backward cost maps.
	fwdCost := make(map[graph.NodeID]float64, len(net.Nodes))
	bwdCost := make(map[graph.NodeID]float64, len(net.Nodes))
	for id := range net.Nodes {
		fwdCost[id] = math.Inf(1)
		bwdCost[id] = math.Inf(1)
	}
	fwdCost[start] = 0
	bwdCost[goal] = 0

	fwdPrev := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	bwdPrev := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))

	fwdSettled := make(map[graph.NodeID]bool, len(net.Nodes))
	bwdSettled := make(map[graph.NodeID]bool, len(net.Nodes))

	fwdHeap := newIndexedHeap()
	bwdHeap := newIndexedHeap()
	fwdHeap.Push(start, 0)
	bwdHeap.Push(goal, 0)

	// mu is the cost of the best complete start→goal path found so far.
	// meetingNode is the node through which that path passes.
	mu := math.Inf(1)
	meetingNode := graph.NodeID(-1)

	// visitedOrder records nodes in order of settlement from both frontiers.
	// Interleaving the two sequences gives the two-pronged animation effect.
	var visitedOrder []graph.NodeID

	updateMu := func(node graph.NodeID) {
		if !math.IsInf(fwdCost[node], 1) && !math.IsInf(bwdCost[node], 1) {
			if total := fwdCost[node] + bwdCost[node]; total < mu {
				mu = total
				meetingNode = node
			}
		}
	}

	for fwdHeap.Len() > 0 && bwdHeap.Len() > 0 {
		// Termination: no unsettled node can yield a path cheaper than mu.
		if fwdHeap.entries[0].priority+bwdHeap.entries[0].priority >= mu {
			break
		}

		// Always expand the side with the lower-priority heap top.
		if fwdHeap.entries[0].priority <= bwdHeap.entries[0].priority {
			curr := fwdHeap.Pop()
			fwdSettled[curr.node] = true
			visitedOrder = append(visitedOrder, curr.node)

			// This node may already be settled on the backward side.
			if bwdSettled[curr.node] {
				updateMu(curr.node)
			}

			for _, edge := range net.Neighbours(curr.node) {
				newCost := fwdCost[curr.node] + edge.Weight
				if newCost < fwdCost[edge.To] {
					fwdCost[edge.To] = newCost
					fwdPrev[edge.To] = curr.node
					// If backward already settled this neighbour, a complete
					// path through it is now known — update mu.
					if bwdSettled[edge.To] {
						updateMu(edge.To)
					}
					if fwdHeap.Contains(edge.To) {
						fwdHeap.DecreasePriority(edge.To, newCost)
					} else {
						fwdHeap.Push(edge.To, newCost)
					}
				}
			}
		} else {
			curr := bwdHeap.Pop()
			bwdSettled[curr.node] = true
			visitedOrder = append(visitedOrder, curr.node)

			if fwdSettled[curr.node] {
				updateMu(curr.node)
			}

			for _, edge := range reverseAdj[curr.node] {
				// edge.To is the predecessor in the original graph.
				// bwdPrev[edge.To] = curr.node encodes "from edge.To, the
				// next hop toward goal in the original graph is curr.node"
				// because the original edge edge.To→curr.node exists.
				newCost := bwdCost[curr.node] + edge.Weight
				if newCost < bwdCost[edge.To] {
					bwdCost[edge.To] = newCost
					bwdPrev[edge.To] = curr.node
					if fwdSettled[edge.To] {
						updateMu(edge.To)
					}
					if bwdHeap.Contains(edge.To) {
						bwdHeap.DecreasePriority(edge.To, newCost)
					} else {
						bwdHeap.Push(edge.To, newCost)
					}
				}
			}
		}
	}

	if math.IsInf(mu, 1) {
		return RouteResult{}, fmt.Errorf("bidijkstra: no path from %v to %v", start, goal)
	}

	path := reconstructBiPath(fwdPrev, bwdPrev, start, goal, meetingNode)

	return RouteResult{
		Path:         path,
		Distance:     mu,
		VisitedNodes: visitedOrder,
	}, nil
}

// reconstructBiPath assembles the full path through meetingNode by combining
// the forward and backward predecessor maps.
//
// Forward half: walk fwdPrev backwards from meetingNode to start, then reverse.
// Backward half: walk bwdPrev from meetingNode to goal (bwdPrev[X]=Y encodes
// the original edge X→Y, so each step is already in the correct direction).
// The two halves are concatenated with the duplicate meetingNode dropped.
func reconstructBiPath(
	fwdPrev map[graph.NodeID]graph.NodeID,
	bwdPrev map[graph.NodeID]graph.NodeID,
	start, goal, meetingNode graph.NodeID,
) []graph.NodeID {
	// Forward half: [start, …, meetingNode].
	var fwdHalf []graph.NodeID
	for n := meetingNode; n != start; n = fwdPrev[n] {
		fwdHalf = append(fwdHalf, n)
	}
	fwdHalf = append(fwdHalf, start)
	for i, j := 0, len(fwdHalf)-1; i < j; i, j = i+1, j-1 {
		fwdHalf[i], fwdHalf[j] = fwdHalf[j], fwdHalf[i]
	}

	// Backward half: [meetingNode, …, goal].
	// Skip the first element (meetingNode) to avoid duplication.
	var bwdHalf []graph.NodeID
	for n := meetingNode; n != goal; n = bwdPrev[n] {
		bwdHalf = append(bwdHalf, n)
	}
	bwdHalf = append(bwdHalf, goal)

	return append(fwdHalf, bwdHalf[1:]...)
}
