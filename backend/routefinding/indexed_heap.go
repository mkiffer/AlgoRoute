package routefinding

import "algoroute/graph"

// indexedHeap is a binary min-heap with O(1) Contains and O(log n) decrease-key.
//
// Unlike the lazy-deletion priorityQueue it replaces, this heap stores at most
// one entry per node. When a shorter path is found, DecreasePriority updates
// the existing entry in-place and re-heapifies — so the heap size is bounded
// by the number of unique nodes, not the number of edge relaxations.
type indexedHeap struct {
	entries []ipqEntry
	index   map[graph.NodeID]int // nodeID → position in entries
}

type ipqEntry struct {
	node     graph.NodeID
	priority float64
}

func newIndexedHeap() *indexedHeap {
	return &indexedHeap{
		index: make(map[graph.NodeID]int),
	}
}

func (h *indexedHeap) Len() int           { return len(h.entries) }
func (h *indexedHeap) Contains(id graph.NodeID) bool { _, ok := h.index[id]; return ok }

// Push adds a new node. Callers must ensure the node is not already present.
func (h *indexedHeap) Push(node graph.NodeID, priority float64) {
	h.entries = append(h.entries, ipqEntry{node: node, priority: priority})
	pos := len(h.entries) - 1
	h.index[node] = pos
	h.siftUp(pos)
}

// Pop removes and returns the entry with the lowest priority.
func (h *indexedHeap) Pop() ipqEntry {
	root := h.entries[0]
	last := len(h.entries) - 1

	h.swap(0, last)
	h.entries = h.entries[:last]
	delete(h.index, root.node)

	if len(h.entries) > 0 {
		h.siftDown(0)
	}
	return root
}

// DecreasePriority lowers the priority of an existing node and re-heapifies.
// If newPriority >= the current priority, the call is a no-op.
func (h *indexedHeap) DecreasePriority(node graph.NodeID, newPriority float64) {
	pos, ok := h.index[node]
	if !ok {
		return
	}
	if newPriority >= h.entries[pos].priority {
		return
	}
	h.entries[pos].priority = newPriority
	h.siftUp(pos)
}

// --- heap internals ---

func (h *indexedHeap) swap(i, j int) {
	h.entries[i], h.entries[j] = h.entries[j], h.entries[i]
	h.index[h.entries[i].node] = i
	h.index[h.entries[j].node] = j
}

func (h *indexedHeap) siftUp(pos int) {
	for pos > 0 {
		parent := (pos - 1) / 2
		if h.entries[pos].priority >= h.entries[parent].priority {
			break
		}
		h.swap(pos, parent)
		pos = parent
	}
}

func (h *indexedHeap) siftDown(pos int) {
	n := len(h.entries)
	for {
		smallest := pos
		left := 2*pos + 1
		right := 2*pos + 2

		if left < n && h.entries[left].priority < h.entries[smallest].priority {
			smallest = left
		}
		if right < n && h.entries[right].priority < h.entries[smallest].priority {
			smallest = right
		}
		if smallest == pos {
			break
		}
		h.swap(pos, smallest)
		pos = smallest
	}
}
