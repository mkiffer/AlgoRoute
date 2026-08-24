# AlgoRoute Haskell Rewrite — Pair-Programming & Tutor Guide

A companion to [`../haskell-rewrite-plan.html`](../haskell-rewrite-plan.html). The plan says *what* to
build; this file is how to build it *with Claude Code as a tutor* when you're coming from C#/Go and
new to Haskell + Nix. Keep it open in the session.

---

## How to use this file with Claude Code

**Your working agreement — paste this at the start of a session:**

> You are my Haskell/Nix tutor and pair programmer. I have a C# and Go background and I'm porting
> the AlgoRoute Go backend to Haskell. For each piece of work:
> 1. Explain the concept first, in C#/Go terms, before writing code.
> 2. Follow TDD — write a failing HSpec test first, show it fail, then implement the minimum.
> 3. Work in small steps and stop at each checkpoint so I can ask questions.
> 4. When you use a new language feature or extension, name it and say why.
> Don't dump a whole module at once — teach it to me as we go.

**Two modes, ask for the one you want:**
- *Tutor mode* — "Explain X, then let me try it myself." Claude explains and hands you the keyboard.
- *Pair mode* — "Let's implement X together." Claude writes with you, narrating decisions.

**Golden rule:** if Claude writes code you don't understand, stop and ask "why this, not that?"
The point of the rewrite is to learn Haskell, not to end up with a black box.

**Local reference notes.** If a `NOTES.local.md` file is present alongside this one, it holds
curated reference material (gitignored, not shared). Ask the tutor to consult it:
> Consult `NOTES.local.md` and align our approach to those idioms where sensible; flag where our
> plan or code diverges, and explain the trade-off.

---

## Part 1 — Mental models

### 1a. Haskell for a C#/Go developer

The plan's C#→Haskell table covers the basics. These are the ideas that actually trip people up:

| Concept | What to internalise |
|---|---|
| **Purity** | A function with type `a -> b` *cannot* do IO, mutate, or throw. If it touches the outside world its type says `IO`. This is enforced by the compiler, not convention. |
| **Laziness** | Nothing is evaluated until forced. `let x = expensive` costs nothing until `x` is used. Great for `where` helpers; a footgun for space leaks (use `Data.Map.Strict`, not lazy `Map`). |
| **`Maybe a`** | Go's `(v, ok)` / C#'s `null`, but the compiler *forces* you to handle the `Nothing` case. |
| **`Either e a`** | Go's `(v, err)`. `Left` = error, `Right` = success. Pure error handling, no exceptions. |
| **`IO a`** | A *value describing an effect*, not the effect itself. `main :: IO ()` is "the program." Think C# `Task<a>` that only runs when the runtime executes it. |
| **`ExceptT e IO a`** | `IO` **and** `Either e` stacked: an effectful computation that can short-circuit with a typed error. This is your whole service pipeline. ≈ `async Task<a>` that can throw a typed `e`. |
| **Type classes** | C# interfaces, but resolved by *type* at compile time, not carried on the object. `class Router r where route :: ...` ≈ `interface IRouter`. |
| **Functor / Applicative / Monad** | Three levels of "map over a context." `fmap`/`<$>` = `.Select`. `<*>` = combine independent wrapped values. `>>=`/`do` = sequence dependent effectful steps. You'll mostly use `do`-notation and rarely think about the names. |
| **`do`-notation** | Sugar for chaining `>>=`. Reads like imperative code (`x <- action`) but works for any monad — `IO`, `Maybe`, `Either`, `ExceptT`, `Handler`. |
| **Records & fields** | `data Foo = Foo { x :: Int }` auto-generates `x :: Foo -> Int`. **Gotcha below.** |

