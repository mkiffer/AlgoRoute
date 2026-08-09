# `Routefinding/Router.hs` — choosing an algorithm by name

The clearest place in this port where the idiomatic Go answer and the idiomatic
Haskell answer genuinely differ. Worth reading even if you skip the rest.

## What it does

Turns the wire string `"astar"` into something that can be run, and dispatches
to it.

## The Go code it replaces

`backend/routefinding/router.go` plus the algorithm constants and `switch` in
`backend/services/options.go` and `routing.go`.

## Go's answer: an interface

```go
type Router interface {
    Route(net *graph.Network, start, goal graph.NodeID) (RouteResult, error)
}

type DijkstraRouter struct{}
func (DijkstraRouter) Route(...) { return Dijkstra(...) }
// ...three more
```

Go's own comment explains the choice, and the reasoning is sound:

> The alternative — a switch on an algorithm name inside RoutingService.Route —
> was rejected because it would couple the service to every algorithm by name,
> requiring a change to the service each time a new algorithm is added.

In a language with no exhaustiveness checking, that is right. A `switch` with a
`default:` branch gives you no help at all when you add a fifth algorithm and
forget to wire it in: the code compiles, and the new algorithm silently falls
through to the default at runtime.

## Haskell's answer: a closed sum type

```haskell
data Algorithm = Dijkstra | AStar | GreedyBestFirst | BidirectionalDijkstra
```

This **inverts** the reasoning. A closed sum type gives the compiler the
complete list of algorithms, so adding a constructor turns every `case` that
does not handle it into a warning — and under `-Wall`, a build failure.

The coupling Go was avoiding becomes the mechanism that makes extension *safe*.
You cannot forget to wire a new algorithm into `runRouter`, `parseAlgorithm` or
`algorithmName`, because the compiler stops you at each one.

**Try it.** Add `| Bellman` to the type and run `cabal build`. You will get
exactly two errors, one per incomplete `case`, each naming the missing
constructor. That is the entire argument, and it takes thirty seconds to see.

## Two more things that fall out for free

```haskell
deriving stock (Eq, Show, Enum, Bounded)

allAlgorithms :: [Algorithm]
allAlgorithms = [minBound .. maxBound]
```

`allAlgorithms` can never drift out of sync with the type. It is used to build
the error message from `parseAlgorithm` ("valid options are …") and to drive the
tests, so both stay correct as the type grows — no hand-maintained list.

## When Go's answer would be right here too

If AlgoRoute were a library that third parties extended with their own
algorithms, a closed sum type would be exactly wrong: it cannot represent an
algorithm the library does not know about. The Haskell equivalent of Go's
interface is a **type class**, and that is what you would reach for:

```haskell
class Router r where
  route :: r -> Network -> NodeID -> NodeID -> Either RouteError RouteResult
```

That recovers Go's open world, and loses exhaustiveness checking — the same
trade, made in the same direction, for the same reason.

For four algorithms in one codebase, all known at compile time, the sum type is
strictly better. The rule of thumb: **closed sum type when you own every case,
type class when you do not.**

## The wire names are a contract

```haskell
algorithmName Dijkstra              = "dijkstra"
algorithmName AStar                 = "astar"
algorithmName GreedyBestFirst       = "greedy"
algorithmName BidirectionalDijkstra = "bidijkstra"
```

These must match `frontend/src/types.ts`:

```typescript
export type Algorithm = 'dijkstra' | 'astar' | 'greedy' | 'bidijkstra';
```

and the Go constants in `services/options.go`. A test asserts the exact list.

`parseAlgorithm ""` returns `Dijkstra`, matching Go's
`newRoutingServiceForAlgorithm`, so a client that omits the field keeps working.
