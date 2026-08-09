# `Routefinding/Bidirectional.hs` — bidirectional Dijkstra

The one algorithm here that is **not** a re-parameterisation of
`Routefinding.Search`. It runs two searches at once and has a genuinely
different stopping rule, so it gets a full implementation.

## What it does

Searches forward from the start and backward from the goal simultaneously,
stopping when the two frontiers can no longer improve on the best complete route
found so far.

## The Go code it replaces

`backend/routefinding/bidirectional_dijkstra.go`, including `reconstructBiPath`.

## Why it is faster

A one-directional Dijkstra that travels distance *d* settles roughly everything
within radius *d*. On a planar road network that is an area proportional to *d²*.

Two searches meeting in the middle each travel only *d/2*, so together they
cover `2 · (d/2)² = d²/2` — about **half** the work. On a road network with a
branching factor, the saving is larger still.

The animation makes this literal: two circles growing toward each other, meeting
in the middle, with everything beyond the meeting point never touched.

## The backward search

It must follow edges **into** a node, and `Graph.Network` only indexes outgoing
edges. So `reverseAdjacency` builds a flipped index once up front — O(E), where
doing it lazily per node would be O(E) per lookup.

On a network with one-way streets this genuinely matters. The backward search
traverses a one-way street *in the direction traffic actually flows*, because it
is walking reversed edges from the goal. Getting this wrong produces a router
that happily sends you the wrong way down a one-way street, and only on
asymmetric graphs — so the test suite checks it explicitly with a one-way pair.

## Which side to expand

Whichever heap's minimum is smaller. This keeps the two frontiers advancing at
the same *cost radius* rather than letting one race ahead — which is what makes
"meet in the middle" true rather than aspirational.

## The stopping rule — the subtle part

Track `mu`: the cheapest complete start→goal route seen so far, updated whenever
a node is known to **both** sides. Stop when

```
topForward + topBackward >= mu
```

**Why that is correct.** Any route not yet discovered must use at least one
unsettled node from each frontier, so it costs at least
`topForward + topBackward`. Once that sum reaches `mu`, no undiscovered route
can beat the one already in hand, and the search can stop.

**The classic bug** is stopping when the frontiers first *touch*. The first node
both searches reach is very often not on the optimal route: the forward search
may have arrived there expensively while a cheaper route through a neighbouring
node is one expansion away. Stopping there gives a plausible, wrong answer —
plausible enough to ship. The test suite pins this down by asserting that
bidirectional agrees with plain Dijkstra on both distance *and* path on a
corridor network.

## Reconstructing the path

Two halves, joined at `meetingNode`:

- **Forward half.** `forward.prev` points toward the start, so walk it backward
  from the meeting node, prepending as you go: `[start … meetingNode]`.
- **Backward half.** `backward.prev` deserves a careful read. An entry
  `prev[X] = Y` was written when the backward search relaxed the *reversed* edge
  X←Y, which means the **original** graph contains the edge X→Y. So
  `backward.prev` is already a map of "next hop toward the goal", and walking it
  *forward* gives `[meetingNode … goal]` in travel order — no reversal.

The two are concatenated with `drop 1` on the second, to remove the duplicated
meeting node.

## Complexity

O((V + E) log V) worst case, same as Dijkstra. The gain is in the constant, and
it is real on road networks. The test asserts strictly fewer settled nodes than
one-directional Dijkstra on a corridor with a branch.

## Guarantee

**Optimal**, given non-negative weights.

## Haskell design decisions

**A `Side` record, twice.** Both searches are ordinary Dijkstra searches
differing only in which adjacency they walk, so `expand` takes the active side,
the opposite side (read-only), and a neighbour function. Go writes the two
branches out in full, which is why its `for` loop is ~70 lines; here the loop is
a `case` choosing which side to pass in.

**`Set NodeID` for the settled set.** Go uses `map[NodeID]bool`, where every
value is `true` — a set spelled as a map because Go has no set type.

**One difference from Go, deliberately.** Go builds its reversed adjacency by
ranging over a map, and Go randomises map iteration order, so the order of edges
in each reversed list varies **run to run**. Here it is deterministic. On graphs
with equal-cost alternatives this means the Haskell backend can pick a different
route than a given Go run — but it picks the *same* one every time, which the Go
version cannot promise even against itself.
