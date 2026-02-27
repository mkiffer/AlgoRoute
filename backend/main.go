package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"

	"algoroute/graph"
	"algoroute/mapping"
	"algoroute/server"
	"algoroute/services"
)

func main() {
	// Server mode flags — used when -serve is present.
	serveMode   := flag.Bool("serve", false, "run as HTTP server instead of CLI")
	listenPort  := flag.String("port", "8080", "HTTP listen port (used with -serve)")
	frontendDir := flag.String("frontend", "../frontend", "path to frontend directory (used with -serve)")

	// CLI mode flags — used when -serve is absent.
	dataFile := flag.String("data", "", "path to OSM JSON file")
	startID  := flag.Int64("start", 0, "start node ID")
	endID    := flag.Int64("end", 0, "end node ID")
	algo     := flag.String("algo", services.AlgorithmDijkstra, "routing algorithm: dijkstra or astar")
	flag.Parse()

	if *serveMode {
		runHTTPServer(*listenPort, *frontendDir)
		return
	}

	runCLI(*dataFile, *startID, *endID, *algo)
}

// runHTTPServer starts the AlgoRoute web server on the given port, serving
// the frontend from frontendDir and the POST /api/route API endpoint.
func runHTTPServer(port, frontendDir string) {
	srv := server.New(frontendDir)

	listenAddress := ":" + port
	log.Printf("AlgoRoute server listening on http://localhost%s", listenAddress)
	log.Printf("Serving frontend from %q", frontendDir)

	if err := http.ListenAndServe(listenAddress, srv); err != nil {
		log.Fatalf("server: %v", err)
	}
}

// runCLI executes a single file-based route request and prints the result to
// stdout. This is the original CLI behaviour, preserved unchanged.
func runCLI(dataFile string, startID, endID int64, algo string) {
	if dataFile == "" || startID == 0 || endID == 0 {
		fmt.Fprintln(os.Stderr, "usage: algoroute -data <file.json> -start <nodeID> -end <nodeID> [-algo dijkstra|astar]")
		fmt.Fprintln(os.Stderr, "       algoroute -serve [-port 8080] [-frontend ../frontend] [-algo dijkstra|astar]")
		os.Exit(1)
	}

	routingService, err := services.NewRoutingService(algo)
	if err != nil {
		log.Fatalf("create routing service: %v", err)
	}

	routeRequest := services.RouteRequest{
		DataFile:  dataFile,
		StartNode: graph.NodeID(startID),
		GoalNode:  graph.NodeID(endID),
		Algorithm: algo,
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
