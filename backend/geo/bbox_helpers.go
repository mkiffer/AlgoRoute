package geo

// BBoxFromCoords returns the smallest BBox that contains both a and b,
// expanded outward by paddingDegrees in every direction.
//
// The padding ensures that roads near (but not exactly at) the geocoded
// coordinates are included when the bbox is used as an Overpass API query
// region. A padding of 0.01 degrees is approximately 1 km, which is a
// reasonable buffer for city-scale route searches.
func BBoxFromCoords(a, b Coord, paddingDegrees float64) BBox {
	minLat := min(a.Lat, b.Lat)
	maxLat := max(a.Lat, b.Lat)
	minLon := min(a.Lon, b.Lon)
	maxLon := max(a.Lon, b.Lon)

	return BBox{
		MinLat: minLat - paddingDegrees,
		MaxLat: maxLat + paddingDegrees,
		MinLon: minLon - paddingDegrees,
		MaxLon: maxLon + paddingDegrees,
	}
}
