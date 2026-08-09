# `Routefinding/Heap.hs` — indexed binary min-heap

## What it does

A priority queue of `(NodeID, Double)` entries that supports **three** operations
the search loop needs, all in log time or better:

| Operation | Cost | Why the search needs it |
|---|---|---|
| `push` | O(log n) | A node is discovered for the first time. |
| `popMin` | O(log n) | Settle the cheapest frontier node. |
| `decreasePriority` | O(log n) | A cheaper route to a known node was found. |
| `member` | O(log n) | Decide between `push` and `decreasePriority`. |
| `peekMin` | O(1) | The bidirectional stopping rule reads both tops. |

## The Go code it replaces

`backend/routefinding/indexed_heap.go`, essentially line for line, including
`siftUp`, `siftDown` and the swap-then-truncate `Pop`.

## Algorithm

A **binary heap** stored as an array: the children of index `i` live at `2i+1`
and `2i+2`, so the tree structure is implicit in the indices and no pointers are
stored. The heap property — every entry is ≤ both its children — is restored
after each mutation by walking one entry up (`siftUp`) or down (`siftDown`) the
tree, which is O(log n) because the tree is complete and therefore balanced.

The **indexed** part is the second field, `Map NodeID Int`. Without it,
"lower this node's priority" would mean scanning the array to find the node
first — O(n), which turns Dijkstra from O((V+E) log V) into O(V·E).

That index is also what makes the heap hold *at most one entry per node*. The
usual alternative, **lazy deletion**, pushes a second entry with the lower
priority and ignores the stale one when it surfaces. That is simpler, but the
heap then grows with the number of *edge relaxations* rather than the number of
nodes, and every pop needs a "have I already settled this?" check. Keeping one
entry per node is what lets `Routefinding.Search` treat every pop as final.

### The three invariants

1. Heap property: `entries[i].priority ≤ entries[2i+1].priority` and `≤ entries[2i+2].priority`.
2. `index` maps every present node to its exact position in `entries`.
3. No node appears twice in `entries`.

Invariant 2 is the one that breaks in practice. Every position change in this
module goes through `swap`, which updates both fields together — that
concentration is the entire defence, and the Go original does the same.

## Haskell design decisions

**`Data.Sequence.Seq`, not a list.** `siftDown` reads and writes element *i*
repeatedly. On a list that is O(n) per access and the whole thing degenerates to
O(n log n) per operation. `Seq` is a finger tree: indexing and updating are both
O(log n), which preserves the bound. It is the closest thing Haskell has to Go's
growable array with random access.

**Immutable, not mutable.** Every operation returns a new heap. `Seq` is
persistent, so an update shares all but O(log n) of the structure with the
original — this is not the wholesale copy it looks like. The payoff is that an
operation cannot leave the structure half-updated: you either get a heap
satisfying all three invariants, or you still hold the old one.

**`popMin` returns `Maybe`.** Go's `Pop` indexes `h.entries[0]` unconditionally
and panics on an empty heap; the caller is trusted to have checked `Len() > 0`.
Here the empty case is in the return type, so it cannot be forgotten.

### The alternative worth knowing: `Data.Set` as a priority search queue

The idiomatic Haskell answer to "priority queue with decrease-key" is usually
not an array heap at all:

```haskell
type PSQ = Set (Double, NodeID)          -- ordered by priority, then node

popMin      = Set.minView
decreaseKey n old new = Set.insert (new, n) . Set.delete (old, n)
```

`Set` is an ordered balanced tree, so `minView`, `insert` and `delete` are all
O(log n) — and decrease-key falls out of *delete then insert*, with no index map
and no `siftUp`/`siftDown` to write. It is about fifteen lines instead of a
hundred and thirty.

The catch is that `decreaseKey` needs the node's **old** priority to delete the
right element, so the caller must keep a `Map NodeID Double` alongside — which
`Routefinding.Search` already does, as its `costs` field. So the trade is real
but small: a side map either way, and a `Set` version would genuinely be
shorter.

**Why this port keeps the array heap anyway.** The point of the exercise is to
read the Go and the Haskell side by side. `siftUp`/`siftDown` translate to
recursive functions in a way that shows exactly how a `for` loop becomes a tail
call, and that is worth more here than fifteen fewer lines. If you were writing
this fresh in Haskell, use the `Set`. Try writing it — the whole module is
replaceable without touching anything else, because the interface is small and
`Search` only sees these seven functions.

## Poke it in the REPL

```
$ cabal repl backend-hs
ghci> import Routefinding.Heap
ghci> import Graph (NodeID(..))
ghci> let h = push (NodeID 3) 9 (push (NodeID 2) 1 (push (NodeID 1) 5 empty))
ghci> fmap fst (popMin h)
Just (Entry {node = 2, priority = 1.0})
ghci> fmap fst (popMin (decreasePriority (NodeID 3) 0 h))
Just (Entry {node = 3, priority = 0.0})
ghci> :type popMin
popMin :: IndexedHeap -> Maybe (Entry, IndexedHeap)
```

That last line is the whole safety argument in one signature: you cannot get an
`Entry` out without acknowledging that there might not be one.
