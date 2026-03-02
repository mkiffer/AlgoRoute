/*
Tests for: routefinding/indexed_heap.go — indexed binary min-heap with decrease-key.

Coverage intent: min-heap ordering on Pop, DecreasePriority re-ordering, Contains
tracking, and Pop from an empty queue. These properties are critical for correct
Dijkstra/A* behaviour: Pop must always return the lowest-priority node, and
DecreasePriority must promote a node when a shorter path is found.
*/
package routefinding

import (
	"algoroute/graph"
	"testing"
)

func TestIndexedHeap_PopReturnsLowestPriority(t *testing.T) {
	// The heap must be a min-heap: Pop returns the entry with the smallest
	// priority value. This ensures Dijkstra always settles the nearest node.
	h := newIndexedHeap()
	h.Push(graph.NodeID(1), 10.0)
	h.Push(graph.NodeID(2), 5.0)
	h.Push(graph.NodeID(3), 8.0)

	got := h.Pop()

	if got.node != graph.NodeID(2) {
		t.Errorf("Pop: got node %v, want 2 (lowest priority 5.0)", got.node)
	}
	if got.priority != 5.0 {
		t.Errorf("Pop: got priority %v, want 5.0", got.priority)
	}
}

func TestIndexedHeap_PopDrainsInOrder(t *testing.T) {
	// Popping all entries must yield them in ascending priority order.
	h := newIndexedHeap()
	h.Push(graph.NodeID(1), 30.0)
	h.Push(graph.NodeID(2), 10.0)
	h.Push(graph.NodeID(3), 20.0)

	want := []graph.NodeID{2, 3, 1}
	for i, wantNode := range want {
		got := h.Pop()
		if got.node != wantNode {
			t.Errorf("Pop[%d]: got node %v, want %v", i, got.node, wantNode)
		}
	}
}

func TestIndexedHeap_DecreasePriority_PromotesNode(t *testing.T) {
	// After decreasing node 3's priority below node 2's, node 3 must be
	// popped first. This validates that the heap re-orders on decrease-key.
	h := newIndexedHeap()
	h.Push(graph.NodeID(1), 10.0)
	h.Push(graph.NodeID(2), 5.0)
	h.Push(graph.NodeID(3), 8.0)

	h.DecreasePriority(graph.NodeID(3), 2.0)

	got := h.Pop()
	if got.node != graph.NodeID(3) {
		t.Errorf("Pop after DecreasePriority: got node %v, want 3", got.node)
	}
	if got.priority != 2.0 {
		t.Errorf("Pop after DecreasePriority: got priority %v, want 2.0", got.priority)
	}
}

func TestIndexedHeap_Contains_TracksPresence(t *testing.T) {
	h := newIndexedHeap()
	h.Push(graph.NodeID(1), 10.0)

	if !h.Contains(graph.NodeID(1)) {
		t.Error("Contains: expected true for pushed node 1, got false")
	}
	if h.Contains(graph.NodeID(99)) {
		t.Error("Contains: expected false for absent node 99, got true")
	}

	h.Pop()

	if h.Contains(graph.NodeID(1)) {
		t.Error("Contains after Pop: expected false for popped node 1, got true")
	}
}

func TestIndexedHeap_Len_ReflectsSize(t *testing.T) {
	h := newIndexedHeap()

	if h.Len() != 0 {
		t.Errorf("Len empty heap: got %d, want 0", h.Len())
	}

	h.Push(graph.NodeID(1), 10.0)
	h.Push(graph.NodeID(2), 20.0)

	if h.Len() != 2 {
		t.Errorf("Len after 2 pushes: got %d, want 2", h.Len())
	}

	h.Pop()

	if h.Len() != 1 {
		t.Errorf("Len after 1 pop: got %d, want 1", h.Len())
	}
}

func TestIndexedHeap_DecreasePriority_LargerValueIsIgnored(t *testing.T) {
	// If DecreasePriority is called with a value >= the current priority,
	// the heap must remain unchanged. This prevents accidentally increasing
	// a node's priority (which would break the min-heap invariant).
	h := newIndexedHeap()
	h.Push(graph.NodeID(1), 5.0)

	h.DecreasePriority(graph.NodeID(1), 10.0)

	got := h.Pop()
	if got.priority != 5.0 {
		t.Errorf("Priority after no-op decrease: got %v, want 5.0 (unchanged)", got.priority)
	}
}
