{-# LANGUAGE DataKinds #-}
-- DuplicateRecordFields implies DisambiguateRecordFields, which is what lets
-- `RouteRequest { origin = ... }` below resolve: both API.Types.RouteRequestJSON
-- and Services.Routing.RouteRequest have an `origin` field, and naming the
-- constructor is enough to say which is meant. Reads for `request.origin` go
-- through OverloadedRecordDot and are resolved by the record's type.
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : API.Handlers
-- Description : Handler implementations, CORS, and the WAI application.
--
-- Ports @backend/server/handlers.go@ and the middleware in
-- @backend/server/server.go@.
module API.Handlers
  ( -- * The application
    application
  , server

    -- * Individual handlers
  , handleRoute
  , handleSuggest
  , handleReverse

    -- * Middleware
  , corsMiddleware
  ) where

import API.Types
  ( API
  , ReverseResponseJSON (..)
  , RouteRequestJSON (..)
  , RouteResponseJSON
  , api
  , toRouteResponse
  )
import App.Env (AppM, Endpoints (..), Env (..), runAppM)
import App.Error (AppError (..), toServantError)
import Control.Monad (when)
import Control.Monad.Except (throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Geo.Reverse (reverseGeocode)
import Geo.Suggest (SuggestResult, suggest)
import Geo.Types (Coord (..))
import Mapping (defaultBuildOptions)
import Network.Wai (Application, Middleware)
import Network.Wai.Middleware.Cors
  ( CorsResourcePolicy (..)
  , cors
  , simpleCorsResourcePolicy
  )
import Routefinding.Router (parseAlgorithm)
import Servant
  ( Handler
  , Raw
  , Server
  , ServerT
  , hoistServer
  , serve
  , type (:<|>) (..)
  )
import Servant.Server.StaticFiles (serveDirectoryFileServer)
import Services.Routing (RouteRequest (..), routeByAddress)
import Text.Read (readMaybe)

-- | The three API handlers plus the static-file fallback, written in 'AppM'.
--
-- __Why 'ServerT' and 'hoistServer'.__ Servant's own handler monad is 'Handler'
-- (which is @ExceptT ServerError IO@). Our pipeline runs in 'AppM', which knows
-- about 'Env' and 'AppError' and nothing about HTTP. Writing the handlers in
-- 'AppM' and converting once — that is what 'hoistServer' does in 'server' —
-- keeps HTTP vocabulary out of the business logic and confines the
-- @AppError -> ServerError@ translation to one function.
--
-- If you have met the pattern in C#: the same instinct as keeping
-- @ControllerBase@ out of your service classes and mapping exceptions to status
-- codes in a single filter.
--
-- __The order matters.__ Servant matches these alternatives left to right
-- against the API type, and the compiler checks that this list lines up with
-- 'API' constructor for constructor. Swap two handlers and it will not compile.
handlers :: FilePath -> ServerT API AppM
handlers staticPath =
  handleRoute
    :<|> handleSuggest
    :<|> handleReverse
    :<|> staticFiles staticPath

-- | Static file fallback, replacing Go's @http.FileServer(http.Dir(...))@.
--
-- A @Raw@ endpoint is a plain WAI application and so cannot read 'AppM''s
-- environment; the directory is captured from 'Env' when the server is built
-- instead.
staticFiles :: FilePath -> ServerT Raw AppM
staticFiles = serveDirectoryFileServer

-- | Interpret the API in Servant's 'Handler' monad.
--
-- 'hoistServer' applies one natural transformation — \"how to run an 'AppM' as
-- a 'Handler'\" — to every handler at once: run the pipeline, and turn a typed
-- 'AppError' into the 'ServerError' Servant knows how to send.
server :: Env -> Server API
server env = hoistServer api toHandler (handlers env.staticDir)
  where
    toHandler :: AppM a -> Handler a
    toHandler action = do
      outcome <- liftIO (runAppM env action)
      either (throwError . toServantError) pure outcome

-- | The full WAI application: CORS, then routing, then static files.
--
-- Note what is /not/ here. Go wraps everything in @panicRecoveryMiddleware@
-- because an unhandled panic would otherwise take down the whole process. Warp
-- already isolates each request — an exception escaping a handler fails that
-- request with a 500 and leaves the server running — so there is nothing to
-- add. A case where the port is shorter because the platform does more.
application :: Env -> Application
application env = corsMiddleware (serve api (server env))

-- | Allow browser clients from any origin.
--
-- Mirrors Go's @corsMiddleware@: any origin, @GET@\/@POST@\/@OPTIONS@, and a
-- @Content-Type@ request header. @wai-cors@ answers the @OPTIONS@ preflight
-- itself, which is the @if r.Method == http.MethodOptions@ branch in the Go
-- version.
--
-- Wide open is right for a public read-only API called from a Vite dev server
-- on a different port. It would not be right for anything authenticated.
corsMiddleware :: Middleware
corsMiddleware =
  cors . const . Just $
    simpleCorsResourcePolicy
      { corsMethods = ["GET", "POST", "OPTIONS"]
      , corsRequestHeaders = ["Content-Type"]
      }

-- | @POST \/api\/route@ — find a route between two addresses.
--
-- Validates, then delegates. The validation is Go's: both addresses required,
-- algorithm name must be one we recognise. Everything after that is
-- "Services.Routing".
--
-- 'defaultBuildOptions' sets @assumeBidirectional = True@, matching
-- @server/handlers.go@: most OSM residential streets carry no @oneway@ tag, and
-- treating those as one-way would fragment the network past usefulness.
handleRoute :: RouteRequestJSON -> AppM RouteResponseJSON
handleRoute request = do
  when (T.null (T.strip request.origin) || T.null (T.strip request.destination)) $
    throwError (InvalidRequest "origin and destination are required")

  algorithm <- case parseAlgorithm request.algorithm of
    Left message -> throwError (InvalidRequest message)
    Right parsed -> pure parsed

  outcome <-
    routeByAddress
      RouteRequest
        { origin = request.origin
        , destination = request.destination
        , algorithm = algorithm
        , buildOptions = defaultBuildOptions
        }
  pure (toRouteResponse outcome)

-- | @GET \/api\/suggest?q=@ — address autocomplete.
--
-- __This handler never fails.__ A missing query, an upstream outage, a
-- malformed Nominatim response — all produce @[]@ with a 200. Autocomplete
-- fires on every keystroke, and turning a transient upstream hiccup into a red
-- error banner would be far worse than briefly showing no suggestions. Same
-- policy as Go, and @frontend/src/autocomplete.ts@ depends on it.
handleSuggest :: Maybe Text -> AppM [SuggestResult]
handleSuggest query = case fromMaybe "" query of
  "" -> pure []
  actual -> do
    env <- ask
    result <- liftIO (suggest env.httpManager env.endpoints.nominatimSearch actual)
    pure (either (const []) id result)

-- | @GET \/api\/reverse?lat=&lon=@ — coordinate to address.
--
-- __Two different failure policies, both taken from Go.__ An unparseable @lat@
-- or @lon@ is a 400 naming the offending value: the caller sent something wrong
-- and should be told. A Nominatim failure is a 200 with an empty address: the
-- caller did nothing wrong, and the frontend can still drop its pin and let the
-- user type the address in.
handleReverse :: Maybe Text -> Maybe Text -> AppM ReverseResponseJSON
handleReverse rawLat rawLon = do
  latitude <- parseParam "lat" rawLat
  longitude <- parseParam "lon" rawLon
  env <- ask
  result <-
    liftIO $
      reverseGeocode
        env.httpManager
        env.endpoints.nominatimReverse
        Coord {lat = latitude, lon = longitude}
  pure $ case result of
    Left _ -> ReverseResponseJSON {address = ""}
    Right address -> ReverseResponseJSON {address = address}
  where
    -- A missing parameter and an unparseable one get the same treatment,
    -- because Go's strconv.ParseFloat("") fails just as ParseFloat("abc") does.
    parseParam :: Text -> Maybe Text -> AppM Double
    parseParam name value =
      case readMaybe (T.unpack (T.strip given)) of
        Just parsed -> pure parsed
        Nothing ->
          throwError . InvalidRequest $
            "invalid " <> name <> ": " <> T.pack (show given)
      where
        given = fromMaybe "" value
