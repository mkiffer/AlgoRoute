-- | Ports @backend/services/tests/network_cache_test.go@.
module Services.CacheSpec (spec) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forM_, replicateM_)
import Data.Text (Text)
import Geo.Types (BBox (..))
import Overpass.Types (Response (..), emptyResponse)
import Services.Cache (cacheSize, insertCache, lookupCache, newCache)
import Test.Hspec

boxA, boxB :: BBox
boxA = BBox {minLat = -37.9, minLon = 145.09, maxLat = -37.88, maxLon = 145.11}
boxB = BBox {minLat = -37.7, minLon = 144.90, maxLat = -37.68, maxLon = 144.92}

-- | A response distinguishable by its @generator@ string, which is otherwise
-- unused by the pipeline.
responseNamed :: Text -> Response
responseNamed marker = emptyResponse {generator = Just marker}

spec :: Spec
spec = describe "Services.Cache" $ do
  it "misses on an empty cache" $ do
    cache <- newCache
    result <- lookupCache cache boxA
    result `shouldBe` Nothing

  it "returns what was stored for the same box" $ do
    -- The scenario this exists for: route with Dijkstra, then A* on the same
    -- two addresses. Identical addresses give an identical box, so the second
    -- request skips a multi-second, multi-megabyte Overpass fetch.
    cache <- newCache
    insertCache cache boxA (responseNamed "first")
    result <- lookupCache cache boxA
    fmap generator result `shouldBe` Just (Just "first")

  it "keeps different boxes separate" $ do
    cache <- newCache
    insertCache cache boxA (responseNamed "first")
    insertCache cache boxB (responseNamed "second")
    a <- lookupCache cache boxA
    b <- lookupCache cache boxB
    fmap generator a `shouldBe` Just (Just "first")
    fmap generator b `shouldBe` Just (Just "second")
    cacheSize cache >>= (`shouldBe` 2)

  it "overwrites an existing entry for the same box" $ do
    cache <- newCache
    insertCache cache boxA (responseNamed "stale")
    insertCache cache boxA (responseNamed "fresh")
    result <- lookupCache cache boxA
    fmap generator result `shouldBe` Just (Just "fresh")
    cacheSize cache >>= (`shouldBe` 1)

  it "treats a box differing only in the last decimal as a different key" $ do
    -- BBox is keyed structurally on four Doubles, so this is exact equality on
    -- floating point. Worth pinning down: a geocode that shifts by a billionth
    -- of a degree misses the cache rather than silently returning data for a
    -- slightly different area.
    cache <- newCache
    let nudged = boxA {maxLat = maxLat boxA + 1e-9}
    insertCache cache boxA (responseNamed "first")
    result <- lookupCache cache nudged
    result `shouldBe` Nothing

  it "does not lose updates when written from many threads at once" $ do
    -- One TVar under STM replaces Go's sync.RWMutex. There is no lock to forget
    -- to release, and a transaction whose inputs changed underneath it simply
    -- retries — so two concurrent inserts cannot interleave into a lost update.
    -- Under a naive read-then-write this test loses entries.
    cache <- newCache
    let boxes = [boxA {minLon = 145 + fromIntegral n / 1000} | n <- [1 .. 50 :: Int]]
    done <- newEmptyMVar
    forM_ boxes $ \box -> forkIO $ do
      insertCache cache box (responseNamed "concurrent")
      putMVar done ()
    replicateM_ (length boxes) (takeMVar done)
    cacheSize cache >>= (`shouldBe` 50)
