-- |
-- Module      : Routefinding.Types
-- Description : What a routing algorithm returns, and how it can fail.
--
-- Ports the @RouteResult@ struct from @backend/routefinding/router.go@ and
-- turns Go's formatted @error@ values into a closed sum type.
module Routefinding.Types
  ( RouteResult (..)
  , RouteError (..)
  ) where

import Graph (NodeID)

-- | The output of every routing algorithm in this package.
--
-- Bundling three values into a record rather than returning a tuple is the
-- same reasoning Go's comment gives: a new field can be added without breaking
-- every call site. @visitedNodes@ was exactly such an addition — it exists to
-- drive the frontend's traversal animation, and adding it cost one line here
-- and nothing at the call sites.
data RouteResult = RouteResult
  { path :: ![NodeID]
  -- ^ Ordered nodes from start to goal, inclusive of both.
  , distance :: !Double
  -- ^ Total edge weight along @path@. Metres, for networks built from OSM
  -- data by "Mapping".
  , visitedNodes :: ![NodeID]
  -- ^ Nodes in the order they were /settled/ — popped from the priority
  -- queue with their final cost confirmed. Starts with the start node and
  -- ends with the goal. The frontend replays this list to show the search
  -- frontier expanding before revealing the chosen path, which is what makes
  -- the difference between the four algorithms visible.
  }
  deriving stock (Eq, Show)

-- | Why a search produced no route.
--
-- Go builds a string with @fmt.Errorf@ at four different call sites, each
-- prefixed with its algorithm's name. A sum type carries the same facts as
-- data: the layer that renders a user-facing message decides on the wording
-- once (see "App.Error"), and the compiler checks that every case is handled.
data RouteError
  = -- | The goal is unreachable from the start. Carries both endpoints so the
    -- message can name them.
    NoPathFound !NodeID !NodeID
  | -- | An endpoint is not in the network at all. Go has no equivalent: its
    -- @net.Nodes[goal]@ silently yields a zero-valued node, so a bad goal ID
    -- becomes a route toward coordinate (0, 0) instead of an error.
    NodeNotInNetwork !NodeID
  deriving stock (Eq, Show)
