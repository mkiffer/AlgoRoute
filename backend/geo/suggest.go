/*
geo/suggest.go

Responsible for: fetching address autocomplete suggestions from the Nominatim
search API and parsing them into SuggestResult values.
Not responsible for: geocoding a single address to a coordinate (see geocode.go),
or serving the suggestions over HTTP (see server/handlers.go).
*/
package geo

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
)

// nominatimSuggestResultLimit is the maximum number of suggestions requested
// from Nominatim. Five results fill a compact dropdown without overwhelming
// the user; Nominatim recommends keeping limits low to respect fair-use policy.
const nominatimSuggestResultLimit = "5"

// SuggestResult is a single address suggestion returned by GET /api/suggest.
type SuggestResult struct {
	DisplayName string  `json:"display_name"`
	Lat         float64 `json:"lat"`
	Lon         float64 `json:"lon"`
}

// nominatimSuggestHit is the raw shape of one entry in a Nominatim search
// response. Lat and Lon arrive as strings and must be parsed before use.
type nominatimSuggestHit struct {
	DisplayName string `json:"display_name"`
	Lat         string `json:"lat"`
	Lon         string `json:"lon"`
}

// SuggestURL returns the full URL for a Nominatim suggestion request for the
// given query. Exported so tests can assert on the query structure without
// making live HTTP calls — mirrors NominatimURL in geocode.go.
func SuggestURL(query string) string {
	params := url.Values{
		"format": {"json"},
		"q":      {query},
		"limit":  {nominatimSuggestResultLimit},
	}
	return nominatimBaseURL + "?" + params.Encode()
}

// Suggest returns up to 5 address suggestions for the given query string
// by calling the public Nominatim search API.
func Suggest(query string) ([]SuggestResult, error) {
	return SuggestWithBaseURL(query, nominatimBaseURL)
}

// SuggestWithBaseURL is the testable core of Suggest. It accepts a base URL so
// unit tests can point it at an httptest server instead of the live Nominatim
// API. Production code calls Suggest, which passes nominatimBaseURL.
func SuggestWithBaseURL(query, baseURL string) ([]SuggestResult, error) {
	params := url.Values{
		"format": {"json"},
		"q":      {query},
		"limit":  {nominatimSuggestResultLimit},
	}
	requestURL := baseURL + "?" + params.Encode()

	req, err := http.NewRequest(http.MethodGet, requestURL, nil)
	if err != nil {
		return nil, fmt.Errorf("build suggest request: %w", err)
	}
	// Nominatim requires a meaningful User-Agent identifying the application.
	// Requests without one are rate-limited more aggressively.
	req.Header.Set("User-Agent", "AlgoRoute/1.0 (https://github.com/algoroute)")

	response, err := httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("suggest HTTP request: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("nominatim returned status %d", response.StatusCode)
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, fmt.Errorf("read suggest response body: %w", err)
	}

	var nominatimHits []nominatimSuggestHit
	if err := json.Unmarshal(body, &nominatimHits); err != nil {
		return nil, fmt.Errorf("unmarshal suggest response: %w", err)
	}

	suggestions := make([]SuggestResult, 0, len(nominatimHits))
	for _, hit := range nominatimHits {
		lat, err := strconv.ParseFloat(hit.Lat, 64)
		if err != nil {
			// Skip results with unparseable coordinates rather than failing the
			// whole request — a single bad entry from Nominatim must not prevent
			// the valid suggestions in the same response from reaching the user.
			continue
		}
		lon, err := strconv.ParseFloat(hit.Lon, 64)
		if err != nil {
			continue
		}
		suggestions = append(suggestions, SuggestResult{
			DisplayName: hit.DisplayName,
			Lat:         lat,
			Lon:         lon,
		})
	}

	return suggestions, nil
}
