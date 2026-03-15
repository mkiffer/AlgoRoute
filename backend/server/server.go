/*
server — HTTP server for AlgoRoute.

Responsible for: registering HTTP routes, serving the static frontend, and
delegating API requests to the RoutingService.
Not responsible for: routing algorithm logic (see services/), geocoding (see geo/),
or OSM data fetching (see api/overpass/).
*/
package server

import (
	"log"
	"net/http"
	"runtime/debug"

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
	// handler is the fully composed middleware chain, built once at
	// construction: panicRecovery → cors → mux. Storing it here avoids
	// reallocating wrapper closures on every request.
	handler http.Handler
	opts    Options
}

// New creates a Server with default options that uses the production external
// API endpoints. For test environments, use NewWithOptions.
func New(staticDir string) *Server {
	return NewWithOptions(Options{StaticDir: staticDir})
}

// NewWithOptions creates a Server with full option control. URL override fields
// allow tests to inject httptest servers for Nominatim and Overpass.
func NewWithOptions(opts Options) *Server {
	s := &Server{opts: opts}
	mux := http.NewServeMux()
	s.registerRoutes(mux)
	s.handler = panicRecoveryMiddleware(corsMiddleware(mux))
	return s
}

// ServeHTTP implements http.Handler so Server can be passed directly to
// http.ListenAndServe. All requests pass through the composed middleware chain.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.handler.ServeHTTP(w, r)
}

// panicRecoveryMiddleware catches any panic that escapes a handler, logs it
// with a full stack trace, and writes a 500 response. Without this, a single
// nil-pointer dereference would crash the entire server process.
func panicRecoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic recovered in HTTP handler: %v\n%s", rec, debug.Stack())
				http.Error(w, "internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// corsMiddleware wraps a handler to add CORS headers on every response and
// handle OPTIONS preflight requests. This allows browser clients served from
// a different origin (e.g. the Vite dev server on :5173) to call the API.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) registerRoutes(mux *http.ServeMux) {
	// Serve the frontend from the configured static directory. Any file not
	// matched by the API routes below will be served from disk, allowing the
	// frontend to reference CSS, JS, and other assets without additional routing.
	mux.Handle("/", http.FileServer(http.Dir(s.opts.StaticDir)))

	// POST /api/route finds a route between two addresses.
	mux.HandleFunc("POST /api/route", s.handleRoute)

	// GET /api/suggest returns address autocomplete suggestions from Nominatim.
	mux.HandleFunc("GET /api/suggest", s.handleSuggest)
}

// newRoutingServiceForAlgorithm returns a RoutingService for the given
// algorithm name, defaulting to Dijkstra when the name is empty.
func newRoutingServiceForAlgorithm(algorithm string) (*services.RoutingService, error) {
	if algorithm == "" {
		algorithm = services.AlgorithmDijkstra
	}
	return services.NewRoutingService(algorithm)
}
