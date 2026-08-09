{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Routefinding.Heap
-- Description : Binary min-heap with O(1) membership and O(log n) decrease-key.
--
-- Ports @backend/routefinding/indexed_heap.go@.
--
-- The distinguishing feature — and the reason it is called /indexed/ — is the
-- side map from node ID to array position. Without it, lowering a node's
-- priority means finding it first, which is O(n). With it, the lookup is O(1)
-- and only the re-heapify costs O(log n). That in turn means the heap holds at
-- most one entry per node, so its size is bounded by the node count rather
-- than by the number of edge relaxations.
module Routefinding.Heap
  ( -- * Type
    IndexedHeap
  , Entry (..)

    -- * Construction
  , empty
  , push

    -- * Queries
  , size
  , isEmpty
  , member
  , peekMin

    -- * Modification
  , popMin
  , decreasePriority
  ) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Sequence (Seq, (|>))
import Data.Sequence qualified as Seq
import Graph (NodeID)

-- | One heap slot: a node and the priority it is ordered by.
--
-- What \"priority\" means is the caller's business. Dijkstra puts the path cost
-- @g@ there, A* puts @g + h@, and greedy best-first puts @h@ alone — which is
-- the entire difference between those three algorithms. See "Routefinding.Search".
data Entry = Entry
  { node :: !NodeID
  , priority :: !Double
  }
  deriving stock (Eq, Show)

-- | A min-heap keyed on 'Entry' priority, with a position index.
--
-- __Representation.__ Go uses @[]ipqEntry@ plus @map[NodeID]int@. The direct
-- Haskell analogue of a growable array with O(log n) indexed update is
-- 'Data.Sequence.Seq' (a finger tree), so the two fields line up one-to-one
-- with the Go struct. A plain list would not do: @siftDown@ needs to read and
-- write element /i/ repeatedly, which is O(n) on a list.
--
-- __Invariants__ (the same ones Go maintains, here uncheckable by the type
-- system but enforced by every operation in this module):
--
-- 1. Heap property — every entry's priority is ≤ both of its children's.
-- 2. @index@ maps each present node to its exact position in @entries@.
-- 3. No node appears twice in @entries@.
--
-- Because the whole structure is immutable, an operation cannot leave it
-- half-updated: either you get back a heap satisfying all three invariants, or
-- you still hold the old one.
data IndexedHeap = IndexedHeap
  { entries :: !(Seq Entry)
  , index :: !(Map NodeID Int)
  }
  deriving stock (Eq, Show)

-- | The empty heap.
empty :: IndexedHeap
empty = IndexedHeap {entries = Seq.empty, index = Map.empty}

-- | Number of entries. O(1).
size :: IndexedHeap -> Int
size h = Seq.length h.entries

-- | Is the heap empty? O(1).
isEmpty :: IndexedHeap -> Bool
isEmpty h = Seq.null h.entries

-- | Is this node currently in the heap? O(log n) — the whole point of the
-- index map. Go calls this @Contains@.
member :: NodeID -> IndexedHeap -> Bool
member nodeID h = Map.member nodeID h.index

-- | The minimum entry, without removing it. O(1).
--
-- Go has no @Peek@ method; "Routefinding.Bidirectional" reaches into
-- @h.entries[0]@ directly to test its termination condition. Exposing it as a
-- function keeps the representation private.
peekMin :: IndexedHeap -> Maybe Entry
peekMin h = case Seq.lookup 0 h.entries of
  Nothing -> Nothing
  Just entry -> Just entry

-- | Insert a node with a priority. O(log n).
--
-- The caller must ensure the node is not already present — same precondition
-- as Go's @Push@. Every call site in this codebase guards with 'member' first
-- and calls 'decreasePriority' otherwise.
--
-- Appends at the end, then sifts the new entry up to its correct depth.
push :: NodeID -> Double -> IndexedHeap -> IndexedHeap
push nodeID nodePriority h = siftUp position placed
  where
    position = Seq.length h.entries
    placed =
      IndexedHeap
        { entries = h.entries |> Entry {node = nodeID, priority = nodePriority}
        , index = Map.insert nodeID position h.index
        }

-- | Remove and return the minimum entry. O(log n).
--
-- The standard array-heap dance, identical to Go's: swap the root with the last
-- element, drop the (now-last) root, then sift the promoted element back down.
--
-- Returning @Maybe (Entry, IndexedHeap)@ rather than Go's bare @ipqEntry@ is
-- the real improvement here. Go's @Pop@ indexes @h.entries[0]@ unconditionally
-- and panics on an empty heap; the caller is trusted to have checked @Len() > 0@
-- first. Here the empty case is in the type, so it cannot be forgotten.
popMin :: IndexedHeap -> Maybe (Entry, IndexedHeap)
popMin h
  | Seq.null h.entries = Nothing
  | otherwise = Just (root, rebuilt)
  where
    root = Seq.index h.entries 0
    lastPosition = Seq.length h.entries - 1

    -- Move the root to the end so removing it is a cheap truncation.
    swapped = swap 0 lastPosition h
    trimmed =
      IndexedHeap
        { entries = Seq.deleteAt lastPosition swapped.entries
        , index = Map.delete root.node swapped.index
        }
    rebuilt
      | Seq.null trimmed.entries = trimmed
      | otherwise = siftDown 0 trimmed

-- | Lower an existing node's priority and restore the heap property.
-- O(log n).
--
-- A no-op if the node is absent, or if the new priority is not actually lower
-- — both guards copied from Go. The second one matters for correctness as well
-- as speed: raising a priority would require 'siftDown', not 'siftUp', so
-- silently accepting a higher value would corrupt the heap.
decreasePriority :: NodeID -> Double -> IndexedHeap -> IndexedHeap
decreasePriority nodeID newPriority h =
  case Map.lookup nodeID h.index of
    Nothing -> h
    Just position
      | newPriority >= (Seq.index h.entries position).priority -> h
      | otherwise -> siftUp position (setPriority position newPriority h)

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

-- | Overwrite the priority at a position, leaving the index map untouched
-- (the node has not moved).
setPriority :: Int -> Double -> IndexedHeap -> IndexedHeap
setPriority position newPriority h =
  h {entries = Seq.adjust' (\e -> e {priority = newPriority}) position h.entries}

-- | Exchange two entries, keeping the index map in step.
--
-- Forgetting to update the index is the classic bug in this data structure —
-- the heap stays valid but @member@ and @decreasePriority@ start operating on
-- the wrong slot. Confining every swap to this one function is why that bug
-- cannot happen here (or in the Go original, which does the same).
swap :: Int -> Int -> IndexedHeap -> IndexedHeap
swap i j h
  | i == j = h
  | otherwise =
      IndexedHeap
        { entries = Seq.update i atJ (Seq.update j atI h.entries)
        , index = Map.insert atI.node j (Map.insert atJ.node i h.index)
        }
  where
    atI = Seq.index h.entries i
    atJ = Seq.index h.entries j

-- | Move an entry toward the root until its parent is no larger.
--
-- Go writes this as @for pos > 0 { … pos = parent }@. Here the loop variable is
-- the recursive call's argument — the single most common shape change when
-- porting imperative code, and a tail call, so GHC compiles it to a jump with
-- no stack growth.
siftUp :: Int -> IndexedHeap -> IndexedHeap
siftUp position h
  | position <= 0 = h
  | priorityAt h position >= priorityAt h parent = h
  | otherwise = siftUp parent (swap position parent h)
  where
    parent = (position - 1) `div` 2

-- | Move an entry toward the leaves until both children are no smaller.
siftDown :: Int -> IndexedHeap -> IndexedHeap
siftDown position h
  | smallest == position = h
  | otherwise = siftDown smallest (swap position smallest h)
  where
    count = Seq.length h.entries
    left = 2 * position + 1
    right = 2 * position + 2

    smallestOfLeft
      | left < count && priorityAt h left < priorityAt h position = left
      | otherwise = position
    smallest
      | right < count && priorityAt h right < priorityAt h smallestOfLeft = right
      | otherwise = smallestOfLeft

-- | Priority at a position. Partial by construction: every caller has already
-- bounds-checked against 'Seq.length'.
priorityAt :: IndexedHeap -> Int -> Double
priorityAt h position = (Seq.index h.entries position).priority
