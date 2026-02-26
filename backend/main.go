package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	"algoroute/graph"
	"algoroute/mapping"
	"algoroute/services"
)

func main() {
	dataFile := flag.String("data", "", "path to OSM JSON file")
	startID := flag.Int64("start", 0, "start node ID")
	endID := flag.Int64("end", 0, "end node ID")
	algo := flag.String("algo", services.AlgorithmDijkstra, "routing algorithm: dijkstra or astar")
	flag.Parse()

	if *dataFile == "" || *startID == 0 || *endID == 0 {
		fmt.Fprintln(os.Stderr, "usage: algoroute -data <file.json> -start <nodeID> -end <nodeID> [-algo dijkstra|astar]")
		os.Exit(1)
	}

	routingService, err := services.NewRoutingService(*algo)
	if err != nil {
		log.Fatalf("create routing service: %v", err)
	}

	routeRequest := services.RouteRequest{
		DataFile:  *dataFile,
		StartNode: graph.NodeID(*startID),
		GoalNode:  graph.NodeID(*endID),
		Algorithm: *algo,
		MapOpts:   mapping.BuildOptions{AssumeBidirectional: true},
	}

	result, err := routingService.Route(routeRequest)
	if err != nil {
		log.Fatalf("route: %v", err)
	}

	fmt.Printf("Algorithm:      %s\n", result.Algorithm)
	fmt.Printf("Total distance: %.2f meters\n", result.Distance)
	fmt.Printf("Path (%d nodes):\n", len(result.Path))
	for _, nodeID := range result.Path {
		fmt.Printf("  %d\n", nodeID)
	}
}
