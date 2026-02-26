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
	h := func(n graph.NodeID) float64 {
		return geo.DistanceMeters(net.Nodes[n].Coord, goalCoord)
	}

	dist := make(map[graph.NodeID]float64, len(net.Nodes))
	prev := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	for id := range net.Nodes {
		dist[id] = math.Inf(1)
	}
	dist[start] = 0

	pq := &priorityQueue{{node: start, cost: h(start)}}
	heap.Init(pq)

	for pq.Len() > 0 {
		cur := heap.Pop(pq).(*pqItem)

		// Stale-entry check: f stored in cur.cost vs current best f for this node.
		if cur.cost > dist[cur.node]+h(cur.node) {
			continue
		}
		if cur.node == goal {
			break
		}

		for _, edge := range net.Neighbours(cur.node) {
			newG := dist[cur.node] + edge.Weight
			if newG < dist[edge.To] {
				dist[edge.To] = newG
				prev[edge.To] = cur.node
				heap.Push(pq, &pqItem{node: edge.To, cost: newG + h(edge.To)})
			}
		}
	}

	if math.IsInf(dist[goal], 1) {
		return nil, 0, fmt.Errorf("astar: no path from %v to %v", start, goal)
	}

	// Reconstruct path by walking prev map backwards.
	var path []graph.NodeID
	for n := goal; n != start; n = prev[n] {
		path = append(path, n)
	}
	path = append(path, start)

	// Reverse in-place.
	for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 {
		path[i], path[j] = path[j], path[i]
	}

	return path, dist[goal], nil
}
