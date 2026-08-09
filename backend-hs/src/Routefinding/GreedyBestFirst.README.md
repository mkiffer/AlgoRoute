# `Routefinding/GreedyBestFirst.hs` — greedy best-first search

```haskell
greedyBestFirst net start goal =
  bestFirstSearch (\_ h -> h) (haversineHeuristic net goal) net start goal
```

Read [`Search.README.md`](Search.README.md) first.

## What it does

Finds *a* path by always expanding whichever frontier node **looks** closest to
the goal. Not necessarily the shortest path — usually not, in fact.

## The Go code it replaces

`backend/routefinding/greedy_best_first.go`.

## Why it exists in AlgoRoute

As a teaching device. It is A* with the `g` term deleted, so putting the two
animations side by side shows exactly what that term was doing. Watching greedy
sprint down a corridor that points the right way and then have to back out is a
more convincing argument for A* than any amount of prose about admissible
heuristics.

## The idea, and why it fails

The priority is `h` alone: the path cost is still computed and recorded — it has
to be, or the reported distance would be meaningless — but it is thrown away
when deciding what to expand next.

Admissibility of `h` buys optimality only *in combination with* `g`. Alone, `h`
says "this node is 400 m from the goal" and nothing whatever about whether
reaching that node took 200 m or 20 km. So the search commits to whichever
corridor points most directly at the goal and follows it even when it is a long
way round: a dead-end street aimed at the goal beats a through-road aimed
slightly wrong. Only when that corridor is exhausted does it back out.

The test suite makes this concrete with a deliberately adversarial network:

| | route taken | distance |
|---|---|---|
| Dijkstra | the cheap road that starts by pointing away | 200 m |
| Greedy | the expensive road that starts by pointing at the goal | 100 km |

## Complexity

O((V + E) log V) — the same bound as the other three. In practice it usually
settles *fewer* nodes than A*, because it never expands anything sideways. That
is the trade: fastest search, worst answer.

## The reported distance is honest

`Search` accumulates the real edge-weight sum in its `costs` map regardless of
what the priority function looks at, so `RouteResult.distance` is the true
length of the path found — **not** the heuristic value that guided the search.

That is deliberate and worth preserving: it is what lets the frontend put
greedy's number next to Dijkstra's optimum and show the gap. The Go
implementation goes out of its way to keep the same property, and its comment
says so.

## One consequence worth knowing

Because priority ignores `g`, a node can be **settled before its cheapest path
is known**, and it is never re-expanded. A later relaxation may still improve
its recorded cost and parent, so the returned path is the best route *through
the nodes greedy happened to visit* — not the best route in the graph.

This means greedy's answer is not merely "some path": it is a locally-tidied
path through a badly chosen set of nodes. The Haskell port reproduces this
exactly, because it falls out of running the same skeleton with a different
priority. No special-casing was needed to make it wrong in the same way.

## When greedy is actually the right choice

Not never. When "a route now" beats "the route in a moment" — live re-routing
under a frame budget, or a first pass that a slower algorithm refines — trading
optimality for a smaller frontier is a real engineering decision. AlgoRoute
just makes the cost of that decision visible.
