package services

import (
	"fmt"

	"algoroute/routefinding"
)

// RoutingService orchestrates network loading and route finding.
type RoutingService struct {
	router       routefinding.Router
	algorithm    string
	networkCache *NetworkCache // nil means no caching — every request hits Overpass
}

// NewRoutingService returns a RoutingService configured for the named algorithm.
// Valid values are AlgorithmDijkstra and AlgorithmAStar.
func NewRoutingService(algorithm string) (*RoutingService, error) {
	var router routefinding.Router
	switch algorithm {
	case AlgorithmDijkstra:
		router = routefinding.DijkstraRouter{}
	case AlgorithmAStar:
		router = routefinding.AStarRouter{}
	default:
		return nil, fmt.Errorf("unknown algorithm %q: use %q or %q", algorithm, AlgorithmDijkstra, AlgorithmAStar)
	}
	return &RoutingService{router: router, algorithm: algorithm}, nil
}

// NewRoutingServiceWithCache returns a RoutingService that uses the provided
// NetworkCache to skip Overpass fetches when the same bounding box has already
// been queried. Pass NewNetworkCache() for a fresh cache, or a shared instance
// to have multiple RoutingService objects benefit from the same cache.
func NewRoutingServiceWithCache(algorithm string, cache *NetworkCache) (*RoutingService, error) {
	svc, err := NewRoutingService(algorithm)
	if err != nil {
		return nil, err
	}
	svc.networkCache = cache
	return svc, nil
}

// Route loads the road network from req.DataFile and finds the shortest path.
func (s *RoutingService) Route(req RouteRequest) (RouteResult, error) {
	net, err := LoadNetworkFromFile(req.DataFile, req.MapOpts)
	if err != nil {
		return RouteResult{}, err
	}

	routeResult, err := s.router.Route(net, req.StartNode, req.GoalNode)
	if err != nil {
		return RouteResult{}, fmt.Errorf("route: %w", err)
	}

	return RouteResult{
		Path:      routeResult.Path,
		Distance:  routeResult.Distance,
		Algorithm: s.algorithm,
	}, nil
}
