{-# LANGUAGE OverloadedRecordDot #-}

-- | Tests for "Geo.Types" — 'contains', 'approxAreaKm2', 'bboxFromCoords'.
--
-- Mix of concrete examples (easy to eyeball) and QuickCheck properties (catch
-- edge cases you didn't think of). Run just this module with:
--
--   cabal test --test-options='--match "Geo.Types"'
module Geo.TypesSpec (spec) where

import Test.Hspec
import Test.QuickCheck

import Geo.Types

spec :: Spec
spec = do
  describe "Geo.Types.contains" $ do
    let box = BBox { minLat = -1, minLon = -1, maxLat = 1, maxLon = 1 }
    it "accepts a point inside the box" $
      contains box (Coord 0 0) `shouldBe` True
    it "accepts a point exactly on the boundary" $
      contains box (Coord 1 1) `shouldBe` True
    it "rejects a point outside the box" $
      contains box (Coord 2 0) `shouldBe` False

  describe "Geo.Types.approxAreaKm2" $ do
    it "is ~0 for a degenerate (zero-span) box" $
      approxAreaKm2 (BBox 10 10 10 10) `shouldSatisfy` (< 0.001)
    it "is symmetric-ish and positive for a real box" $
      approxAreaKm2 (BBox 0 0 1 1) `shouldSatisfy` (> 0)

  describe "Geo.Types.bboxFromCoords" $ do
    -- This is a correctness INVARIANT: a box padded around two points must
    -- still contain both of them. If padding is applied with the wrong sign,
    -- the lower corner moves the wrong way and this fails — a good red test.
    it "always contains both input coordinates" $ property $
      \(la, lo, lb, lob) ->
        let a = Coord la lo
            b = Coord lb lob
            box = bboxFromCoords a b 0.01
        in contains box a && contains box b

    it "pads outward: a 1x1 box grows on every side" $ do
      let box = bboxFromCoords (Coord 0 0) (Coord 1 1) 0.5
      box.minLat `shouldSatisfy` (< 0)
      box.minLon `shouldSatisfy` (< 0)
      box.maxLat `shouldSatisfy` (> 1)
      box.maxLon `shouldSatisfy` (> 1)
