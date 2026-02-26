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

	//iterate through resp.Ways
	//for each way, check if it has a highway tag
	//if not, skip it and increment NonRoutableWays

	//for each way with a highway tag, check if the highway type is allowed
	//if not, skip it and increment NonRoutableWays
	//add nodes to the graph if they don't already exist
	//add edges to the graph
	//if AssumeBidirectional is true, add edges in both directions

	net := graph.NewNetwork()
	var stats BuildStats

	for _, way := range response.Ways {
		stats.WayCount++

		for i, nodeID := range way.Nodes {
			if i == 0 {
				continue //skip first node
			}
			//get the id of where the edge starts (FROM)
			//create the node and add it to the network
			//object

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

			//get the id of where the edge ends (TO)
			//create the node and add it to the network
			//object
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

			//calculate distance between fromNode and toNode
			distance := geo.DistanceMeters(fromNode.Coord, toNode.Coord)

			//create the forward direction edge
			forwardEdge := graph.Edge{
				From:   fromNode.ID,
				To:     toNode.ID,
				Weight: distance,
				WayID:  way.Id,
				Name:   way.Tags["name"],
			}
			if err := net.AddEdge(forwardEdge); err != nil {
				return nil, stats, err
			}

			stats.EdgeCount++

			if options.AssumeBidirectional {
				backwardEdge := graph.Edge{
					From:   toNode.ID,
					To:     fromNode.ID,
					Weight: distance,
					WayID:  way.Id,
					Name:   way.Tags["name"],
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
