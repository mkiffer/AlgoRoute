package server

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"

	"algoroute/geo"
	"algoroute/mapping"
	"algoroute/services"
)

// routeRequest is the JSON body accepted by POST /api/route.
type routeRequest struct {
	Origin      string `json:"origin"`
	Destination string `json:"destination"`
	Algorithm   string `json:"algorithm"` // "dijkstra" or "astar"; defaults to "dijkstra"
}

// routeResponse is the JSON body returned on a successful POST /api/route.
type routeResponse struct {
	Algorithm        string      `json:"algorithm"`
	DistanceMeters   float64     `json:"distance_meters"`
	Path             []pathNode  `json:"path"`
	VisitedNodes     []coordJSON `json:"visited_nodes"`
	OriginCoord      coordJSON   `json:"origin_coord"`
	DestinationCoord coordJSON   `json:"destination_coord"`
}

// pathNode represents a single node in the route path.
type pathNode struct {
	NodeID int64   `json:"node_id"`
	Lat    float64 `json:"lat"`
	Lon    float64 `json:"lon"`
}

// coordJSON is a lat/lon pair for JSON serialisation.
type coordJSON struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

// errorResponse is the JSON body returned when a request fails.
type errorResponse struct {
	Error string `json:"error"`
}

func writeJSON(w http.ResponseWriter, statusCode int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	// The header and status are already flushed; if Encode fails we can only log.
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("writeJSON: encode response: %v", err)
	}
}

// maxRequestBodyBytes caps how much of a request body is read before the
// handler rejects the request. Prevents memory exhaustion from oversized payloads.
const maxRequestBodyBytes = 1 << 20 // 1 MB

func (s *Server) handleRoute(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBodyBytes)

	var req routeRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Error: "invalid JSON body: " + err.Error(),
		})
		return
	}

	if req.Origin == "" || req.Destination == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Error: "origin and destination are required",
		})
		return
	}

	// Construct a RoutingService per request (algorithm selection varies per
	// call) backed by the server's shared NetworkCache so repeated requests
	// for the same area skip the Overpass fetch.
	routingService, err := s.newRoutingServiceForAlgorithm(req.Algorithm)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: err.Error()})
		return
	}

	addressRequest := services.AddressRouteRequest{
		Origin:              req.Origin,
		Destination:         req.Destination,
		Algorithm:           req.Algorithm,
		MapOpts:             mapping.BuildOptions{AssumeBidirectional: true},
		GeocoderBaseURL:     s.opts.GeocoderBaseURL,
		DestGeocoderBaseURL: s.opts.DestGeocoderBaseURL,
		OverpassBaseURL:     s.opts.OverpassBaseURL,
	}

	result, err := routingService.RouteByAddress(addressRequest)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: err.Error()})
		return
	}

	pathNodes := make([]pathNode, len(result.Path))
	for i, node := range result.Path {
		pathNodes[i] = pathNode{
			NodeID: int64(node.ID),
			Lat:    node.Coord.Lat,
			Lon:    node.Coord.Lon,
		}
	}

	visitedNodes := make([]coordJSON, len(result.VisitedNodes))
	for i, node := range result.VisitedNodes {
		visitedNodes[i] = coordJSON{Lat: node.Coord.Lat, Lon: node.Coord.Lon}
	}

	writeJSON(w, http.StatusOK, routeResponse{
		Algorithm:      result.Algorithm,
		DistanceMeters: result.DistanceMeters,
		Path:           pathNodes,
		VisitedNodes:   visitedNodes,
		OriginCoord:    coordJSON{Lat: result.OriginCoord.Lat, Lon: result.OriginCoord.Lon},
		DestinationCoord: coordJSON{
			Lat: result.DestinationCoord.Lat,
			Lon: result.DestinationCoord.Lon,
		},
	})
}

// handleSuggest handles GET /api/suggest?q=<query> and returns up to 5
// Nominatim address suggestions as a JSON array. On any failure it returns
// an empty array so the frontend autocomplete degrades gracefully.
func (s *Server) handleSuggest(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		writeJSON(w, http.StatusOK, []geo.SuggestResult{})
		return
	}

	results, err := suggestWithOptionalOverride(query, s.opts.SuggestBaseURL)
	if err != nil {
		// Suggestions are non-critical — return empty rather than an error response.
		writeJSON(w, http.StatusOK, []geo.SuggestResult{})
		return
	}

	writeJSON(w, http.StatusOK, results)
}

// suggestWithOptionalOverride calls SuggestWithBaseURL when a non-empty
// overrideBaseURL is provided (used by tests), or Suggest when empty
// (production path).
func suggestWithOptionalOverride(query, overrideBaseURL string) ([]geo.SuggestResult, error) {
	if overrideBaseURL != "" {
		return geo.SuggestWithBaseURL(query, overrideBaseURL)
	}
	return geo.Suggest(query)
}

// reverseGeocodeResponse is the JSON body returned by GET /api/reverse.
type reverseGeocodeResponse struct {
	Address string `json:"address"`
}

// handleReverseGeocode handles GET /api/reverse?lat=X&lon=Y and returns
// {"address":"..."} with the reverse-geocoded address string. On any
// Nominatim failure it returns 200 with an empty address so the frontend can
// still place a pin and let the user type an address manually.
func (s *Server) handleReverseGeocode(w http.ResponseWriter, r *http.Request) {
	latStr := r.URL.Query().Get("lat")
	lonStr := r.URL.Query().Get("lon")

	lat, err := strconv.ParseFloat(latStr, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Error: fmt.Sprintf("invalid lat: %q", latStr),
		})
		return
	}

	lon, err := strconv.ParseFloat(lonStr, 64)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Error: fmt.Sprintf("invalid lon: %q", lonStr),
		})
		return
	}

	address, err := reverseGeocodeWithOptionalOverride(geo.Coord{Lat: lat, Lon: lon}, s.opts.ReverseGeocodeBaseURL)
	if err != nil {
		// Reverse geocoding is non-critical — return empty address rather than
		// an error so the frontend can still place the pin with no label.
		writeJSON(w, http.StatusOK, reverseGeocodeResponse{Address: ""})
		return
	}

	writeJSON(w, http.StatusOK, reverseGeocodeResponse{Address: address})
}

// reverseGeocodeWithOptionalOverride calls ReverseGeocodeWithBaseURL when a
// non-empty overrideBaseURL is provided (used by tests), or ReverseGeocode
// when empty (production path).
func reverseGeocodeWithOptionalOverride(coord geo.Coord, overrideBaseURL string) (string, error) {
	if overrideBaseURL != "" {
		return geo.ReverseGeocodeWithBaseURL(coord, overrideBaseURL)
	}
	return geo.ReverseGeocode(coord)
}
