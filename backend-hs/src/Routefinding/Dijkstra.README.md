# `Routefinding/Dijkstra.hs` — Dijkstra's algorithm

```haskell
dijkstra = bestFirstSearch (\g _ -> g) noHeuristic
```

That is the whole module. Everything else lives in
[`Search.README.md`](Search.README.md), which you should read first.

## What it does

Finds the genuinely shortest path by total edge weight, from one node to another
in a directed graph with non-negative weights.

## The Go code it replaces

`backend/routefinding/dijkstra.go` — 90 lines, of which 80 are the shared search
skeleton and 1 is the priority decision.

## The idea

Always expand the frontier node with the smallest known cost from the start.

Because every edge weight is non-negative, the first time a node is popped no
cheaper route to it can still exist: everything else on the frontier already
costs at least as much, and can only get more expensive from there. So each pop
*finalises* a node, and the algorithm never revisits one. That is both the
correctness argument and the reason the loop can stop the moment the goal is
popped rather than running the frontier dry.

## Complexity

O((V + E) log V) with the indexed binary heap:

- V pushes and V pops, each O(log V);
- at most E decrease-key operations, each O(log V).

With a naive array scan instead of a heap it would be O(V² + E), which is
actually *faster* on very dense graphs (E ≈ V²) — but road networks are sparse
(E ≈ 2–3 V), so the heap wins comfortably.

## Guarantee

**Optimal.** The returned distance is the true shortest. The tests assert that
A* and bidirectional Dijkstra agree with it exactly, which is how those two are
checked.

## Precondition: non-negative weights

Dijkstra's correctness argument fails with a negative edge, because a node
already settled could later become reachable more cheaply — and it is never
revisited. `Graph.addEdge` rejects negative weights at construction, so a
`Network` cannot violate this and the search does not have to check.

(If AlgoRoute ever grew "roads with a rebate", the answer would be Bellman-Ford,
not a patched Dijkstra.)

## What the animation shows

An **even circle** growing outward from the start. Equal cost means equal
radius, and Dijkstra has no idea where the goal is, so it explores just as
eagerly in the wrong direction as the right one. Half the settled nodes are
typically behind you.

Run the same route with A* and watch the circle become a cone. That side-by-side
is the clearest possible demonstration of what a heuristic buys, and it is why
this app draws `visited_nodes` at all.

## Why the module is three lines

The temptation when porting is to keep the 90-line file and change one
expression, mirroring Go. Resisting that is the point: once `Search` exists,
"Dijkstra is best-first search ordered by cost-so-far" is a *complete*
definition, and writing anything more would be restating the shared parts.

If you want to see the full loop, read `Search.hs` — but read it once, not three
times.
