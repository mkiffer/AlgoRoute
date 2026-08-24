-- | Indexed binary min-heap with O(1) membership and O(log n) decrease-key.
-- Port of Go @routefinding/indexed_heap.go@.
--
-- This is the trickiest pure module: the Go version mutates a slice and an
-- index map in place; here every operation returns a new 'IndexedHeap'. Do it
-- TDD-first — the heap invariant is easy to get subtly wrong.
--
-- Internally mirror the Go layout: a 'Seq' of entries (random-access array)
-- plus a @Map NodeID Int@ from node to its position, kept in sync on every
-- swap. Keep the constructors hidden so the invariant can't be violated from
-- outside.
module Routefinding.Heap
  ( IndexedHeap
  , empty
  , size
  , member
  , insert
  , popMin
  , decreaseKey
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq

import Graph (NodeID)

-- | One heap slot: a node and its current priority. (Go: @ipqEntry@.)
data Entry = Entry
  { entryNode :: NodeID
  , entryPriority :: Double
  }
  deriving stock (Show, Eq)

-- | The heap. Constructors intentionally unexported. (Go: @indexedHeap@.)
data IndexedHeap = IndexedHeap
  { entries :: Seq Entry
    -- ^ Binary-heap array: children of @i@ are @2i+1@ and @2i+2@.
  , positions :: Map NodeID Int
    -- ^ node id → its index in 'entries'; the O(1) membership index.
  }

-- | An empty heap. (Go: @newIndexedHeap@.)
empty :: IndexedHeap
empty = IndexedHeap Seq.empty Map.empty

-- | Number of entries. (Go: @Len@.)
size :: IndexedHeap -> Int
size = Seq.length . entries

-- | Is this node currently in the heap? (Go: @Contains@.)
--
-- TODO: @Map.member id . positions@.
member :: NodeID -> IndexedHeap -> Bool
member = undefined

-- | Add a new node at the given priority, then sift it up. Caller guarantees
-- the node is not already present. (Go: @Push@.)
--
-- TODO: append an 'Entry', record its position, then 'siftUp' from the last
--       index. Write 'siftUp'/'siftDown'/'swap' as private @where@ helpers that
--       keep 'entries' and 'positions' in sync (that sync is the whole point
--       of an indexed heap).
insert :: NodeID -> Double -> IndexedHeap -> IndexedHeap
insert = undefined

-- | Remove and return the lowest-priority @(node, priority)@ plus the rest of
-- the heap; 'Nothing' when empty. (Go: @Pop@ — but 'Maybe' makes the empty
-- case explicit, and returning the new heap replaces in-place mutation.)
--
-- TODO: read root (index 0), swap it with the last entry, drop the last,
--       delete from 'positions', then 'siftDown' from 0.
popMin :: IndexedHeap -> Maybe ((NodeID, Double), IndexedHeap)
popMin = undefined

-- | Lower an existing node's priority and re-heapify. No-op if the node is
-- absent or the new priority is not actually smaller. (Go: @DecreasePriority@.)
--
-- TODO: look up its position; if @newPriority < current@, update the entry and
--       'siftUp' from that position.
decreaseKey :: NodeID -> Double -> IndexedHeap -> IndexedHeap
decreaseKey = undefined
