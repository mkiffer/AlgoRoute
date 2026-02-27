package geo

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"
)

const nominatimBaseURL = "https://nominatim.openstreetmap.org/search"

// httpClient is used for all Nominatim requests. The 10-second timeout keeps
// geocoding failures from stalling the entire routing request.
var httpClient = &http.Client{Timeout: 10 * time.Second}

// nominatimResult is the shape of a single result in a Nominatim JSON response.
type nominatimResult struct {
	Lat string `json:"lat"`
	Lon string `json:"lon"`
}

// NominatimURL returns the full URL for a Nominatim search request for the
// given address. Exported so tests can assert on the query structure without
// making live HTTP calls.
func NominatimURL(address string) string {
	params := url.Values{
		"format": {"json"},
		"q":      {address},
		"limit":  {"1"},
	}
	return nominatimBaseURL + "?" + params.Encode()
}

// Geocode converts a free-text address string into a geographic coordinate
// by calling the public Nominatim search API.
//
// Returns an error if the address produces no results or the HTTP call fails.
// Nominatim usage policy requires a descriptive User-Agent header.
func Geocode(address string) (Coord, error) {
	return GeocodeWithBaseURL(address, nominatimBaseURL)
}

// GeocodeWithBaseURL is the testable core of Geocode. It accepts a base URL so
// unit tests can point it at an httptest server instead of the live Nominatim
// API. Production code calls Geocode, which passes nominatimBaseURL.
func GeocodeWithBaseURL(address, baseURL string) (Coord, error) {
	params := url.Values{
		"format": {"json"},
		"q":      {address},
		"limit":  {"1"},
	}
	requestURL := baseURL + "?" + params.Encode()

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return Coord{}, fmt.Errorf("build geocode request: %w", err)
	}
	// Nominatim requires a meaningful User-Agent identifying the application.
	// Requests without one are rate-limited more aggressively.
	req.Header.Set("User-Agent", "AlgoRoute/1.0 (https://github.com/algoroute)")

	resp, err := httpClient.Do(req)
	if err != nil {
		return Coord{}, fmt.Errorf("geocode HTTP request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return Coord{}, fmt.Errorf("nominatim returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return Coord{}, fmt.Errorf("read geocode response body: %w", err)
	}

	var results []nominatimResult
	if err := json.Unmarshal(body, &results); err != nil {
		return Coord{}, fmt.Errorf("unmarshal geocode response: %w", err)
	}

	if len(results) == 0 {
		return Coord{}, fmt.Errorf("geocode: no results for address %q", address)
	}

	lat, err := strconv.ParseFloat(results[0].Lat, 64)
	if err != nil {
		return Coord{}, fmt.Errorf("geocode: parse lat %q: %w", results[0].Lat, err)
	}
	lon, err := strconv.ParseFloat(results[0].Lon, 64)
	if err != nil {
		return Coord{}, fmt.Errorf("geocode: parse lon %q: %w", results[0].Lon, err)
	}

	return Coord{Lat: lat, Lon: lon}, nil
}
