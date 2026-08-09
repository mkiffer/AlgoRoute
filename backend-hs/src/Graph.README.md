# `Graph.hs` — the road network

## What it does

The routing graph: nodes with coordinates, directed weighted edges, and an
adjacency index. Everything the search algorithms actually traverse.

## The Go code it replaces

All four files of `backend/graph/` — `node_id.go`, `node.go`, `edge.go`,
`network.go` — merged into one module. In Haskell there is no reason to spread
four small declarations across four files; Go's split is largely about keeping
each file's imports honest.

## The central design difference: `Network` is a value

Go mutates:

```go
func (n *Network) AddNode(node Node)              // mutates in place
func (n *Network) AddEdge(edge Edge) error        // mutates, or returns error
```

Haskell returns:

```haskell
addNode :: Node -> Network -> Network
addEdge :: Edge -> Network -> Either GraphError Network
```

**This is not as expensive as it looks.** `Data.Map` is a persistent balanced
tree: inserting into a map of *n* entries allocates O(log n) new nodes and
*shares* everything else with the original. Building a 40,000-node network this
way is not meaningfully slower than mutating one.

What it buys:

- **No aliasing.** Nothing can hold a stale pointer to a network that has since
  changed underneath it.
- **No half-updated state.** `addEdge` either gives you a valid network or an
  error; there is no third case where the network was partially modified before
  the failure. Go's version returns the error *after* the caller already has a
  pointer to the mutated struct.
- **Free snapshots.** Keeping the pre-mutation network costs nothing, which is
  occasionally handy in tests.

## `NodeID` is a `newtype`, not a `type`

```haskell
newtype NodeID = NodeID { unNodeID :: Int64 }
```

Go's `type NodeID int64` creates a genuinely distinct named type. The Haskell
equivalent is `newtype`, **not** `type`: a bare `type NodeID = Int64` is a
transparent synonym, and would let you pass a way ID where a node ID is expected
without complaint. Both are `Int64` underneath and both are OSM identifiers, so
this is a real mistake waiting to happen.

`newtype` costs nothing at runtime — GHC erases the wrapper entirely, so a
`NodeID` is an `Int64` in memory.

## `GraphError` instead of `error`

```haskell
data GraphError
  = MissingFromNode !NodeID
  | MissingToNode !NodeID
  | NegativeWeight !Double
```

Go returns `error`, an interface satisfied by anything with an `Error()` method,
so a caller learns what went wrong only by reading the message string. A closed
sum type says it in the type: a caller can pattern match on `MissingFromNode`
and handle it differently from `NegativeWeight`, and the compiler will tell them
if a new constructor appears.

**The three checks** are Go's, unchanged: both endpoints must already exist as
nodes, and the weight must be non-negative. The last one is load-bearing —
Dijkstra's optimality proof depends on it, because a negative edge can make an
already-settled node reachable more cheaply, and the algorithm never revisits
one. Enforcing it at construction means the search does not have to check.

A stricter design would make it unrepresentable — `newtype NonNegative = ...`
with a smart constructor — but the weight comes from a Haversine call that
cannot return a negative, so the check exists only to catch a caller
constructing edges by hand. Runtime validation is the right weight of solution
here.

## `lookupNode` returns `Maybe`, and this matters

```haskell
lookupNode :: NodeID -> Network -> Maybe Node
```

Go's `net.Nodes[id]` silently returns a **zero-valued `Node`** for an unknown
ID — ID 0, coordinate (0, 0). That is in the Gulf of Guinea, and the bug
surfaces much later as a route with a leg to the Atlantic rather than as an
error at the lookup.

`Services.Routing.resolveNodes` uses this to produce a slightly short polyline
rather than a line to the ocean if a node ever goes missing.

## `addEdge` prepends; `finalizeAdjacency` fixes the order

Appending to a linked list is O(n), so doing it per edge would make network
construction quadratic. `addEdge` prepends (O(1)) and leaves each adjacency list
in reverse insertion order; `finalizeAdjacency` reverses them all once at the
end, in O(E).

**Why bother restoring the order at all?** Because when two neighbours tie on
priority, the order they were pushed onto the heap decides which is settled
first — which changes the `visited_nodes` animation the frontend draws, and, on
a graph with equal-cost alternative routes, which route is returned. Reversing
here means the Haskell backend and the Go backend agree node-for-node, not
merely on total distance. The CLI parity check depends on it.

`Mapping.buildNetwork` calls it; hand-built test networks call it through
`TestSupport.mustNetworkWithCoords`.

## Two maps, not one

```haskell
data Network = Network
  { nodes     :: !(Map NodeID Node)
  , adjacency :: !(Map NodeID [Edge])
  }
```

They are read at different times — `nodes` for coordinate lookups during
snapping and result enrichment, `adjacency` during the search loop — so keeping
them separate avoids touching edge lists when only a coordinate is wanted.
`addNode` inserts an empty adjacency entry so `neighbours` can never be asked
about a node that exists but has no key.

## Poke it in the REPL

```
ghci> import Graph
ghci> let n1 = Node (NodeID 1) (Coord 0 0)
ghci> let net = addNode n1 empty
ghci> addEdge (Edge (NodeID 1) (NodeID 2) 5 0 "") net
Left (MissingToNode 2)
ghci> nodeCount net
1
```

That `Left` is the whole invariant story in one line: you cannot build an edge
into a node the network has never heard of.
