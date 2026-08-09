# `Routefinding/Search.hs` — the shared best-first search

## What it does

One function, `bestFirstSearch`, which **is** Dijkstra, A* and greedy
best-first. The three differ by a single argument.

## The Go code it replaces

Three files — `dijkstra.go`, `astar.go`, `greedy_best_first.go` — of about
ninety lines each, of which roughly eighty are identical: the same cost map, the
same heap loop, the same relaxation, the same path reconstruction, the same
`visitedOrder` bookkeeping.

Go's comments acknowledge the duplication (`astar.go` says "identical structure
to Dijkstra"). It is not a failing of the Go code; there is no comfortable way
to factor it out there without passing a function value into a generic search and
losing the readability that three separate files buy.

In Haskell, passing a function is the ordinary thing to do. So the shared 80% is
here, and each algorithm module states only its own idea.

## Algorithm

```
push start onto the frontier
loop:
    pop the lowest-priority node  →  it is now settled, record it
    if it is the goal, stop
    for each outgoing edge:
        if this route is cheaper than the best known one to the neighbour:
            record the new cost and parent
            push (or decrease-key) the neighbour with its new priority
```

**Complexity:** O((V + E) log V). Each node is pushed and popped at most once
(the indexed heap guarantees one entry per node), each edge triggers at most one
decrease-key, and every heap operation is O(log V).

**Why a pop is final.** With non-negative weights, when a node is popped nothing
still on the frontier can reach it more cheaply — everything else already costs
at least as much and can only grow. So each node is settled exactly once and
never revisited, and the loop can stop the instant the goal is settled. (For A*
this needs the heuristic to be *consistent*, not merely admissible; Haversine
is, because it obeys the triangle inequality.)

**Where it does not hold.** Greedy best-first orders by `h` alone, so its pops
are *not* final and its answer is not optimal. It still runs correctly through
this same skeleton — see `GreedyBestFirst.README.md` for what it costs.

## The priority function

```haskell
type PriorityFn = Double -> Double -> Double   -- g -> h -> priority
```

| Algorithm | `PriorityFn` | Orders the frontier by |
|---|---|---|
| Dijkstra | `\g _ -> g` | what the path has cost so far |
| A* | `\g h -> g + h` | estimated cost of the whole journey |
| Greedy best-first | `\_ h -> h` | how close the goal looks |

**Laziness makes the abstraction free.** `\g _ -> g` never forces its second
argument, so no heuristic is ever computed for Dijkstra — even though the
signature says it takes one. In a strict language this factoring would cost a
Haversine call per relaxation; here it costs nothing. This is one of the few
places where laziness pays a concrete, measurable dividend rather than merely
being something to be careful about.

## Haskell design decisions

**Loop state becomes function parameters.** Go declares four mutable locals —
`openSet`, `bestKnownCostTo`, `arrivedViaNode`, `visitedOrder` — and updates them
in place. Here they are the fields of a `SearchState` that each iteration
returns a new version of, and the "loop" is a tail-recursive call. This is *the*
shape change when porting imperative code, and GHC compiles a tail call to a
jump, so there is no stack growth.

**Absent means infinite.** Go pre-fills `bestKnownCostTo` with `+Inf` for every
node in the network — an O(V) pass over a map where most entries are never
touched. Here a node simply absent from `costs` has infinite cost
(`Map.findWithDefault infinity`). Same statement, no initialisation pass, and
the "have I reached this node?" question becomes a lookup rather than a
comparison against infinity.

**`settled` is built backwards.** Prepending to a list is O(1), appending is
O(n). The list is accumulated in reverse and flipped once at the end — the
standard Haskell idiom, and the reason you will see `reverse state.settled` in
`finish`.

**Path reconstruction has fuel.** Go writes

```go
for current := goal; current != start; current = arrivedViaNode[current] {
```

which loops forever if the parent map is ever cyclic or broken, because a
missing key yields the zero `NodeID`, which maps to the zero `NodeID` again. The
Haskell version carries a counter bounded by the node count. It costs one `Int`
and removes a class of hang. This is a deliberate improvement over the original,
not a translation.

**`NodeNotInNetwork`.** Go's A* reads `net.Nodes[goal].Coord` for a goal that may
not exist, silently getting a zero-valued node at coordinate (0, 0) — so a bad
goal ID produces a route heading for the Gulf of Guinea rather than an error.
Both endpoints are checked up front here.

## Poke it in the REPL

```
ghci> import Routefinding.Search
ghci> import Routefinding.Dijkstra
ghci> :type bestFirstSearch
bestFirstSearch :: PriorityFn -> Heuristic -> Network -> NodeID -> NodeID
                -> Either RouteError RouteResult
ghci> :info dijkstra
dijkstra = bestFirstSearch (\g _ -> g) noHeuristic
```

Then build a small network by hand (see `test/TestSupport.hs` for the helper)
and compare `visitedNodes` between `dijkstra` and `aStar` on the same pair.
Watching that list get shorter is the entire argument for heuristics.
