package services

import (
	"fmt"

	"algoroute/routefinding"
)

// RoutingService orchestrates network loading and route finding.
type RoutingService struct {
	router    routefinding.Router
	algorithm string
}

// NewRoutingService returns a RoutingService configured for the named algorithm.
// Valid values for algorithm are "dijkstra" and "astar".
func NewRoutingService(algorithm string) (*RoutingService, error) {
	var router routefinding.Router
	switch algorithm {
	case "dijkstra":
		router = routefinding.DijkstraRouter{}
	case "astar":
		router = routefinding.AStarRouter{}
	default:
		return nil, fmt.Errorf("unknown algorithm %q: use \"dijkstra\" or \"astar\"", algorithm)
	}
	return &RoutingService{router: router, algorithm: algorithm}, nil
}

// Route loads the road network from req.DataFile and finds the shortest path.
func (s *RoutingService) Route(req RouteRequest) (RouteResult, error) {
	net, err := LoadNetworkFromFile(req.DataFile, req.MapOpts)
	if err != nil {
		return RouteResult{}, err
	}

	path, dist, err := s.router.Route(net, req.StartNode, req.GoalNode)
	if err != nil {
		return RouteResult{}, fmt.Errorf("route: %w", err)
	}

	return RouteResult{
		Path:      path,
		Distance:  dist,
		Algorithm: s.algorithm,
	}, nil
}
