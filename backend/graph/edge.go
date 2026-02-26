package graph

type Edge struct {
	From   NodeID
	To     NodeID
	Weight float64

	// metadata
	WayID int64
	Name  string
}
