package overpass

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"algoroute/geo"
)

const overpassAPIURL = "https://overpass-api.de/api/interpreter"

// driveableHighwayTypes is the set of OSM highway tag values that represent
// roads a car can legally drive on. Footways, cycleways, and service roads
// are excluded to keep the graph focused on driveable routes.
const driveableHighwayTypes = `motorway|trunk|primary|secondary|tertiary|residential|unclassified|living_street`

// overpassHTTPClient is used for all Overpass API requests. The 30-second
// timeout handles large bounding boxes that can return several MB of data;
// shorter timeouts cause spurious failures on slower connections.
var overpassHTTPClient = &http.Client{Timeout: 30 * time.Second}

// BuildOverpassQuery returns an Overpass QL query that fetches all driveable
// way elements (and their member nodes) within bbox.
//
// The bbox coordinates follow the Overpass convention: south,west,north,east
// which corresponds to MinLat,MinLon,MaxLat,MaxLon. The >;out body; idiom
// causes Overpass to also emit every node referenced by a matched way, so the
// response contains both ways and the coordinate data for their nodes.
//
// Exported so it can be unit-tested without making live HTTP calls.
func BuildOverpassQuery(bbox geo.BBox) string {
	// Overpass bbox argument order: (south, west, north, east)
	bboxStr := fmt.Sprintf("%.6f,%.6f,%.6f,%.6f",
		bbox.MinLat, bbox.MinLon, bbox.MaxLat, bbox.MaxLon,
	)
	return fmt.Sprintf(
		`[out:json];(way["highway"~"^(%s)$"](%s);>;);out body;`,
		driveableHighwayTypes, bboxStr,
	)
}

// FetchFromAPI queries the live Overpass API for all driveable road ways within
// bbox and returns a parsed Response ready for mapping.BuildNetwork.
func FetchFromAPI(bbox geo.BBox) (Response, error) {
	return FetchFromAPIWithBaseURL(bbox, overpassAPIURL)
}

// FetchFromAPIWithBaseURL is the testable core of FetchFromAPI. It accepts a
// base URL so unit tests can point it at an httptest server. Production code
// calls FetchFromAPI, which passes overpassAPIURL.
func FetchFromAPIWithBaseURL(bbox geo.BBox, baseURL string) (Response, error) {
	query := BuildOverpassQuery(bbox)

	resp, err := overpassHTTPClient.PostForm(baseURL, url.Values{"data": {query}})
	if err != nil {
		return Response{}, fmt.Errorf("overpass HTTP request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return Response{}, fmt.Errorf("overpass API returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return Response{}, fmt.Errorf("read overpass response body: %w", err)
	}

	var response Response
	if err := json.Unmarshal(body, &response); err != nil {
		return Response{}, fmt.Errorf("unmarshal overpass response: %w", err)
	}

	// Populate the derived slices and map that the mapping layer depends on.
	// This replicates the post-unmarshal logic in LoadNetworkFromJSON so that
	// both file-based and HTTP-based responses have identical structure.
	response.NodeByID = make(map[int64]Element)
	for _, element := range response.Elements {
		switch element.Type {
		case "way":
			response.Ways = append(response.Ways, element)
		case "node":
			response.Nodes = append(response.Nodes, element)
			response.NodeByID[element.Id] = element
		}
	}

	return response, nil
}
