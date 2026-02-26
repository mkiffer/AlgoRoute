package routefinding

import (
	"container/heap"
	"fmt"
	"math"

	"algoroute/graph"
)

type pqItem struct {
	node graph.NodeID
	cost float64
	idx  int
}

type priorityQueue []*pqItem

func (pq priorityQueue) Len() int           { return len(pq) }
func (pq priorityQueue) Less(i, j int) bool { return pq[i].cost < pq[j].cost }
func (pq priorityQueue) Swap(i, j int) {
	pq[i], pq[j] = pq[j], pq[i]
	pq[i].idx = i
	pq[j].idx = j
}
func (pq *priorityQueue) Push(x any) {
	item := x.(*pqItem)
	item.idx = len(*pq)
	*pq = append(*pq, item)
}
func (pq *priorityQueue) Pop() any {
	old := *pq
	n := len(old)
	item := old[n-1]
	old[n-1] = nil
	*pq = old[:n-1]
	return item
}

// Dijkstra returns the shortest path and its cost from start to goal.
func Dijkstra(
	net *graph.Network,
	start graph.NodeID,
	goal graph.NodeID,
) ([]graph.NodeID, float64, error) {
	if start == goal {
		return []graph.NodeID{start}, 0, nil
	}

	dist := make(map[graph.NodeID]float64, len(net.Nodes))
	prev := make(map[graph.NodeID]graph.NodeID, len(net.Nodes))
	for id := range net.Nodes {
		dist[id] = math.Inf(1)
	}
	dist[start] = 0

	pq := &priorityQueue{{node: start, cost: 0}}
	heap.Init(pq)

	for pq.Len() > 0 {
		cur := heap.Pop(pq).(*pqItem)

		if cur.cost > dist[cur.node] {
			continue // stale entry
		}
		if cur.node == goal {
			break
		}

		for _, edge := range net.Neighbours(cur.node) {
			newCost := dist[cur.node] + edge.Weight
			if newCost < dist[edge.To] {
				dist[edge.To] = newCost
				prev[edge.To] = cur.node
				heap.Push(pq, &pqItem{node: edge.To, cost: newCost})
			}
		}
	}

	if math.IsInf(dist[goal], 1) {
		return nil, 0, fmt.Errorf("dijkstra: no path from %v to %v", start, goal)
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
