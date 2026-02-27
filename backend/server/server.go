/*
server — HTTP server for AlgoRoute.

Responsible for: registering HTTP routes, serving the static frontend, and
delegating API requests to the RoutingService.
Not responsible for: routing algorithm logic (see services/), geocoding (see geo/),
or OSM data fetching (see api/overpass/).
*/
package server

import (
	"net/http"

	"algoroute/services"
)

// Options configures a Server. StaticDir is the only required field; the URL
// override fields exist so tests can substitute httptest servers for live
// external APIs without making network calls.
type Options struct {
	StaticDir string // path to the directory containing index.html

	// Overrideable for testing — leave empty to use production endpoints.
	GeocoderBaseURL     string // base URL for origin geocoding (Nominatim)
	DestGeocoderBaseURL string // base URL for destination geocoding (Nominatim)
	OverpassBaseURL     string // base URL for Overpass road network fetch
	SuggestBaseURL      string // base URL for address autocomplete suggestions (Nominatim)
}

// Server handles HTTP requests for AlgoRoute. It serves the static frontend
// and exposes POST /api/route for address-based route finding.
//
// The Strategy pattern is used for the routing algorithm: the RoutingService
// holds a pluggable Router (Dijkstra or A*) that the handler selects per
// request. This keeps the server decoupled from specific algorithm choices.
type Server struct {
	mux  *http.ServeMux
	opts Options
}

// New creates a Server with default options that uses the production external
// API endpoints. For test environments, use NewWithOptions.
func New(staticDir string) *Server {
	return NewWithOptions(Options{StaticDir: staticDir})
}

// NewWithOptions creates a Server with full option control. URL override fields
// allow tests to inject httptest servers for Nominatim and Overpass.
func NewWithOptions(opts Options) *Server {
	s := &Server{
		mux:  http.NewServeMux(),
		opts: opts,
	}
	s.registerRoutes()
	return s
}

// ServeHTTP implements http.Handler so Server can be passed directly to
// http.ListenAndServe.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}

func (s *Server) registerRoutes() {
	// Serve the frontend from the configured static directory. Any file not
	// matched by the API routes below will be served from disk, allowing the
	// frontend to reference CSS, JS, and other assets without additional routing.
	s.mux.Handle("/", http.FileServer(http.Dir(s.opts.StaticDir)))

	// POST /api/route finds a route between two addresses.
	s.mux.HandleFunc("POST /api/route", s.handleRoute)

	// GET /api/suggest returns address autocomplete suggestions from Nominatim.
	s.mux.HandleFunc("GET /api/suggest", s.handleSuggest)
}

// newRoutingServiceForAlgorithm returns a RoutingService for the given
// algorithm name, defaulting to Dijkstra when the name is empty.
func newRoutingServiceForAlgorithm(algorithm string) (*services.RoutingService, error) {
	if algorithm == "" {
		algorithm = services.AlgorithmDijkstra
	}
	return services.NewRoutingService(algorithm)
}
