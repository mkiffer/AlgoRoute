package services

import (
	"fmt"

	"algoroute/api/overpass"
	"algoroute/geo"
	"algoroute/graph"
	"algoroute/mapping"
)

// RouteByAddress performs the full address-to-route pipeline:
//  1. Geocode origin and destination strings to coordinates.
//  2. Build a padded bounding box that encloses both coordinates.
//  3. Fetch the road network from the Overpass API for that bounding box.
//  4. Build a graph.Network from the Overpass response.
//  5. Snap both coordinates to their nearest graph nodes.
//  6. Run the configured routing algorithm between the two snapped nodes.
//  7. Enrich the path with per-node coordinates for map rendering.
func (s *RoutingService) RouteByAddress(req AddressRouteRequest) (AddressRouteResult, error) {
	// Step 1: Geocode origin.
	// Use a per-field base URL so tests can serve independent fake Nominatim
	// responses for origin and destination without request-routing logic.
	originCoord, err := geocodeWithOptionalOverride(req.Origin, req.GeocoderBaseURL)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("geocode origin: %w", err)
	}

	// Step 1b: Geocode destination.
	destinationCoord, err := geocodeWithOptionalOverride(req.Destination, req.DestGeocoderBaseURL)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("geocode destination: %w", err)
	}

	// Step 2: Build a padded bounding box so that roads near (but not
	// exactly at) the geocoded coordinates are included in the fetch.
	bbox := geo.BBoxFromCoords(originCoord, destinationCoord, bboxPaddingDegrees)

	// Step 3: Fetch the road network.
	var overpassResponse overpass.Response
	if req.OverpassBaseURL != "" {
		overpassResponse, err = overpass.FetchFromAPIWithBaseURL(bbox, req.OverpassBaseURL)
	} else {
		overpassResponse, err = overpass.FetchFromAPI(bbox)
	}
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("fetch road network: %w", err)
	}

	if len(overpassResponse.Ways) == 0 {
		return AddressRouteResult{}, fmt.Errorf(
			"no driveable roads found in bounding box — " +
				"the area between the two addresses may have no OSM road data",
		)
	}

	// Step 4: Build graph.Network.
	// Default to bidirectional edges: one-way street handling (OSM oneway tag)
	// is a future enhancement and requires additional mapping logic.
	mapOpts := req.MapOpts
	if !mapOpts.AssumeBidirectional {
		mapOpts.AssumeBidirectional = true
	}
	network, _, err := mapping.BuildNetwork(overpassResponse, mapOpts)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("build network: %w", err)
	}

	// Step 5: Snap geocoded coordinates to the nearest graph nodes.
	startNodeID, err := graph.NearestNode(network, originCoord)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("snap origin to network: %w", err)
	}
	goalNodeID, err := graph.NearestNode(network, destinationCoord)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("snap destination to network: %w", err)
	}

	// Step 6: Run the routing algorithm.
	pathNodeIDs, totalDistance, err := s.router.Route(network, startNodeID, goalNodeID)
	if err != nil {
		return AddressRouteResult{}, fmt.Errorf("route: %w", err)
	}

	// Step 7: Enrich path with coordinates so the HTTP layer can render a
	// polyline without a separate node-coordinate lookup.
	pathNodes := make([]graph.Node, len(pathNodeIDs))
	for i, nodeID := range pathNodeIDs {
		pathNodes[i] = network.Nodes[nodeID]
	}

	return AddressRouteResult{
		Algorithm:        s.algorithm,
		DistanceMeters:   totalDistance,
		Path:             pathNodes,
		OriginCoord:      originCoord,
		DestinationCoord: destinationCoord,
	}, nil
}

// geocodeWithOptionalOverride calls GeocodeWithBaseURL when a non-empty
// overrideBaseURL is provided (used by tests), or Geocode when empty
// (production path). This avoids leaking test-only parameters into the
// production Geocode signature.
func geocodeWithOptionalOverride(address, overrideBaseURL string) (geo.Coord, error) {
	if overrideBaseURL != "" {
		return geo.GeocodeWithBaseURL(address, overrideBaseURL)
	}
	return geo.Geocode(address)
}
