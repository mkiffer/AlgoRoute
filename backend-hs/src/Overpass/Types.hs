{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Overpass API response DTOs and JSON parsing.
-- Port of Go @api/overpass/client.go@ (@Response@, @Element@, @Tag@).
--
-- The interesting bit: Go tags @Element@ with a @type@ *string* field and
-- leaves node/way fields as optional pointers. Haskell models it as a real sum
-- type — 'NodeElement' vs 'WayElement' — with a hand-written 'FromJSON' that
-- reads @"type"@ to choose the constructor. This is where a C# discriminated-
-- union instinct pays off. TDD it against @testdata/sample_overpass.json@.
module Overpass.Types
  ( Element (..)
  , Response (..)
  , elemTag
  , mkResponse
  ) where

import Data.Aeson (FromJSON (..), Value (..), withObject, (.!=), (.:), (.:?))
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

-- | One OSM element: a node (with coords) or a way (with a node-id list).
-- (Go: the single @Element@ struct with a @Type@ discriminator.)
data Element
  = NodeElement
      { elemId :: Int64
      , elemLat :: Double
      , elemLon :: Double
      , elemTags :: Map Text Text
      }
  | WayElement
      { elemId :: Int64
      , elemNodeIds :: [Int64]
      , elemTags :: Map Text Text
      }
  deriving stock (Show, Eq)

-- | Parse one element, switching on the @"type"@ field.
--
-- TODO: @withObject "Element" $ \\o -> do  ty <- o .: "type" ; case (ty :: Text) of@
--         "node" -> NodeElement <$> o .: "id" <*> o .: "lat" <*> o .: "lon"
--                                <*> o .:? "tags" .!= mempty
--         "way"  -> WayElement  <$> o .: "id" <*> o .:? "nodes" .!= []
--                                <*> o .:? "tags" .!= mempty
--         _      -> fail ("unknown element type: " <> show ty)
instance FromJSON Element where
  parseJSON = undefined

-- | The parsed response plus the derived lookups the mapping layer needs.
-- (Go: @overpass.Response@ with its @Ways@ / @Nodes@ / @NodeByID@ fields that
-- are populated after unmarshalling, not by it.)
data Response = Response
  { elements :: [Element]
  , ways :: [Element]
  , nodeById :: Map Int64 Element
  }
  deriving stock (Show, Eq)

-- | Decode only the flat @elements@ array; 'mkResponse' fills the rest.
instance FromJSON Response where
  parseJSON = withObject "Response" $ \o ->
    mkResponse <$> o .:? "elements" .!= []

-- | Build the derived indexes from a flat element list — the equivalent of the
-- post-@Unmarshal@ loop shared by Go's @LoadNetworkFromJSON@ and @FetchFromAPI@.
--
-- TODO: partition 'elements' into ways ('WayElement') and a
--       @Map Int64 Element@ of nodes keyed by 'elemId'.
mkResponse :: [Element] -> Response
mkResponse = undefined

-- | Look up an OSM tag on an element. (Go: @Element.Tag@.)
--
-- TODO: @Map.lookup key (elemTags e)@ — works for both constructors since
--       'DuplicateRecordFields' gives both an 'elemTags'.
elemTag :: Text -> Element -> Maybe Text
elemTag = undefined
