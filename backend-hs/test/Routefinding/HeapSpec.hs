{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/routefinding/indexed_heap_test.go@.
module Routefinding.HeapSpec (spec) where

import Data.List (foldl', sort)
import Data.Maybe (fromJust)
import Graph (NodeID (..))
import Routefinding.Heap
  ( Entry (..)
  , IndexedHeap
  , decreasePriority
  , empty
  , isEmpty
  , member
  , peekMin
  , popMin
  , push
  , size
  )
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (Property, (===))

spec :: Spec
spec = describe "Routefinding.Heap" $ do
  describe "popMin" $ do
    it "returns the entry with the lowest priority" $ do
      let heap = fromList [(1, 5), (2, 1), (3, 3)]
      fmap (\(entry, _) -> entry.node) (popMin heap) `shouldBe` Just (NodeID 2)

    it "drains in ascending priority order" $ do
      let heap = fromList [(1, 5), (2, 1), (3, 3), (4, 9), (5, 0)]
      drain heap `shouldBe` [NodeID 5, NodeID 2, NodeID 3, NodeID 1, NodeID 4]

    it "returns Nothing for an empty heap" $
      -- Go's Pop indexes entries[0] unconditionally and panics here; the Maybe
      -- makes the empty case impossible to forget.
      (popMin empty :: Maybe (Entry, IndexedHeap)) `shouldBe` Nothing

    it "removes the popped node from membership" $ do
      let heap = fromList [(1, 5), (2, 1)]
          (_, rest) = fromJust (popMin heap)
      member (NodeID 2) rest `shouldBe` False
      member (NodeID 1) rest `shouldBe` True

  describe "decreasePriority" $ do
    it "promotes a node to the front" $ do
      let heap = decreasePriority (NodeID 3) 0 (fromList [(1, 5), (2, 1), (3, 9)])
      fmap (\(entry, _) -> entry.node) (popMin heap) `shouldBe` Just (NodeID 3)

    it "ignores a larger priority" $ do
      -- Raising a priority would need siftDown, not siftUp, so accepting one
      -- would silently corrupt the heap. Go guards the same way.
      let heap = decreasePriority (NodeID 2) 100 (fromList [(1, 5), (2, 1)])
      fmap (\(entry, _) -> entry.priority) (popMin heap) `shouldBe` Just 1

    it "ignores a node that is not present" $ do
      let heap = fromList [(1, 5)]
      size (decreasePriority (NodeID 99) 0 heap) `shouldBe` 1

  describe "member and size" $ do
    it "tracks which nodes are present" $ do
      let heap = fromList [(1, 5), (2, 1)]
      member (NodeID 1) heap `shouldBe` True
      member (NodeID 99) heap `shouldBe` False

    it "reflects pushes and pops" $ do
      let heap = fromList [(1, 5), (2, 1), (3, 3)]
      size heap `shouldBe` 3
      isEmpty heap `shouldBe` False
      size (snd (fromJust (popMin heap))) `shouldBe` 2
      isEmpty empty `shouldBe` True

  describe "peekMin" $ do
    it "returns the minimum without removing it" $ do
      let heap = fromList [(1, 5), (2, 1)]
      fmap (.node) (peekMin heap) `shouldBe` Just (NodeID 2)
      size heap `shouldBe` 2

    it "returns Nothing for an empty heap" $
      fmap (.node) (peekMin empty) `shouldBe` Nothing

  -- The heap's whole contract in one property. Examples can only check the
  -- orderings someone thought to write down; this checks every ordering
  -- QuickCheck can produce, including the deep sift-down cases that only show
  -- up with a dozen or more entries.
  prop "drains in sorted order whatever the insertion order" propDrainsSorted

-- | Build a heap from (node ID, priority) pairs.
fromList :: [(Integer, Double)] -> IndexedHeap
fromList = foldl' insert empty
  where
    insert heap (nodeID, priority) = push (NodeID (fromIntegral nodeID)) priority heap

-- | Pop everything, in order.
drain :: IndexedHeap -> [NodeID]
drain heap = case popMin heap of
  Nothing -> []
  Just (entry, rest) -> entry.node : drain rest

-- | Popping a heap yields its priorities in non-decreasing order.
--
-- Duplicate node IDs are removed first, because 'push' documents that a node
-- must not already be present — feeding it duplicates would test a case the
-- data structure does not claim to support.
propDrainsSorted :: [(Integer, Double)] -> Property
propDrainsSorted pairs =
  drainPriorities (fromList unique) === sort (map snd unique)
  where
    unique = dedupeOn fst pairs

    drainPriorities heap = case popMin heap of
      Nothing -> []
      Just (entry, rest) -> entry.priority : drainPriorities rest

    dedupeOn key = go []
      where
        go _ [] = []
        go seen (x : xs)
          | key x `elem` seen = go seen xs
          | otherwise = x : go (key x : seen) xs
