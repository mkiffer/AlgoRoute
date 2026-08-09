{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports the algorithm-selection tests from
-- @backend/services/tests/routing_test.go@.
module Routefinding.RouterSpec (spec) where

import Data.Either (isLeft)
import Data.Text qualified as T
import Graph (NodeID (..))
import Routefinding.Router
  ( Algorithm (..)
  , algorithmName
  , allAlgorithms
  , parseAlgorithm
  , runRouter
  )
import Routefinding.Types (RouteResult (..))
import Test.Hspec
import TestSupport (EdgeSpec (..), mustNetwork, mustRight, shouldBeApprox)

spec :: Spec
spec = do
  describe "Routefinding.Router.parseAlgorithm" $ do
    it "accepts every documented wire name" $ do
      parseAlgorithm "dijkstra" `shouldBe` Right Dijkstra
      parseAlgorithm "astar" `shouldBe` Right AStar
      parseAlgorithm "greedy" `shouldBe` Right GreedyBestFirst
      parseAlgorithm "bidijkstra" `shouldBe` Right BidirectionalDijkstra

    it "defaults an empty name to Dijkstra" $
      -- Matches Server.newRoutingServiceForAlgorithm, so a client that omits
      -- the field entirely keeps working.
      parseAlgorithm "" `shouldBe` Right Dijkstra

    it "rejects an unknown name" $
      parseAlgorithm "quicksort" `shouldSatisfy` isLeft

    it "lists the valid names in its error message" $ do
      case parseAlgorithm "quicksort" of
        Right _ -> expectationFailure "expected a parse failure"
        Left message ->
          mapM_
            (\name -> T.unpack message `shouldContain` T.unpack name)
            (map algorithmName allAlgorithms)

    it "round-trips every algorithm through its name" $
      -- Generated from allAlgorithms rather than a hand-written list, so
      -- adding a constructor extends this test automatically.
      mapM_
        (\algorithm -> parseAlgorithm (algorithmName algorithm) `shouldBe` Right algorithm)
        allAlgorithms

  describe "Routefinding.Router.algorithmName" $
    it "matches the identifiers in frontend/src/types.ts" $
      map algorithmName allAlgorithms
        `shouldBe` ["dijkstra", "astar", "greedy", "bidijkstra"]

  describe "Routefinding.Router.runRouter" $ do
    -- A network with one obvious answer, so every algorithm — optimal or not —
    -- must return it. This is the check that the dispatch table is wired up
    -- correctly and no two entries are swapped.
    let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1, EdgeSpec 2 3 1]

    it "dispatches to a working implementation for every algorithm" $
      mapM_
        ( \algorithm -> do
            result <- mustRight (runRouter algorithm net (NodeID 1) (NodeID 3))
            result.path `shouldBe` map NodeID [1, 2, 3]
            result.distance `shouldBeApprox` 2
        )
        allAlgorithms
