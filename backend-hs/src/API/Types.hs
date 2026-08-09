{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeOperators #-}

-- |
-- Module      : API.Types
-- Description : The HTTP surface, as a type — plus the JSON wire shapes.
--
-- Ports the request\/response structs and the route registration from
-- @backend/server/handlers.go@ and @backend/server/server.go@.
--
-- This module is where Servant earns its keep: the API is /declared/ as a type,
-- and "API.Handlers" is checked against that declaration at compile time.
module API.Types
  ( -- * The API
    API
  , api

    -- * Requests
  , RouteRequestJSON (..)

    -- * Responses
  , RouteResponseJSON (..)
  , PathNodeJSON (..)
  , CoordJSON (..)
  , ReverseResponseJSON (..)

    -- * Conversion
  , toRouteResponse
  ) where

import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , object
  , withObject
  , (.!=)
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Geo.Suggest (SuggestResult)
import Geo.Types (Coord (..))
import Graph (Node (..), NodeID (..))
import Routefinding.Router (algorithmName)
import Servant
  ( Get
  , JSON
  , Post
  , QueryParam
  , Raw
  , ReqBody
  , type (:<|>)
  , type (:>)
  )
import Services.Routing (RouteOutcome (..))

-- | The entire HTTP surface of the backend, as a single type.
--
-- __What is going on here.__ @:>@ reads as \"then\": @\"api\" :> \"route\" :>
-- ReqBody '[JSON] r :> Post '[JSON] s@ is \"the path @\/api\/route@, then a JSON
-- request body of type @r@, then a POST returning JSON of type @s@\". @:\<|>@
-- separates alternative endpoints and reads as \"or\".
--
-- __Why this is worth the unfamiliarity.__ Servant derives the handler type
-- from this declaration, so the compiler checks that "API.Handlers" implements
-- exactly this API: wrong response shape, missing endpoint, or handlers in the
-- wrong order are all type errors, not runtime 500s. Go's
-- @mux.HandleFunc(\"POST \/api\/route\", s.handleRoute)@ associates a path with a
-- function and checks nothing about what that function reads or writes.
--
-- __On @lat@ and @lon@ as 'Text'.__ @QueryParam \"lat\" Double@ would have
-- Servant parse and reject invalid values for us — but with Servant's own error
-- body, not the @{\"error\": \"invalid lat: …\"}@ shape the Go backend returns.
-- Taking the raw text and parsing in the handler keeps the wire contract
-- identical. A deliberate trade of type-level convenience for byte-level
-- compatibility.
--
-- __The trailing @Raw@__ serves the built frontend for any path the API routes
-- above do not claim, replacing Go's
-- @mux.Handle(\"\/\", http.FileServer(...))@. It must come last: Servant tries
-- alternatives in order, and @Raw@ matches everything.
type API =
  "api" :> "route" :> ReqBody '[JSON] RouteRequestJSON :> Post '[JSON] RouteResponseJSON
    :<|> "api" :> "suggest" :> QueryParam "q" Text :> Get '[JSON] [SuggestResult]
    :<|> "api"
      :> "reverse"
      :> QueryParam "lat" Text
      :> QueryParam "lon" Text
      :> Get '[JSON] ReverseResponseJSON
    :<|> Raw

-- | Value-level witness for 'API', for passing to @serve@.
--
-- 'Proxy' carries no data — it exists only so a type can be passed to a
-- function that needs to know it. The @Proxy \@API@ spelling in "API.Handlers"
-- and @Main@ is the same idea written with a type application.
api :: Proxy API
api = Proxy

-- | The body of @POST \/api\/route@.
--
-- @algorithm@ is optional and defaults to @\"\"@, which
-- 'Routefinding.Router.parseAlgorithm' maps to Dijkstra — so an older client
-- that omits the field keeps working, exactly as with Go's zero-valued string.
data RouteRequestJSON = RouteRequestJSON
  { origin :: !Text
  , destination :: !Text
  , algorithm :: !Text
  }
  deriving stock (Eq, Show)

instance FromJSON RouteRequestJSON where
  parseJSON = withObject "RouteRequest" $ \o ->
    RouteRequestJSON
      <$> o .: "origin"
      <*> o .: "destination"
      <*> o .:? "algorithm" .!= ""

instance ToJSON RouteRequestJSON where
  toJSON request =
    object
      [ "origin" .= request.origin
      , "destination" .= request.destination
      , "algorithm" .= request.algorithm
      ]

-- | A lat\/lon pair, as the frontend's @Coord@ interface.
data CoordJSON = CoordJSON
  { lat :: !Double
  , lon :: !Double
  }
  deriving stock (Eq, Show)

instance ToJSON CoordJSON where
  toJSON c = object ["lat" .= c.lat, "lon" .= c.lon]

instance FromJSON CoordJSON where
  parseJSON = withObject "Coord" $ \o -> CoordJSON <$> o .: "lat" <*> o .: "lon"

-- | One node of the returned path, as the frontend's @PathNode@ interface.
data PathNodeJSON = PathNodeJSON
  { nodeId :: !Int
  , lat :: !Double
  , lon :: !Double
  }
  deriving stock (Eq, Show)

instance ToJSON PathNodeJSON where
  toJSON n = object ["node_id" .= n.nodeId, "lat" .= n.lat, "lon" .= n.lon]

instance FromJSON PathNodeJSON where
  parseJSON = withObject "PathNode" $ \o ->
    PathNodeJSON <$> o .: "node_id" <*> o .: "lat" <*> o .: "lon"

-- | The body of a successful @POST \/api\/route@.
--
-- __The field names are a contract.__ @frontend/src/types.ts@ declares this
-- shape as a TypeScript interface, and @animation.ts@ reads @visited_nodes@
-- directly. Renaming a key here silently breaks the map.
--
-- __Why the instances are hand-written.__ @aeson@ could derive these from
-- 'Generic' with a @fieldLabelModifier@ turning @distanceMeters@ into
-- @distance_meters@. That is less code, but it makes the wire format a
-- consequence of a naming convention: rename a Haskell field and the JSON
-- changes silently. Writing @\"distance_meters\" .= …@ puts the contract in
-- plain sight, which is worth more than the lines it costs in the one module
-- where an external consumer is watching.
data RouteResponseJSON = RouteResponseJSON
  { algorithm :: !Text
  , distanceMeters :: !Double
  , path :: ![PathNodeJSON]
  , visitedNodes :: ![CoordJSON]
  , originCoord :: !CoordJSON
  , destinationCoord :: !CoordJSON
  }
  deriving stock (Eq, Show)

instance ToJSON RouteResponseJSON where
  toJSON response =
    object
      [ "algorithm" .= response.algorithm
      , "distance_meters" .= response.distanceMeters
      , "path" .= response.path
      , "visited_nodes" .= response.visitedNodes
      , "origin_coord" .= response.originCoord
      , "destination_coord" .= response.destinationCoord
      ]

instance FromJSON RouteResponseJSON where
  parseJSON = withObject "RouteResponse" $ \o ->
    RouteResponseJSON
      <$> o .: "algorithm"
      <*> o .: "distance_meters"
      <*> o .: "path"
      <*> o .: "visited_nodes"
      <*> o .: "origin_coord"
      <*> o .: "destination_coord"

-- | The body of @GET \/api\/reverse@.
newtype ReverseResponseJSON = ReverseResponseJSON
  { address :: Text
  }
  deriving stock (Eq, Show)

instance ToJSON ReverseResponseJSON where
  toJSON r = object ["address" .= r.address]

instance FromJSON ReverseResponseJSON where
  parseJSON = withObject "ReverseResponse" $ \o ->
    ReverseResponseJSON <$> o .: "address"

-- | Project a pipeline result onto the wire shape.
--
-- Note the asymmetry, faithfully preserved from Go: @path@ carries node IDs and
-- coordinates, while @visited_nodes@ carries coordinates only. The animation
-- just draws dots and does not need identity, and a long Dijkstra search can
-- settle tens of thousands of nodes — dropping the IDs meaningfully shrinks the
-- response.
toRouteResponse :: RouteOutcome -> RouteResponseJSON
toRouteResponse outcome =
  RouteResponseJSON
    { algorithm = algorithmName outcome.algorithm
    , distanceMeters = outcome.distanceMeters
    , path = map toPathNode outcome.pathNodes
    , visitedNodes = map (toCoordJSON . (.coord)) outcome.visitedNodes
    , originCoord = toCoordJSON outcome.originCoord
    , destinationCoord = toCoordJSON outcome.destinationCoord
    }
  where
    toPathNode node =
      PathNodeJSON
        { nodeId = fromIntegral (unNodeID node.nodeId)
        , lat = node.coord.lat
        , lon = node.coord.lon
        }

    toCoordJSON :: Coord -> CoordJSON
    toCoordJSON c = CoordJSON {lat = c.lat, lon = c.lon}
