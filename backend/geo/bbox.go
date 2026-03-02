package geo

import "math"

type BBox struct {
	MinLat float64
	MinLon float64
	MaxLat float64
	MaxLon float64
}

func (b BBox) Contains(c Coord) bool {
	return c.Lat >= b.MinLat && c.Lat <= b.MaxLat && c.Lon >= b.MinLon && c.Lon <= b.MaxLon
}

// kmPerDegree is the approximate distance in kilometres of one degree of
// latitude (or longitude at the equator). Used for quick area estimates.
const kmPerDegree = 111.32

// ApproxAreaKm2 returns the approximate area of the bounding box in square
// kilometres. The calculation uses a cosine correction at the midpoint latitude
// to account for longitude convergence toward the poles. This is accurate enough
// for validating query size but not intended for geodesic precision.
func (b BBox) ApproxAreaKm2() float64 {
	latSpanKm := (b.MaxLat - b.MinLat) * kmPerDegree
	midLatRad := (b.MinLat + b.MaxLat) / 2.0 * math.Pi / 180.0
	lonSpanKm := (b.MaxLon - b.MinLon) * kmPerDegree * math.Cos(midLatRad)
	return latSpanKm * lonSpanKm
}
