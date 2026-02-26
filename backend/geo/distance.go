package geo

import (
	"math"
)

const earthRadiusMeters = 6371000.0

func DistanceMeters(a, b Coord) float64 {
	lat1 := a.Lat * math.Pi / 180.0
	lat2 := b.Lat * math.Pi / 180.0
	dLat := (b.Lat - a.Lat) * math.Pi / 180.0
	dLon := (b.Lon - a.Lon) * math.Pi / 180.0

	sinDLat := math.Sin(dLat / 2)
	sinDLon := math.Sin(dLon / 2)

	h := sinDLat*sinDLat + math.Cos(lat1)*math.Cos(lat2)*sinDLon*sinDLon

	return 2 * earthRadiusMeters * math.Asin(math.Sqrt(h))
}
