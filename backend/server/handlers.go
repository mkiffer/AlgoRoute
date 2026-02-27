package server

import (
	"encoding/json"
	"net/http"

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
	json.NewEncoder(w).Encode(body)
}

func (s *Server) handleRoute(w http.ResponseWriter, r *http.Request) {
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

	// Construct a fresh RoutingService per request so the caller can choose
	// the algorithm independently on each call. Construction is O(1).
	routingService, err := newRoutingServiceForAlgorithm(req.Algorithm)
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

	writeJSON(w, http.StatusOK, routeResponse{
		Algorithm:      result.Algorithm,
		DistanceMeters: result.DistanceMeters,
		Path:           pathNodes,
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
