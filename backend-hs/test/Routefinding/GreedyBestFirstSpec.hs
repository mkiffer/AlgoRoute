{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/routefinding/greedy_best_first_test.go@.
module Routefinding.GreedyBestFirstSpec (spec) where

import Graph (Edge (..), Network, NodeID (..))
import Graph qualified
import Routefinding.Dijkstra (dijkstra)
import Routefinding.GreedyBestFirst (greedyBestFirst)
import Routefinding.Types (RouteError (..), RouteResult (..))
import Test.Hspec
import TestSupport
  ( EdgeSpec (..)
  , mustNetwork
  , mustNetworkWithCoords
  , mustRight
  , shouldBeApprox
  )

spec :: Spec
spec = describe "Routefinding.GreedyBestFirst.greedyBestFirst" $ do
  it "finds a path" $ do
    let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1, EdgeSpec 2 3 1]
    result <- mustRight (greedyBestFirst net (NodeID 1) (NodeID 3))
    result.path `shouldBe` map NodeID [1, 2, 3]

  it "reports an error when the goal is unreachable" $ do
    let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1]
    greedyBestFirst net (NodeID 1) (NodeID 3)
      `shouldBe` Left (NoPathFound (NodeID 1) (NodeID 3))

  it "returns a trivial path when start equals goal" $ do
    let net = mustNetwork [1] []
    result <- mustRight (greedyBestFirst net (NodeID 1) (NodeID 1))
    result.path `shouldBe` [NodeID 1]
    result.distance `shouldBeApprox` 0

  it "records the start and goal among the visited nodes" $ do
    let net = mustNetwork [1, 2, 3] [EdgeSpec 1 2 1, EdgeSpec 2 3 1]
    result <- mustRight (greedyBestFirst net (NodeID 1) (NodeID 3))
    take 1 result.visitedNodes `shouldBe` [NodeID 1]
    result.visitedNodes `shouldContain` [NodeID 3]

  describe "the price of dropping the g term" $ do
    -- The trap network. Node 1 has two ways out:
    --
    --   * node 2, which sits geographically *towards* the goal but is reached
    --     by an absurdly long road (50 km of edge weight), and continues to
    --     the goal by another long one;
    --   * node 3, which sits off to the side but is reached cheaply, and
    --     continues cheaply to the goal.
    --
    -- Dijkstra weighs the roads and takes 1→3→4. Greedy sees only that node 2
    -- looks closer to the goal, commits to it, and pays for it.
    it "returns a longer route than Dijkstra when the heuristic misleads it" $ do
      viaGreedy <- mustRight (greedyBestFirst trapNetwork (NodeID 1) (NodeID 4))
      viaDijkstra <- mustRight (dijkstra trapNetwork (NodeID 1) (NodeID 4))
      viaGreedy.distance `shouldSatisfy` (> viaDijkstra.distance)

    it "reports the true edge-weight cost of the path it found" $ do
      -- Not the heuristic value that guided the search. This is what lets the
      -- frontend put greedy's number next to Dijkstra's optimum and show the
      -- gap honestly.
      viaGreedy <- mustRight (greedyBestFirst trapNetwork (NodeID 1) (NodeID 4))
      viaGreedy.distance `shouldBeApprox` sumOfWeights trapNetwork viaGreedy.path

    it "still returns a genuinely connected path" $ do
      -- Suboptimal is allowed; disconnected is not.
      viaGreedy <- mustRight (greedyBestFirst trapNetwork (NodeID 1) (NodeID 4))
      head viaGreedy.path `shouldBe` NodeID 1
      last viaGreedy.path `shouldBe` NodeID 4

-- | Total edge weight along a path, looked up in the network.
--
-- Deliberately recomputed from the graph rather than trusted from the result:
-- the point of the assertion is that the reported distance and the path agree.
sumOfWeights :: Network -> [NodeID] -> Double
sumOfWeights net nodes =
  sum
    [ weightBetween a b
    | (a, b) <- zip nodes (drop 1 nodes)
    ]
  where
    weightBetween a b =
      case [e | e <- Graph.neighbours a net, e.to == b] of
        (edge : _) -> edge.weight
        [] -> error ("no edge from " <> show a <> " to " <> show b)

-- | A network where straight-line distance points the wrong way.
--
-- Node 2 is placed near the goal but reached only by a very long road; node 3
-- is placed to the side but reached cheaply.
trapNetwork :: Network
trapNetwork = mustNetworkWithCoords positions edges
  where
    positions =
      [ (1, -37.80, 144.90) -- start
      , (2, -37.80, 144.99) -- looks close to the goal
      , (3, -37.85, 144.91) -- looks far from the goal
      , (4, -37.80, 145.00) -- goal
      ]

    -- Weights chosen by hand, not by geometry, so the heuristic and the real
    -- costs actively disagree.
    edges =
      [ EdgeSpec 1 2 50000 -- expensive road toward the goal
      , EdgeSpec 2 4 50000
      , EdgeSpec 1 3 100 -- cheap road away from the goal
      , EdgeSpec 3 4 100
      ]
