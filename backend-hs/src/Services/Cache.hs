-- |
-- Module      : Services.Cache
-- Description : Thread-safe cache of Overpass responses, keyed by bounding box.
--
-- Ports @backend/services/network_cache.go@, replacing Go's @sync.RWMutex@
-- with a single 'TVar' under STM.
module Services.Cache
  ( NetworkCache
  , newCache
  , lookupCache
  , insertCache
  , cacheSize
  ) where

import Control.Concurrent.STM
  ( TVar
  , atomically
  , modifyTVar'
  , newTVarIO
  , readTVarIO
  )
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Geo.Types (BBox)
import Overpass.Types (Response)

-- | Overpass responses, keyed by the bounding box that produced them.
--
-- __Why cache at all.__ The common case is a user comparing algorithms: route
-- with Dijkstra, then hit A* on the same two addresses. Identical addresses
-- give identical geocodes, which give an identical bounding box — so the second
-- request can skip an Overpass call that took several seconds and returned
-- several megabytes. Without this, the comparison the whole app is built around
-- is painfully slow.
--
-- __Why 'BBox' works as a key.__ It is four 'Double's with a derived 'Ord', so
-- boxes compare structurally. This is the same property Go relies on when it
-- writes @map[geo.BBox]@ — legal there precisely because the struct contains
-- only comparable fields.
--
-- __What this deliberately does not do.__ No eviction, no TTL, no size bound —
-- an unbounded map, exactly as in Go. A long-running server routing many
-- distinct areas will grow its memory without limit. That is a known and
-- accepted trade-off for a demo backend; adding an LRU bound would be the first
-- change if it ever ran in earnest.
newtype NetworkCache = NetworkCache (TVar (Map BBox Response))

-- | An empty cache.
newCache :: IO NetworkCache
newCache = NetworkCache <$> newTVarIO Map.empty

-- | Look up a cached response.
--
-- __STM versus a mutex.__ Go takes @mu.RLock()@, reads, and @defer@s the
-- unlock; forget the defer and the server deadlocks. Here there is no lock to
-- take or release: 'readTVarIO' reads the current value of the 'TVar' in one
-- atomic step. Nothing can interleave, and there is no unlock to forget —
-- the type system will not let a 'TVar' be read outside a transaction.
--
-- This is a read-only operation, so 'readTVarIO' is used rather than
-- @atomically . readTVar@: it skips the transaction log entirely, which is
-- cheaper and cannot conflict with anything.
lookupCache :: NetworkCache -> BBox -> IO (Maybe Response)
lookupCache (NetworkCache var) bbox = Map.lookup bbox <$> readTVarIO var

-- | Store a response, replacing any existing entry for the same box.
--
-- 'modifyTVar'' is read-modify-write as a single atomic transaction. Two
-- concurrent requests for the same box cannot interleave into a lost update —
-- STM retries a transaction whose inputs changed underneath it. The @'@ makes
-- the new map strict, so the cache holds an evaluated map rather than a chain
-- of pending inserts.
--
-- __A note for the Lambda deployment.__ AWS reuses a warm Lambda instance
-- across invocations, and this 'TVar' lives as long as the process. So the
-- cache survives between requests on a warm instance exactly as it does on a
-- long-running server, and is simply empty on a cold start. No Redis required —
-- the same behaviour the Go backend has today.
insertCache :: NetworkCache -> BBox -> Response -> IO ()
insertCache (NetworkCache var) bbox response =
  atomically (modifyTVar' var (Map.insert bbox response))

-- | Number of cached responses. Diagnostics and tests only.
cacheSize :: NetworkCache -> IO Int
cacheSize (NetworkCache var) = Map.size <$> readTVarIO var
