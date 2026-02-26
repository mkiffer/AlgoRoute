package services

import (
	"fmt"

	"algoroute/api/overpass"
	"algoroute/graph"
	"algoroute/mapping"
)

// LoadNetworkFromFile reads an OSM JSON file and builds a routing network.
func LoadNetworkFromFile(path string, opts mapping.BuildOptions) (*graph.Network, error) {
	resp, err := overpass.LoadNetworkFromJSON(path)
	if err != nil {
		return nil, fmt.Errorf("load network from file %q: %w", path, err)
	}
	net, _, err := mapping.BuildNetwork(resp, opts)
	if err != nil {
		return nil, fmt.Errorf("build network: %w", err)
	}
	return net, nil
}
