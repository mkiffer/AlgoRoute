package services

import (
	"algoroute/geo"
	"algoroute/graph"
	"algoroute/mapping"
)

// bboxPaddingDegrees is the margin added around the two geocoded coordinates
// when constructing the Overpass bounding box. 0.01 degrees ≈ 1 km, which
// ensures that roads near (but not exactly at) the geocoded points are included
// in the fetched network.
const bboxPaddingDegrees = 0.01

// AddressRouteRequest describes an address-based routing request.
// GeocoderBaseURL, DestGeocoderBaseURL, and OverpassBaseURL are optional:
// when empty, the production API URLs are used. They exist so tests can
// substitute httptest servers without making live external calls.
type AddressRouteRequest struct {
	Origin      string // free-text address, e.g. "Glenhuntly Rd, Elsternwick"
	Destination string // free-text address, e.g. "Chapel St, South Yarra"
	Algorithm   string // AlgorithmDijkstra or AlgorithmAStar
	MapOpts     mapping.BuildOptions

	// Overrideable for testing — leave empty to use production endpoints.
	GeocoderBaseURL     string // base URL for origin geocoding (Nominatim)
	DestGeocoderBaseURL string // base URL for destination geocoding (Nominatim)
	OverpassBaseURL     string // base URL for Overpass road network fetch
}

// AddressRouteResult is the result of an address-based routing operation.
// Path and VisitedNodes carry full graph.Node values (NodeID + Coord) rather
// than bare NodeIDs so the HTTP layer can render overlays without a separate
// coordinate lookup.
type AddressRouteResult struct {
	Algorithm        string
	DistanceMeters   float64
	Path             []graph.Node // ordered nodes from origin snap to destination snap
	VisitedNodes     []graph.Node // settled nodes in expansion order, for traversal animation
	OriginCoord      geo.Coord    // the geocoded origin coordinate (not the snapped node)
	DestinationCoord geo.Coord    // the geocoded destination coordinate (not the snapped node)
}
