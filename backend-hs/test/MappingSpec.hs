{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/mapping/tests/mapping_test.go@ and @oneway_test.go@.
module MappingSpec (spec) where

import Data.Aeson (Value, encode, object, (.=))
import Data.Aeson qualified as Aeson
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Graph (Edge (..), Network (..), NodeID (..))
import Graph qualified
import Mapping (BuildOptions (..), BuildStats (..), buildNetwork, defaultBuildOptions)
import Overpass.Types (Response)
import Test.Hspec
import TestSupport (mustLoadFixture, mustRight)

spec :: Spec
spec = do
  describe "Mapping.buildNetwork on the shared fixture" $ do
    it "builds a network with nodes and edges" $ do
      response <- mustLoadFixture
      (net, stats) <- mustRight (buildNetwork defaultBuildOptions response)
      stats.wayCount `shouldBe` 55
      Graph.nodeCount net `shouldSatisfy` (> 0)
      Graph.edgeCount net `shouldSatisfy` (> 0)

    it "reports statistics consistent with the network it built" $ do
      response <- mustLoadFixture
      (net, stats) <- mustRight (buildNetwork defaultBuildOptions response)
      stats.nodeCount `shouldBe` Graph.nodeCount net
      stats.edgeCount `shouldBe` Graph.edgeCount net

    it "weights edges in metres" $ do
      -- A units sanity check. Consecutive OSM nodes on a residential street are
      -- metres apart — if the Haversine call were returning degrees or
      -- kilometres, every weight would fall outside this range.
      response <- mustLoadFixture
      (net, _) <- mustRight (buildNetwork defaultBuildOptions response)
      map (.weight) (allEdges net) `shouldSatisfy` all (\w -> w > 0 && w < 5000)

    it "adds fewer edges when untagged ways are not assumed bidirectional" $ do
      -- The fixture's ways are mostly untagged, so this option is what decides
      -- whether they get a backward edge.
      response <- mustLoadFixture
      (bothWays, _) <- mustRight (buildNetwork defaultBuildOptions response)
      (forwardOnly, _) <-
        mustRight (buildNetwork BuildOptions {assumeBidirectional = False} response)
      Graph.edgeCount forwardOnly `shouldSatisfy` (< Graph.edgeCount bothWays)

  describe "Mapping.buildNetwork one-way handling" $ do
    it "oneway=yes gives only the forward edge" $ do
      net <- twoNodeWay (Just "yes") defaultBuildOptions
      directions net `shouldBe` (True, False)

    it "oneway=-1 gives only the backward edge" $ do
      -- A way digitised against the direction of travel. The forward edge must
      -- be suppressed, not merely supplemented.
      net <- twoNodeWay (Just "-1") defaultBuildOptions
      directions net `shouldBe` (False, True)

    it "oneway=reverse behaves like oneway=-1" $ do
      net <- twoNodeWay (Just "reverse") defaultBuildOptions
      directions net `shouldBe` (False, True)

    it "oneway=no is bidirectional even when the option says otherwise" $ do
      -- An explicit tag always wins over assumeBidirectional.
      net <- twoNodeWay (Just "no") BuildOptions {assumeBidirectional = False}
      directions net `shouldBe` (True, True)

    it "an untagged way is bidirectional when the option allows it" $ do
      net <- twoNodeWay Nothing defaultBuildOptions
      directions net `shouldBe` (True, True)

    it "an untagged way is forward-only when the option forbids it" $ do
      net <- twoNodeWay Nothing BuildOptions {assumeBidirectional = False}
      directions net `shouldBe` (True, False)

    it "accepts every documented spelling of a forward-only tag" $
      mapM_ (expectDirections (True, False)) ["yes", "1", "true"]

    it "accepts every documented spelling of an explicitly two-way tag" $
      mapM_ (expectDirections (True, True)) ["no", "0", "false"]

    it "accepts every documented spelling of a reverse-only tag" $
      mapM_ (expectDirections (False, True)) ["-1", "reverse"]

    it "treats an unrecognised tag value as forward-only" $ do
      -- A Go quirk, preserved deliberately. The backward-edge condition is
      --
      --   not forwardOnly && (reverseOnly || explicitlyTwoWay
      --                       || (assumeBidirectional && tag == ""))
      --
      -- so a value none of the three predicates recognise — a typo, a
      -- conditional restriction like "yes @ (Mo-Fr 07:00-09:00)" — falls
      -- through every branch: the `tag == ""` guard fails because the tag is
      -- present, and no backward edge is added. The way ends up one-way even
      -- though nothing said so.
      --
      -- Arguably it should fall back to the untagged behaviour. It is asserted
      -- here as-is because the point of this port is to match the Go backend,
      -- and a silent behavioural difference in one-way handling would be a
      -- genuinely confusing one to debug. Change both backends together.
      net <- twoNodeWay (Just "maybe") defaultBuildOptions
      directions net `shouldBe` (True, False)

  describe "Mapping.buildNetwork with missing node references" $
    it "abandons the rest of a way and counts it, rather than failing" $ do
      -- Normal at the edge of a bounding box: a way names a node Overpass did
      -- not send. A partial network is still routable, so this must not be an
      -- error.
      response <- decodeResponse missingRefFixture
      (net, stats) <- mustRight (buildNetwork defaultBuildOptions response)
      stats.missingNodeRefs `shouldBe` 1
      -- The first segment resolved, so both of its nodes are present; the
      -- unresolvable third reference stopped the walk there.
      Graph.nodeCount net `shouldBe` 2

  describe "Mapping.buildNetwork edge metadata" $
    it "carries the way ID and street name onto every edge" $ do
      net <- twoNodeWay Nothing defaultBuildOptions
      map (.wayId) (allEdges net) `shouldSatisfy` all (== 100)
      map (.name) (allEdges net) `shouldSatisfy` all (== "Test Street")

-- | Is there an edge 1→2, and is there an edge 2→1?
directions :: Network -> (Bool, Bool)
directions net =
  ( any (\e -> e.to == NodeID 2) (Graph.neighbours (NodeID 1) net)
  , any (\e -> e.to == NodeID 1) (Graph.neighbours (NodeID 2) net)
  )

-- | Assert the edge directions produced by a given @oneway@ tag value.
expectDirections :: (Bool, Bool) -> Text -> Expectation
expectDirections expected tag = do
  net <- twoNodeWay (Just tag) defaultBuildOptions
  directions net `shouldBe` expected

-- | Every directed edge in the network.
allEdges :: Network -> [Edge]
allEdges net = concat (Map.elems net.adjacency)

-- | Build a one-segment network from a synthetic Overpass response, optionally
-- tagging the way with a @oneway@ value.
twoNodeWay :: Maybe Text -> BuildOptions -> IO Network
twoNodeWay onewayTag options = do
  response <- decodeResponse (twoNodeFixture onewayTag)
  fst <$> mustRight (buildNetwork options response)

-- | Decode a synthetic response, failing the test if it is malformed.
--
-- Fixtures are built as @aeson@ 'Value's and encoded, rather than written as
-- JSON string literals. A literal with a typo produces a confusing decode
-- failure halfway through a test; building the value means the compiler checks
-- the structure.
decodeResponse :: Value -> IO Response
decodeResponse = mustRight . Aeson.eitherDecode . encode

-- | Two nodes about 111 m apart, joined by one way.
twoNodeFixture :: Maybe Text -> Value
twoNodeFixture onewayTag =
  object
    [ "elements"
        .= [ object ["type" .= t "node", "id" .= i 1, "lat" .= (-37.800 :: Double), "lon" .= (144.900 :: Double)]
           , object ["type" .= t "node", "id" .= i 2, "lat" .= (-37.801 :: Double), "lon" .= (144.900 :: Double)]
           , object
              [ "type" .= t "way"
              , "id" .= i 100
              , "nodes" .= map i [1, 2]
              , "tags" .= object (baseTags <> onewayTags)
              ]
           ]
    ]
  where
    baseTags = ["highway" .= t "residential", "name" .= t "Test Street"]
    onewayTags = maybe [] (\tag -> ["oneway" .= tag]) onewayTag

-- | A way whose third node reference is missing from the response.
missingRefFixture :: Value
missingRefFixture =
  object
    [ "elements"
        .= [ object ["type" .= t "node", "id" .= i 1, "lat" .= (-37.800 :: Double), "lon" .= (144.900 :: Double)]
           , object ["type" .= t "node", "id" .= i 2, "lat" .= (-37.801 :: Double), "lon" .= (144.900 :: Double)]
           , object
              [ "type" .= t "way"
              , "id" .= i 100
              , "nodes" .= map i [1, 2, 999]
              , "tags" .= object ["highway" .= t "residential"]
              ]
           ]
    ]

-- Small type-annotating helpers, so the literals above do not need inline
-- signatures. OverloadedStrings would otherwise leave every string ambiguous.
t :: Text -> Text
t = id

i :: Int -> Int
i = id
