# `Services/Cache.hs` — Overpass responses, keyed by bounding box

## What it does

An in-memory map from `BBox` to the Overpass response for that box, safe to read
and write from many request threads at once.

## The Go code it replaces

`backend/services/network_cache.go`, replacing `sync.RWMutex` with a single
`TVar` under STM.

## Why cache at all

The common case is a user **comparing algorithms**: route with Dijkstra, then
hit A* on the same two addresses. Identical addresses give identical geocodes,
which give an identical bounding box — so the second request can skip an
Overpass call that took several seconds and returned several megabytes.

Without this, the comparison the whole app is built around is painfully slow.
And since the algorithm comparison is the *point* of AlgoRoute, the cache is not
an optimisation so much as a feature.

The key is the **box**, not the address pair, so two different address pairs
that happen to produce the same box — the same route requested in reverse, for
instance — also share the fetch.

## STM versus a mutex

Go:

```go
func (c *NetworkCache) Lookup(bbox geo.BBox) (overpass.Response, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    ...
}
```

Haskell:

```haskell
lookupCache (NetworkCache var) bbox = Map.lookup bbox <$> readTVarIO var
insertCache (NetworkCache var) bbox r = atomically (modifyTVar' var (Map.insert bbox r))
```

**There is no lock to take or release.** A `TVar` cannot be read outside a
transaction — the type system will not let you — so there is no unlock to
forget, no lock-ordering to get wrong, and no possibility of the `defer` being
omitted.

`modifyTVar'` is read-modify-write as **one atomic transaction**. Two concurrent
inserts cannot interleave into a lost update: STM detects that a transaction's
inputs changed underneath it and retries. Go's `Lock`/`Unlock` gives the same
guarantee, but only because the programmer paired them correctly.

**`readTVarIO`, not `atomically . readTVar`.** For a single read there is
nothing to make atomic — the value is read in one step regardless — so
`readTVarIO` skips the transaction log entirely. Cheaper, and it cannot conflict
with anything. Using `atomically (readTVar var)` here would be correct but
wasteful, and it is a common thing to see.

**`modifyTVar'`, not `modifyTVar`.** The `'` makes the new map strict. Without
it the cache would hold a chain of pending `Map.insert` thunks, and the memory
would be retained until something forced them — the classic STM space leak.

There is a test that forks 50 threads inserting concurrently and asserts all 50
entries survive. Under a naive read-then-write it loses entries.

## What this deliberately does not do

**No eviction, no TTL, no size bound** — an unbounded map, exactly as in Go. A
long-running server routing many distinct areas will grow its memory without
limit.

That is a known and accepted trade-off for a demo backend; `PROJECT_STATE.md`
lists "cache eviction / TTL" as a next step. Adding an LRU bound would be the
first change if this ever ran in earnest, and it is confined to this module.

## Exact float keys

`BBox` derives `Ord` structurally over four `Double`s, so lookups are **exact
floating-point equality**. A geocode that shifts by a billionth of a degree
misses the cache rather than silently returning data for a slightly different
area.

That is the right trade — a near-miss returning the wrong area's road network
would be a far worse bug than an extra fetch — but it is worth knowing, and
there is a test pinning it down.

## A note for the Lambda deployment

AWS reuses a warm Lambda instance across invocations, and this `TVar` lives as
long as the process. So the cache **survives between requests on a warm
instance** exactly as it does on a long-running server, and is simply empty on a
cold start.

No Redis required — the same behaviour the Go backend has today. The rewrite
plan calls this out too.

## Poke it in the REPL

```
ghci> import Services.Cache
ghci> import Geo.Types
ghci> import Overpass.Types
ghci> c <- newCache
ghci> lookupCache c (BBox 0 0 1 1)
Nothing
ghci> insertCache c (BBox 0 0 1 1) emptyResponse
ghci> cacheSize c
1
```
