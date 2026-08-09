# `Routefinding/Types.hs` — what a search returns, and how it fails

## What it does

Two declarations, no logic. It exists as a leaf module so every algorithm can
import it without creating a cycle.

## The Go code it replaces

The `RouteResult` struct in `backend/routefinding/router.go`, and the
`fmt.Errorf` calls scattered through all four algorithm files.

## `RouteResult`

```haskell
data RouteResult = RouteResult
  { path         :: ![NodeID]   -- start to goal, inclusive
  , distance     :: !Double     -- total edge weight, metres for OSM data
  , visitedNodes :: ![NodeID]   -- settlement order
  }
```

Bundling three values into a record rather than returning a tuple is the same
reasoning Go's comment gives: a new field can be added without breaking every
call site. `visitedNodes` was exactly such an addition — it exists to drive the
frontend's traversal animation, and adding it cost one line here and nothing at
the call sites.

**`visitedNodes` is the interesting one.** It records nodes in the order they
were *settled* — popped from the priority queue with their final cost confirmed
— starting with the start node and ending with the goal. The frontend replays
it to show the search frontier expanding before revealing the chosen path, which
is what makes the difference between the four algorithms visible at all. Without
it, Dijkstra and A* would look identical: same path, same distance, no story.

## `RouteError`

```haskell
data RouteError
  = NoPathFound !NodeID !NodeID
  | NodeNotInNetwork !NodeID
```

Go builds a formatted string at four call sites, each prefixed with its
algorithm's name (`"dijkstra: no path from %v to %v"`). A sum type carries the
same facts **as data**: the layer that renders a user-facing message decides on
the wording once (`App.Error`), and the compiler checks that every case is
handled.

The practical difference: a caller who wants to react differently to "no path"
than to "bad node ID" can pattern match, rather than matching on message text.

**`NodeNotInNetwork` has no Go counterpart.** Go's `net.Nodes[goal]` silently
yields a zero-valued node for an unknown ID, so a bad goal produces a route
heading toward coordinate (0, 0) — in the Gulf of Guinea — instead of an error.
`Routefinding.Search` checks both endpoints before starting.

## Why strict fields

Every field is `!`. `RouteResult` is returned from a search that has already
done all the work, so there is nothing to gain from deferring evaluation, and a
lazy field would keep the entire search state alive in a thunk until someone
forced it. Strictness here is about *not retaining* the network, not about
speed.
