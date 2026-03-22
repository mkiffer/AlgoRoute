package overpass

import (
	"encoding/json"
	"fmt"
	"os"
)

// Response matches the top-level JSON shape returned by the Overpass API.
type Response struct {
	Version   float64   `json:"version"`
	Generator string    `json:"generator"`
	Osm3s     *Osm3s    `json:"osm3s,omitempty"`
	Elements  []Element `json:"elements"`

	// Slices derived from Elements — not populated by JSON unmarshalling.
	Ways  []Element `json:"-"`
	Nodes []Element `json:"-"`
	// Fast lookup: node ID → node element.
	NodeByID map[int64]Element `json:"-"`
}

type Osm3s struct {
	TimestampOSMBase string `json:"timestamp_osm_base,omitempty"`
	Copyright        string `json:"copyright,omitempty"`
}

// Element represents a single OSM node or way from an Overpass response.
type Element struct {
	Type string `json:"type"` // "node" or "way"
	Id   int64  `json:"id"`

	// Node fields (only set when Type == "node").
	Lat *float64 `json:"lat,omitempty"`
	Lon *float64 `json:"lon,omitempty"`

	// Way fields (only set when Type == "way").
	Nodes []int64 `json:"nodes,omitempty"`

	// OSM tags are treated as free-form key-value strings due to their variability.
	Tags map[string]string `json:"tags,omitempty"`
}

func LoadNetworkFromJSON(jsonFilePath string) (Response, error) {
	data, err := os.ReadFile(jsonFilePath)
	if err != nil {
		return Response{}, fmt.Errorf("read file %q: %w", jsonFilePath, err)
	}

	var response Response
	if err := json.Unmarshal(data, &response); err != nil {
		return Response{}, fmt.Errorf("unmarshal overpass response: %w", err)
	}

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

func (e Element) Tag(key string) (string, bool) {
	if e.Tags == nil {
		return "", false
	}
	v, ok := e.Tags[key]
	return v, ok
}