**The record-field gotcha you WILL hit.** The plan's types reuse field names across records —
`lat`/`lon` appear on `Coord`, `PathNode`, `CoordJSON`, `SuggestResult`; `nodeId` on `Node` and
`PathNode`; `elemId` on both `Element` constructors. Classic Haskell rejects that (one top-level
`lat` function can't have four types). `GHC2021` alone doesn't fix it. Ask Claude to enable, per
module:
- `{-# LANGUAGE DuplicateRecordFields #-}` — lets multiple records share a field name.
- `{-# LANGUAGE OverloadedRecordDot #-}` — lets you write `coord.lat` instead of `lat coord`,
  disambiguating by the record's type (very C#-like).

When you hit "ambiguous occurrence `lat`", that's this — ask the tutor to walk through it once.

### 1b. Nix for this project

You don't need to master Nix — you need four ideas:

| Idea | What it means here |
|---|---|
| **Flake** | `flake.nix` = a pinned, reproducible description of inputs (nixpkgs) and outputs (dev shell, binary, Lambda zip). `flake.lock` freezes exact versions so builds are identical everywhere. |
| **Dev shell** | `nix develop` drops you into a shell where `ghc`, `cabal`, `haskell-language-server`, `hlint`, `fourmolu` all exist — without installing anything globally. This is where you live. |
| **`callCabal2nix`** | Reads `backend-hs.cabal` and auto-generates the Nix build. You edit the `.cabal`; Nix figures out the rest. |
| **`pkgsStatic` / musl** | A second build variant that links statically for AWS Lambda. Ignore it until Phase 9. |

**Key habit:** the `.cabal` file is the source of truth for dependencies and modules. Add a new
module file → add it to `exposed-modules`. Need a new library → add it to `build-depends`. Then
re-enter/reload. If you're confused why an `import` won't resolve, it's almost always a missing
`build-depends` entry.

---

## Part 2 — Daily workflow

```bash
cd backend-hs
nix develop                 # enter the toolchain shell (do this first, every session)

# inside the dev shell:
cabal build                 # compile everything
cabal repl backend-hs       # REPL — load the library, poke at functions interactively
cabal test                  # run the HSpec suite (once Part 3 adds it)
fourmolu -i src app         # auto-format in place
hlint src app               # lint suggestions
```

**REPL-driven development is your fastest feedback loop** (much faster than Go's edit-compile-run).
In `cabal repl` you can `:reload` after edits, call a function with sample input, and `:type expr`
to ask "what type is this?". Ask the tutor to show you a REPL session for each pure module — it's
the best way to build intuition.

**Optional but worth it:** `ghcid` gives you a live-recompiling window that shows errors on every
save. Ask Claude to add it to the dev shell's `packages` list in `flake.nix`.

---

## Part 3 — Module-by-module learning path

Follow the plan's **port order** (bottom-up: pure code first, IO last). For each module below:
the Go source to port from, the *new* concept it teaches, a copy-paste tutor prompt, and a
**checkpoint** that means "done, move on."

> Reuse the existing test fixtures. The Go `testdata/*.json` files (same 3-node Melbourne sample)
> work as-is for the Haskell JSON-parsing tests — don't invent new ones.

### Step 1 — `Graph.hs` + `Routefinding/` (pure, no IO)
- **Port from:** `backend/graph/`, `backend/routefinding/`
- **Teaches:** data declarations, records, `Data.Map.Strict`, pattern matching, recursion instead of
  loops, `Either` for "no path found".
- **The mindset shift:** the Go `for` loop that mutates a heap and a costs-map becomes a
  *tail-recursive* function that takes the heap+costs as arguments and returns the next call's
  arguments. "Loop state" becomes "function parameters."
- **Prompt:**
  > Let's port `graph` and `routefinding` to Haskell. Start with `Graph.hs` — explain the data
  > declarations in C# terms, then let me write them. Then we TDD the indexed heap: failing HSpec
  > test first. Show me how the Go while-loop in Dijkstra maps to a tail-recursive `go` helper.
- **Checkpoint:** `Dijkstra` and `AStar` pass tests on a hand-built `Network`; you can explain why
  A*'s only change is `priority = g + haversine`.

### Step 2 — `Overpass/Types.hs` (pure, JSON)
- **Port from:** `backend/api/overpass/` DTOs
- **Teaches:** sum types (discriminated unions), custom `FromJSON` instances, `aeson`.
- **The interesting bit:** Go tags `Element` with a `type` string field; Haskell models it as a real
  sum type `data Element = NodeElement {…} | WayElement {…}` and a hand-written `FromJSON` that reads
  the `"type"` field to pick the constructor. This is where a C# discriminated-union instinct pays off.
- **Prompt:**
  > Port `Overpass/Types.hs`. Explain sum types vs Go's string-tagged struct. TDD a custom `FromJSON`
  > for `Element` against the existing `testdata/sample_overpass.json` — failing test first.
- **Checkpoint:** parsing the fixture yields the right `NodeElement`/`WayElement` values.

### Step 3 — `Geo/` + `Overpass/Client.hs` (first IO)
- **Port from:** `backend/geo/`, `backend/api/overpass/fetch.go`
- **Teaches:** `IO`, `ExceptT e IO`, `http-client` (`Manager`, requests), the `Env` record pattern.
- **Watch out:** Nominatim returns `lat`/`lon` as JSON **strings** — parse with `read @Double`, same
  as Go's `strconv.ParseFloat`. And keep `Geo/Distance.hs` (Haversine) **pure** — no IO — it's just math.
- **Prompt:**
  > Introduce IO. Port `Geo/Distance.hs` as a pure function (TDD it first), then `Geo/Geocode.hs`
  > using `ExceptT GeoError IO`. Explain what `Manager` is and why we create one `Env` at startup
  > and thread it through, in C# scoped-singleton terms.
- **Checkpoint:** Haversine matches the Go results; a geocode call returns `Right coord` for a real
  address and `Left err` on failure.

### Step 4 — `Mapping.hs` (pure transform)
- **Port from:** `backend/mapping/`
- **Teaches:** `foldl'` as a replacement for nested loops; building a `Map` incrementally.
- **Prompt:**
  > Port `Mapping.hs`. Show how the Go nested loop (ways → consecutive node pairs → edges) becomes a
  > `foldl'` over ways where each way folds over its pairs. TDD against the fixture.
- **Checkpoint:** the fixture produces the same `Network` (node count, edge count, oneway handling)
  as the Go `mapping` tests.

### Step 5 — `Services/` (IO + concurrency)
- **Port from:** `backend/services/`
- **Teaches:** `STM`/`TVar` (vs Go `sync.RWMutex`), the `ExceptT` orchestration pipeline, `liftEither`.
- **The payoff:** the 7-step Go pipeline becomes one readable `do` block that short-circuits on the
  first `Left`, exactly like early-return-on-error but without the `if err != nil` noise.
- **Prompt:**
  > Port `Services/Cache.hs` with a `TVar (Map BBox Response)` — explain `atomically` vs a mutex.
  > Then build the `routeByAddress` pipeline in `ExceptT AppError IO`; explain `liftEither` and where
  > each early-return maps to a `throwError`.
- **Checkpoint:** cache hit/miss works; the pipeline returns typed errors (`AreaTooLarge`, etc.)
  matching the Go behavior.

### Step 6 — `API/` (HTTP)
- **Port from:** `backend/server/`
- **Teaches:** Servant's type-level API, `Server`/`Handler`, `:<|>`, CORS middleware.
- **The wild part:** the entire API surface is a *type*. Servant checks your handlers against it at
  compile time — wrong response shape = type error, not a runtime 500. Ask the tutor to slow down here.
- **Prompt:**
  > Explain the Servant `API` type piece by piece (`:>`, `ReqBody`, `QueryParam`, `:<|>`). Then wire
  > `server env` and the three handlers. Show how `Handler` is already `ExceptT ServerError IO` so our
  > pipeline errors convert cleanly.
- **Checkpoint:** `hspec-wai` tests hit all three endpoints and match the existing JSON contract.

### Step 7 — `app/Main.hs` (wiring)
- **Teaches:** `optparse-applicative` (CLI flags), `warp` `run`, and the `#ifdef LAMBDA` split between
  the local server and the HAL Lambda entry point (this is why the `.cabal` has two executables).
- **Prompt:**
  > Wire `Main.hs`: local Warp server with `optparse-applicative` flags first. Then add the
  > `#ifdef LAMBDA` branch and explain how `cpp-options: -DLAMBDA` in the `.cabal` selects it.
- **Checkpoint:** `cabal run backend-hs-local -- --port 8080` serves the real API; the existing
  frontend talks to it unchanged.

### Step 8 — `flake.nix` Lambda build (infra) — Phase 9, do last.

---

## Part 4 — Reusable prompts

- **"Explain this Go code, then let me port it":**
  > Read `backend/<path>.go`. Explain what it does, then help me port it to `<module>.hs` TDD-style —
  > failing test first. Don't write the implementation until I've seen the test fail.
- **"I don't understand this type error":**
  > Here's a GHC error: `<paste>`. Explain what it means in plain terms, what likely caused it, and the
  > smallest fix — teach me the underlying rule, don't just patch it.
- **"Is this idiomatic?":**
  > Review `<module>.hs` for idiomatic Haskell and run `hlint` mentally. Suggest improvements and
  > explain the reasoning in C#/Go terms.
- **"Quiz me":**
  > Ask me 3 questions about what we just built (`<module>`) to check I actually understand it.

---

## Part 5 — Cheatsheet

```haskell
x <- action            -- bind the result of an effect (in a do-block)
let y = pureExpr       -- bind a pure value (no <-)
f <$> mx               -- fmap: apply pure f to a wrapped value      (C# mx.Select(f))
mf <*> mx              -- apply a wrapped function to a wrapped value
mx >>= f               -- bind: feed result of mx into f :: a -> m b (what do-notation desugars to)
pure x / return x      -- wrap a plain value into the monad
throwError e           -- short-circuit an ExceptT / Handler with error e
liftEither (Left e)    -- turn an Either into an ExceptT (propagates the error)
liftIO action          -- run an IO action inside a bigger monad (ExceptT, Handler)
maybe d f mx           -- handle Maybe: default d if Nothing, else f on the value
either fL fR ex        -- handle Either: fL on Left, fR on Right
:type expr             -- (REPL) show the type of expr
:reload / :r           -- (REPL) reload after editing
```

**When stuck, in order:** read the type signature → ask the REPL `:type` → ask the tutor to explain
the *type*, not just the code → only then look at implementation. In Haskell, the types are the
documentation.
