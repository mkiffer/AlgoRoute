{-# LANGUAGE OverloadedStrings #-}

-- | Servant handlers, wiring, and CORS. Port of Go @server/handlers.go@ +
-- @server/server.go@.
--
-- 'server' assembles the three handlers with ':<|>' in the SAME order as the
-- 'API' type in "API.Types" — Servant matches them positionally at compile
-- time. A Servant 'Handler' is already @ExceptT ServerError IO@, so a pipeline
-- 'AppError' converts cleanly by choosing a status code and 'throwError'-ing a
-- 'ServerError'.
module API.Handlers
  ( server
  , corsApp
  ) where

import Network.Wai (Application)
import Servant

import API.Types
  ( API
  , ReverseResponse
  , RouteRequest
  , RouteResponse
  , SuggestResult
  )
import Services.Routing (Env)

-- | Wire all three handlers together. (Go: the @registerRoutes@ mux.)
--
-- TODO: @server env = handleRoute env :<|> handleSuggest env :<|> handleReverse env@
--       — order MUST match the 'API' type.
server :: Env -> Server API
server = undefined

-- | @POST /api/route@. (Go: @handleRoute@.)
--
-- TODO:
--   1. Convert 'RouteRequest' → 'Services.Routing.AddressRouteRequest'
--      ('Routefinding.Types.parseAlgorithm'; 400 on an unknown algorithm).
--   2. @liftIO (runExceptT (routeByAddress env req'))@.
--   3. 'Left' → 'throwError' (appErrorToServant e);  'Right' → build 'RouteResponse'.
--      Missing origin/destination → @err400@ (Go returns 400 for that).
_handleRoute :: Env -> RouteRequest -> Handler RouteResponse
_handleRoute = undefined

-- | @GET /api/suggest?q=@. Degrades gracefully — any failure (or a missing @q@)
-- returns @[]@ with 200, never an error. (Go: @handleSuggest@.)
--
-- TODO: no/empty @q@ → @pure []@; otherwise run 'Geo.Suggest.suggest' and
--       collapse a 'Left' to @[]@.
_handleSuggest :: Env -> Maybe String -> Handler [SuggestResult]
_handleSuggest = undefined

-- | @GET /api/reverse?lat=&lon=@. Missing/invalid params → @err400@; any
-- Nominatim failure → 200 with an empty address (the frontend still drops a
-- pin). (Go: @handleReverseGeocode@.)
--
-- TODO: require both params (else @err400@); run 'Geo.Reverse.reverseGeocode';
--       'Left' → empty-address 'ReverseResponse'.
_handleReverse :: Env -> Maybe Double -> Maybe Double -> Handler ReverseResponse
_handleReverse = undefined

-- | Map a pipeline 'Services.Routing.AppError' to a Servant 'ServerError'
-- (status + JSON body). (Go: the @writeJSON(w, 4xx/5xx, errorResponse{...})@
-- calls.)
--
-- TODO: @AreaTooLarge@/bad input → @err400@; the rest → @err500@; set the body
--       to @{"error": "..."}@ and @Content-Type: application/json@.
-- appErrorToServant :: AppError -> ServerError
-- appErrorToServant = undefined

-- | Wrap the WAI 'Application' with permissive CORS so the Vite dev server (and
-- any browser origin) can call the API. (Go: @corsMiddleware@; plan §7.2.)
--
-- TODO (from "Network.Wai.Middleware.Cors"):
--   corsApp = cors (const (Just simpleCorsResourcePolicy
--     { corsOrigins        = Nothing               -- allow all
--     , corsMethods        = ["GET","POST","OPTIONS"]
--     , corsRequestHeaders = ["Content-Type"] }))
corsApp :: Application -> Application
corsApp = undefined
