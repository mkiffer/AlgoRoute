-- | Tests for "Routefinding.Heap" — the indexed min-heap.
--
-- The heap is the easiest module to get subtly wrong, so lean on a property:
-- draining it must yield priorities in non-decreasing order, no matter what was
-- inserted. That single property catches most sift-up/sift-down bugs.
module Routefinding.HeapSpec (spec) where

import Data.List (sort)
import Data.Maybe (isNothing)
import Test.Hspec
import Test.QuickCheck

import qualified Routefinding.Heap as Heap

-- | Insert every (node, priority) pair, then pop everything out in order.
drainPriorities :: [(Int, Double)] -> [Double]
drainPriorities pairs = go (foldr (\(n, p) h -> Heap.insert (fromIntegral n) p h) Heap.empty pairs)
  where
    go h = case Heap.popMin h of
      Nothing -> []
      Just ((_, p), h') -> p : go h'

spec :: Spec
spec = do
  describe "Routefinding.Heap" $ do
    it "empty heap has size 0 and pops Nothing" $ do
      Heap.size Heap.empty `shouldBe` 0
      -- IndexedHeap is opaque (no Eq/Show), so inspect only the popped value.
      isNothing (fmap fst (Heap.popMin Heap.empty)) `shouldBe` True

    it "pops priorities in non-decreasing order (uses unique node ids)" $ property $
      \(xs :: [Double]) ->
        let pairs = zip [1 :: Int ..] xs      -- unique ids, arbitrary priorities
        in drainPriorities pairs === sort xs

    it "decreaseKey re-orders an existing node to the front" $ do
      let h0 = Heap.insert 1 10.0 (Heap.insert 2 20.0 Heap.empty)
          h1 = Heap.decreaseKey 2 5.0 h0
      fmap (fst . fst) (Heap.popMin h1) `shouldBe` Just 2

    it "member reflects presence" $ do
      let h = Heap.insert 42 1.0 Heap.empty
      Heap.member 42 h `shouldBe` True
      Heap.member 99 h `shouldBe` False
