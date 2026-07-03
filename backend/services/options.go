package services

import (
	"algoroute/graph"
	"algoroute/mapping"
)

const (
	AlgorithmDijkstra             = "dijkstra"
	AlgorithmAStar                = "astar"
	AlgorithmGreedyBestFirst      = "greedy"
	AlgorithmBidirectionalDijkstra = "bidijkstra"
)

// RouteRequest describes the inputs for a routing operation.
type RouteRequest struct {
	DataFile  string // path to OSM JSON file
	StartNode graph.NodeID
	GoalNode  graph.NodeID
	Algorithm string // AlgorithmDijkstra or AlgorithmAStar
	MapOpts   mapping.BuildOptions
}
