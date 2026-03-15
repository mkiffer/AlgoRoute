/*
Tests for: server/server.go — panicRecoveryMiddleware.
Coverage intent:
  - A handler that panics must yield a 500 response, not crash the process.
  - A normal handler must pass through with its original status code unchanged.

Uses the internal package (package server, not server_test) to access the
unexported panicRecoveryMiddleware directly, consistent with corsMiddleware
also being unexported.
*/
package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPanicRecoveryMiddleware_PanickingHandler_Returns500(t *testing.T) {
	// A handler that panics must not crash the server. The middleware must
	// recover the panic and write a 500 so the client gets a response and
	// the process keeps serving subsequent requests.
	panickingHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("simulated nil-pointer dereference")
	})

	handler := panicRecoveryMiddleware(panickingHandler)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusInternalServerError {
		t.Errorf(
			"panicRecoveryMiddleware: got status %d, want 500 — "+
				"a panicking handler must be recovered and return 500",
			rec.Code,
		)
	}
}

func TestPanicRecoveryMiddleware_NormalHandler_PassesThroughUnchanged(t *testing.T) {
	// When no panic occurs, the middleware must not interfere with the
	// handler's response — status code and body must be preserved exactly.
	normalHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	handler := panicRecoveryMiddleware(normalHandler)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()

	handler.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Errorf(
			"panicRecoveryMiddleware: got status %d, want 200 — "+
				"a normal handler must not be affected by the recovery wrapper",
			rec.Code,
		)
	}
}
