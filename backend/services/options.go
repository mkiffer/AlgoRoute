package services

import (
	"algoroute/graph"
	"algoroute/mapping"
)

// RouteRequest describes the inputs for a routing operation.
type RouteRequest struct {
	DataFile  string // path to OSM JSON file
	StartNode graph.NodeID
	GoalNode  graph.NodeID
	Algorithm string // "dijkstra" or "astar"
	MapOpts   mapping.BuildOptions
}
