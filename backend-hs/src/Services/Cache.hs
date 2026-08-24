-- | In-memory Overpass response cache, keyed by bounding box.
-- Port of Go @services/network_cache.go@.
--
-- Go guards a @map@ with a @sync.RWMutex@; here we use @STM@/'TVar'. Think of
-- it like a transactional @ConcurrentDictionary@ — 'atomically' runs a
-- transaction all-or-nothing, no manual lock/unlock. 'BBox' derives 'Ord'
-- (all-'Double' fields), so it works directly as the 'Data.Map.Strict.Map' key.
--
-- Deliberately unbounded (no TTL/eviction), matching the Go version.
module Services.Cache
  ( Cache
  , newCache
  , lookupCache
  , insertCache
  ) where

import Control.Concurrent.STM (TVar)
import Data.Map.Strict (Map)

import Geo.Types (BBox)
import Overpass.Types (Response)

-- | The cache handle. Constructor hidden so all access goes through the
-- transactional helpers below. (Go: @NetworkCache@.)
newtype Cache = Cache (TVar (Map BBox Response))

-- | Create an empty cache. (Go: @NewNetworkCache@.)
--
-- TODO: @Cache <$> newTVarIO Map.empty@.
newCache :: IO Cache
newCache = undefined

-- | Look up a cached response for @bbox@ ('Nothing' on a miss).
-- (Go: @NetworkCache.Lookup@.)
--
-- TODO: @atomically (Map.lookup bbox <$> readTVar tv)@.
lookupCache :: Cache -> BBox -> IO (Maybe Response)
lookupCache = undefined

-- | Store @response@ under @bbox@, overwriting any existing entry.
-- (Go: @NetworkCache.Store@.)
--
-- TODO: @atomically (modifyTVar' tv (Map.insert bbox response))@.
insertCache :: Cache -> BBox -> Response -> IO ()
insertCache = undefined
