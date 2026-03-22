package geo

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
)

const nominatimReverseBaseURL = "https://nominatim.openstreetmap.org/reverse"

// nominatimReverseResult is the shape of a Nominatim reverse geocoding response.
// Nominatim returns a single JSON object (not an array) for reverse lookups.
type nominatimReverseResult struct {
	DisplayName string `json:"display_name"`
}

// ReverseGeocodeURL returns the full URL for a Nominatim reverse geocoding
// request for the given coordinate. Exported so tests can assert on the query
// structure without making live HTTP calls.
func ReverseGeocodeURL(coord Coord) string {
	params := url.Values{
		"format": {"json"},
		"lat":    {strconv.FormatFloat(coord.Lat, 'f', -1, 64)},
		"lon":    {strconv.FormatFloat(coord.Lon, 'f', -1, 64)},
	}
	return nominatimReverseBaseURL + "?" + params.Encode()
}

// ReverseGeocode converts a geographic coordinate into a human-readable address
// string by calling the public Nominatim reverse geocoding API.
//
// Returns an error if the HTTP call fails or the response contains no display_name.
// Nominatim usage policy requires a descriptive User-Agent header.
func ReverseGeocode(coord Coord) (string, error) {
	return ReverseGeocodeWithBaseURL(coord, nominatimReverseBaseURL)
}

// ReverseGeocodeWithBaseURL is the testable core of ReverseGeocode. It accepts
// a base URL so unit tests can point it at an httptest server instead of the
// live Nominatim API. Production code calls ReverseGeocode, which passes
// nominatimReverseBaseURL.
func ReverseGeocodeWithBaseURL(coord Coord, baseURL string) (string, error) {
	params := url.Values{
		"format": {"json"},
		"lat":    {strconv.FormatFloat(coord.Lat, 'f', -1, 64)},
		"lon":    {strconv.FormatFloat(coord.Lon, 'f', -1, 64)},
	}
	requestURL := baseURL + "?" + params.Encode()

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return "", fmt.Errorf("build reverse geocode request: %w", err)
	}
	// Nominatim requires a meaningful User-Agent identifying the application.
	req.Header.Set("User-Agent", "AlgoRoute/1.0 (https://github.com/algoroute)")

	resp, err := httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("reverse geocode HTTP request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("nominatim reverse returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read reverse geocode response body: %w", err)
	}

	var result nominatimReverseResult
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("unmarshal reverse geocode response: %w", err)
	}

	if result.DisplayName == "" {
		return "", fmt.Errorf("reverse geocode: no display_name in response")
	}

	return result.DisplayName, nil
}
