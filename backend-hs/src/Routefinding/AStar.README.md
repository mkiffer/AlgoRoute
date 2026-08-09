# `Routefinding/AStar.hs` — A* search

```haskell
aStar net start goal =
  bestFirstSearch (\g h -> g + h) (haversineHeuristic net goal) net start goal
```

Read [`Search.README.md`](Search.README.md) first; the loop lives there.

## What it does

Finds the shortest path, but explores toward the goal instead of in all
directions.

## The Go code it replaces

`backend/routefinding/astar.go`, whose own comment says "Identical structure to
Dijkstra. Only difference: priority = g + haversine current goal." Here that
sentence is the implementation.

## The idea

Dijkstra orders the frontier by `g` — what a node has cost so far. A* orders it
by

```
f(n) = g(n) + h(n)
```

where `h(n)` estimates what remains. Nodes that are cheap to reach **and** point
toward the goal are expanded first, so the search elongates along the goal
direction rather than spreading evenly.

`h = 0` recovers Dijkstra exactly. Dropping `g` gives greedy best-first. A* is
the point on that dial that is both informed and still correct.

## The heuristic, and why it stays optimal

`h` is the great-circle (Haversine) distance from the node to the goal.

**Admissible** — never overestimates. A great circle is the shortest path
between two points on a sphere; roads bend, climb and detour, so the true road
distance is always at least the straight-line distance. Admissibility is what
guarantees A* returns the *optimal* path.

**Consistent** — obeys the triangle inequality: `h(a) ≤ cost(a,b) + h(b)` for
every edge. This is the stronger property, and it is what lets the search settle
each node exactly once and stop the instant the goal is popped. Without it, A*
would need to re-open settled nodes.

Both hold for Haversine on any road network whose weights are real distances —
which is exactly what `Mapping` produces. The test suite asserts the consequence
directly: A* and Dijkstra return the same distance.

**Where it would break.** If edge weights became travel *times* while `h` stayed
a *distance*, `h` would overestimate on fast roads and A* would quietly stop
being optimal. The fix is to divide `h` by the maximum speed on the network —
worth knowing, because "we switched to time-based weights" is the most common
way a working A* silently becomes wrong.

## Complexity

O((V + E) log V), the same worst case as Dijkstra. **The heuristic changes the
constant, not the bound.** On a graph with no useful geometry — a maze, a
network where the straight line is always blocked — A* degenerates to Dijkstra
and settles the same nodes. On real roads it typically settles a small fraction.

The test suite asserts "no more than Dijkstra" on a grid where routes tie, and
"strictly fewer" on a network with cheap roads leading away from the goal. That
second fixture is the interesting one: an *expensive* detour proves nothing,
because Dijkstra would not expand it either.

## What the animation shows

A **cone** stretching from start toward goal, instead of Dijkstra's circle. The
`visited_nodes` list is markedly shorter on the same route.

## Poke it in the REPL

```
ghci> import Routefinding.AStar
ghci> import Routefinding.Dijkstra
ghci> import Routefinding.Types
-- build a network (see test/TestSupport.hs), then:
ghci> fmap (length . visitedNodes) (aStar net start goal)
ghci> fmap (length . visitedNodes) (dijkstra net start goal)
ghci> fmap distance (aStar net start goal) == fmap distance (dijkstra net start goal)
True
```

The last line is admissibility, checked by hand. The two before it are the
reason anyone bothers.
