package graph

import (
	"fmt"
	"math"

	"algoroute/geo"
)

// NearestNode returns the NodeID of the node in net whose coordinate is
// closest to target, measured by Haversine distance.
//
// This is used to snap a geocoded coordinate (which rarely falls exactly on a
// graph node) to the nearest node before running a routing algorithm.
//
// Time complexity: O(n) linear scan — sufficient for city-scale networks where
// n is typically in the tens of thousands. A spatial index (e.g. k-d tree)
// would be needed only for continent-scale graphs or real-time snapping under
// heavy load.
//
// Returns an error if the network contains no nodes, because there is no
// meaningful snap target — returning a zero NodeID would silently corrupt
// downstream routing calls.
func NearestNode(net *Network, target geo.Coord) (NodeID, error) {
	if len(net.Nodes) == 0 {
		return 0, fmt.Errorf("nearest node: network has no nodes")
	}

	var nearestID NodeID
	shortestDistance := math.Inf(1)

	for nodeID, node := range net.Nodes {
		distanceToNode := geo.DistanceMeters(target, node.Coord)
		if distanceToNode < shortestDistance {
			shortestDistance = distanceToNode
			nearestID = nodeID
		}
	}

	return nearestID, nil
}
