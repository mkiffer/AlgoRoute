package services

import "algoroute/graph"

// RouteResult holds the output of a routing operation.
type RouteResult struct {
	Path      []graph.NodeID
	Distance  float64 // total distance in meters
	Algorithm string
}
