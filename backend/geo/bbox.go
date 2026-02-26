package geo

type BBox struct {
	MinLat float64
	MinLon float64
	MaxLat float64
	MaxLon float64
}

func (b BBox) Contains(c Coord) bool {
	return c.Lat >= b.MinLat && c.Lat <= b.MaxLat && c.Lon >= b.MinLon && c.Lon <= b.MaxLon
}
