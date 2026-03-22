// network_cache.go — in-memory cache for Overpass API responses.
//
// Responsible for: storing and retrieving overpass.Response values keyed by
// geographic bounding box so that repeated route requests for the same area
// skip the Overpass fetch entirely.
//
// Not responsible for: cache eviction, TTL, or on-disk persistence. This is
// intentionally a simple unbounded map — eviction can be added if memory
// growth becomes a concern in production.
package services

import (
	"sync"

	"algoroute/api/overpass"
	"algoroute/geo"
)

// NetworkCache caches Overpass API responses keyed by geographic bounding box.
//
// A common scenario that benefits from caching: the user submits the same
// origin and destination twice (e.g. once with Dijkstra, once with A*). Each
// call produces the identical bbox, so the second call can skip the Overpass
// fetch — potentially saving several seconds and tens of megabytes per request.
//
// geo.BBox contains only float64 fields and is therefore comparable, making it
// safe to use directly as a map key.
//
// Thread-safe: Lookup and Store may be called concurrently from multiple
// goroutines (one per HTTP request).
type NetworkCache struct {
	mu      sync.RWMutex
	entries map[geo.BBox]overpass.Response
}

// NewNetworkCache returns an empty, ready-to-use NetworkCache.
func NewNetworkCache() *NetworkCache {
	return &NetworkCache{
		entries: make(map[geo.BBox]overpass.Response),
	}
}

// Lookup returns the cached Overpass response for bbox, if one exists.
// The second return value is false on a cache miss.
func (c *NetworkCache) Lookup(bbox geo.BBox) (overpass.Response, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	resp, ok := c.entries[bbox]
	return resp, ok
}

// Store saves resp under bbox, overwriting any existing entry for that bbox.
func (c *NetworkCache) Store(bbox geo.BBox, resp overpass.Response) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries[bbox] = resp
}
