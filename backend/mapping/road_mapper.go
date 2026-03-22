package mapping

import (
	"algoroute/api/overpass"
	"algoroute/geo"
	"algoroute/graph"
)

type BuildOptions struct {
	AssumeBidirectional bool

	AllowedHighwayTypes map[string]bool

	SkipWaysWithMissingNodes bool
}

type BuildStats struct {
	WayCount        int
	NodeCount       int
	EdgeCount       int
	SkippedWays     int
	MissingNodeRefs int
	NonRoutableWays int // eg no highway tag
}

func BuildNetwork(response overpass.Response, options BuildOptions) (*graph.Network, BuildStats, error) {
	net := graph.NewNetwork()
	var stats BuildStats

	for _, way := range response.Ways {
		stats.WayCount++

		for i, nodeID := range way.Nodes {
			// OSM ways are flat node-ID lists; edges are consecutive pairs [i-1, i].
			// Skip index 0 because there is no predecessor to form an edge from.
			if i == 0 {
				continue
			}

			fromID := way.Nodes[i-1]
			respFromNode, exists := response.NodeByID[fromID]
			if !exists || respFromNode.Lat == nil || respFromNode.Lon == nil {
				stats.MissingNodeRefs++
				break
			}

			fromNode := graph.Node{
				ID:    graph.NodeID(fromID),
				Coord: geo.Coord{Lat: *respFromNode.Lat, Lon: *respFromNode.Lon},
			}
			net.AddNode(fromNode)

			respToNode, exists := response.NodeByID[nodeID]
			if !exists || respToNode.Lat == nil || respToNode.Lon == nil {
				stats.MissingNodeRefs++
				break
			}

			toNode := graph.Node{
				ID:    graph.NodeID(nodeID),
				Coord: geo.Coord{Lat: *respToNode.Lat, Lon: *respToNode.Lon},
			}
			net.AddNode(toNode)

			distance := geo.DistanceMeters(fromNode.Coord, toNode.Coord)

			// Use the Tag() helper rather than direct map access so a nil Tags
			// map is handled explicitly and the intent is self-documenting.
			wayName, _ := way.Tag("name")

			// Parse the OSM oneway tag to determine which direction(s) are legal.
			// Tag reference: https://wiki.openstreetmap.org/wiki/Key:oneway
			onewayTag, _ := way.Tag("oneway")

			if !isReverseOnlyOneWay(onewayTag) {
				forwardEdge := graph.Edge{
					From:   fromNode.ID,
					To:     toNode.ID,
					Weight: distance,
					WayID:  way.Id,
					Name:   wayName,
				}
				if err := net.AddEdge(forwardEdge); err != nil {
					return nil, stats, err
				}
				stats.EdgeCount++
			}

			// Add the backward edge based on the oneway tag. Precedence:
			//   oneway=yes/1/true   → no backward edge (one-way forward only)
			//   oneway=-1/reverse   → backward edge only (reverse-only way)
			//   oneway=no/0/false   → backward edge (explicitly bidirectional)
			//   no oneway tag       → backward edge iff AssumeBidirectional=true
			shouldAddBackward := !isForwardOnlyOneWay(onewayTag) &&
				(isReverseOnlyOneWay(onewayTag) ||
					isExplicitlyBidirectional(onewayTag) ||
					(options.AssumeBidirectional && onewayTag == ""))
			if shouldAddBackward {
				backwardEdge := graph.Edge{
					From:   toNode.ID,
					To:     fromNode.ID,
					Weight: distance,
					WayID:  way.Id,
					Name:   wayName,
				}
				if err := net.AddEdge(backwardEdge); err != nil {
					return nil, stats, err
				}
				stats.EdgeCount++
			}
		}
	}

	return net, stats, nil
}

// isForwardOnlyOneWay reports whether the OSM oneway tag value restricts travel
// to the forward direction (A→B). When true, the backward edge must not be added.
// Documented OSM values: "yes", "1", "true".
func isForwardOnlyOneWay(tag string) bool {
	return tag == "yes" || tag == "1" || tag == "true"
}

// isReverseOnlyOneWay reports whether the OSM oneway tag value restricts travel
// to the reverse direction (B→A). When true, the forward edge must not be added.
// Documented OSM values: "-1", "reverse".
func isReverseOnlyOneWay(tag string) bool {
	return tag == "-1" || tag == "reverse"
}

// isExplicitlyBidirectional reports whether the OSM oneway tag explicitly marks
// a way as bidirectional. This takes priority over BuildOptions.AssumeBidirectional.
// Documented OSM values: "no", "0", "false".
func isExplicitlyBidirectional(tag string) bool {
	return tag == "no" || tag == "0" || tag == "false"
}
