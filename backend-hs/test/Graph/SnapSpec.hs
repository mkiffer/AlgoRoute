-- | Ports @backend/graph/tests/snap_test.go@.
module Graph.SnapSpec (spec) where

import Geo.Types (Coord (..))
import Graph (NodeID (..), empty)
import Graph.Snap (SnapError (..), nearestNode)
import Test.Hspec
import TestSupport (mustNetworkWithCoords)

spec :: Spec
spec = describe "Graph.Snap.nearestNode" $ do
  it "returns the node closest to the target" $ do
    -- The reason snapping exists: a geocoded address almost never lands exactly
    -- on a graph node, so it must be projected onto the nearest one first.
    let net =
          mustNetworkWithCoords
            [ (1, -37.81, 144.96)
            , (2, -37.82, 144.97)
            , (3, -37.83, 144.98)
            ]
            []
        target = Coord {lat = -37.821, lon = 144.971}
    nearestNode net target `shouldBe` Right (NodeID 2)

  it "returns the only node in a single-node network" $ do
    let net = mustNetworkWithCoords [(42, -37.81, 144.96)] []
        target = Coord {lat = -37.90, lon = 145.10}
    nearestNode net target `shouldBe` Right (NodeID 42)

  it "reports an error for an empty network" $
    -- Returning a zero NodeID instead would send the search off to a node that
    -- does not exist, and the failure would surface much later.
    nearestNode empty (Coord {lat = 0, lon = 0}) `shouldBe` Left EmptyNetwork

  it "breaks ties deterministically by lowest node ID" $ do
    -- Two nodes at identical coordinates. Go iterates its node map in
    -- randomised order and keeps the first strict improvement, so it can return
    -- either one; folding over an ordered Map always returns the same one.
    let net = mustNetworkWithCoords [(7, -37.8, 144.9), (9, -37.8, 144.9)] []
        target = Coord {lat = -37.8, lon = 144.9}
    nearestNode net target `shouldBe` Right (NodeID 7)
