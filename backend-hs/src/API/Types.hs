{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeOperators #-}

-- | The Servant API type and the JSON request/response shapes.
-- Port of the wire contract in Go @server/handlers.go@ (@routeRequest@,
-- @routeResponse@, @pathNode@, @coordJSON@, …) and the routes in @server.go@.
--
-- The whole API surface is a single *type*. Servant checks your handlers
-- against it at compile time — a wrong response shape is a type error, not a
-- runtime 500. Slow down and read 'API' one combinator at a time.
--
-- Keep the JSON field names byte-for-byte identical to the Go tags
-- (@distance_meters@, @visited_nodes@, @display_name@, …): the existing
-- frontend depends on them. Use an aeson field-label modifier to map Haskell
-- camelCase to the snake_case wire names (TODO below).
module API.Types
  ( API
  , RouteRequest (..)
  , RouteResponse (..)
  , PathNode (..)
  , CoordJSON (..)
  , SuggestResult (..)
  , ReverseResponse (..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.Int (Int64)
import Data.Text (Text)
import GHC.Generics (Generic)
import Servant

-- | @POST /api/route@, @GET /api/suggest@, @GET /api/reverse@.
-- (Go: the three @mux.HandleFunc@ registrations in @server.go@.)
type API =
       "api" :> "route"
         :> ReqBody '[JSON] RouteRequest
         :> Post '[JSON] RouteResponse
  :<|> "api" :> "suggest"
         :> QueryParam "q" Text
         :> Get '[JSON] [SuggestResult]
  :<|> "api" :> "reverse"
         :> QueryParam "lat" Double
         :> QueryParam "lon" Double
         :> Get '[JSON] ReverseResponse

-- | Body of @POST /api/route@. (Go: @routeRequest@.)
data RouteRequest = RouteRequest
  { origin :: Text
  , destination :: Text
  , algorithm :: Text
  }
  deriving stock (Show, Eq, Generic)

-- | Success body of @POST /api/route@. (Go: @routeResponse@.)
-- Wire names: @distance_meters@, @visited_nodes@, @origin_coord@,
-- @destination_coord@.
data RouteResponse = RouteResponse
  { algorithm :: Text
  , distanceMeters :: Double
  , path :: [PathNode]
  , visitedNodes :: [CoordJSON]
  , originCoord :: CoordJSON
  , destinationCoord :: CoordJSON
  }
  deriving stock (Show, Eq, Generic)

-- | One node on the returned polyline. (Go: @pathNode@; wire name @node_id@.)
data PathNode = PathNode
  { nodeId :: Int64
  , lat :: Double
  , lon :: Double
  }
  deriving stock (Show, Eq, Generic)

-- | A bare lat/lon pair. (Go: @coordJSON@.)
data CoordJSON = CoordJSON
  { lat :: Double
  , lon :: Double
  }
  deriving stock (Show, Eq, Generic)

-- | One autocomplete hit. (Go: @geo.SuggestResult@; wire name @display_name@.)
data SuggestResult = SuggestResult
  { displayName :: Text
  , lat :: Double
  , lon :: Double
  }
  deriving stock (Show, Eq, Generic)

-- | Body of @GET /api/reverse@. (Go: @reverseGeocodeResponse@.)
newtype ReverseResponse = ReverseResponse
  { address :: Text
  }
  deriving stock (Show, Eq, Generic)

-- TODO: derive the JSON instances with snake_case field names. Define one
-- Options value and reuse it, e.g.
--
--   wireOptions :: Options
--   wireOptions = defaultOptions { fieldLabelModifier = camelTo2 '_' }
--
-- then for each type:
--
--   instance ToJSON   RouteResponse where toJSON    = genericToJSON    wireOptions
--   instance FromJSON RouteRequest  where parseJSON = genericParseJSON wireOptions
--
-- Requests only need FromJSON; responses only need ToJSON. Verify the emitted
-- keys against the frontend's expectations before wiring handlers.
instance FromJSON RouteRequest
instance ToJSON RouteResponse
instance ToJSON PathNode
instance ToJSON CoordJSON
instance ToJSON SuggestResult
instance ToJSON ReverseResponse
