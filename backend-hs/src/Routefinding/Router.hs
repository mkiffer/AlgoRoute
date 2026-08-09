-- |
-- Module      : Routefinding.Router
-- Description : Choosing an algorithm by name.
--
-- Ports @backend/routefinding/router.go@ and the algorithm-name constants and
-- @switch@ from @backend/services/{options,routing}.go@.
--
-- This is the clearest place in the whole port where the idiomatic Go answer
-- and the idiomatic Haskell answer genuinely differ — see 'Algorithm'.
module Routefinding.Router
  ( Algorithm (..)
  , runRouter
  , parseAlgorithm
  , algorithmName
  , allAlgorithms
  ) where

import Data.Text (Text)
import Data.Text qualified as T
import Graph (Network, NodeID)
import Routefinding.AStar (aStar)
import Routefinding.Bidirectional (bidirectionalDijkstra)
import Routefinding.Dijkstra (dijkstra)
import Routefinding.GreedyBestFirst (greedyBestFirst)
import Routefinding.Types (RouteError, RouteResult)

-- | Which shortest-path algorithm to run.
--
-- __Go uses an interface here; this uses a closed sum type. Why the
-- difference?__
--
-- Go's @router.go@ declares @type Router interface { Route(...) }@ with four
-- one-method implementations, and its comment explains the choice: a @switch@
-- on an algorithm name inside the service would couple the service to every
-- algorithm, so adding a fifth would mean editing the service. The interface
-- decouples them. In an open-world language with no exhaustiveness checking,
-- that reasoning is right.
--
-- Haskell inverts it. A closed sum type gives the compiler the complete list of
-- algorithms, so adding a constructor turns every @case@ that does not handle
-- it into a warning — and with @-Wall@, a build failure. The coupling Go was
-- avoiding becomes the mechanism that makes extension /safe/: you cannot forget
-- to wire a new algorithm into 'runRouter', 'parseAlgorithm' or 'algorithmName',
-- because the compiler stops you. Try it: add a constructor and build.
--
-- A type class (Haskell's closest analogue to a Go interface) would recover
-- Go's open world and lose this. That would be the right call for a plugin
-- system where third parties supply algorithms. For four algorithms in one
-- codebase, all known at compile time, the sum type is strictly better — and
-- as a bonus it derives 'Eq', 'Show', 'Enum' and 'Bounded' for free, which is
-- where 'allAlgorithms' comes from.
data Algorithm
  = Dijkstra
  | AStar
  | GreedyBestFirst
  | BidirectionalDijkstra
  deriving stock (Eq, Show, Enum, Bounded)

-- | Every algorithm, derived from 'Bounded' and 'Enum' rather than written out.
--
-- This list can never drift out of sync with the type, which is why the error
-- message from 'parseAlgorithm' is built from it.
allAlgorithms :: [Algorithm]
allAlgorithms = [minBound .. maxBound]

-- | The wire name, as used in the JSON API and by the frontend's selector.
--
-- These strings are a contract with @frontend/types.ts@ and must match the Go
-- constants in @services/options.go@ exactly.
algorithmName :: Algorithm -> Text
algorithmName = \case
  Dijkstra -> "dijkstra"
  AStar -> "astar"
  GreedyBestFirst -> "greedy"
  BidirectionalDijkstra -> "bidijkstra"

-- | Parse a wire name.
--
-- An empty string selects 'Dijkstra', matching
-- @Server.newRoutingServiceForAlgorithm@, which lets the frontend omit the
-- field entirely. Anything else unrecognised is an error listing the valid
-- names — generated from 'allAlgorithms', so it stays correct as the type grows.
parseAlgorithm :: Text -> Either Text Algorithm
parseAlgorithm "" = Right Dijkstra
parseAlgorithm name =
  case filter ((== name) . algorithmName) allAlgorithms of
    (algorithm : _) -> Right algorithm
    [] ->
      Left $
        "unknown algorithm "
          <> T.pack (show name)
          <> ": valid options are "
          <> T.intercalate ", " (map algorithmName allAlgorithms)

-- | Dispatch to the chosen algorithm.
--
-- Go's equivalent is a @switch@ that constructs a @Router@ value, plus a later
-- call through that interface. Here the dispatch happens in one place, and
-- because 'Algorithm' is closed, the compiler verifies it is complete.
runRouter :: Algorithm -> Network -> NodeID -> NodeID -> Either RouteError RouteResult
runRouter = \case
  Dijkstra -> dijkstra
  AStar -> aStar
  GreedyBestFirst -> greedyBestFirst
  BidirectionalDijkstra -> bidirectionalDijkstra
