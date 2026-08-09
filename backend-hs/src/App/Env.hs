-- |
-- Module      : App.Env
-- Description : The application environment, and the monad that carries it.
--
-- Ports the scattered global state of the Go backend — its two package-level
-- @http.Client@ values, the @NetworkCache@ hanging off @Server@, and the URL
-- override fields on @server.Options@ — into one record created at startup and
-- threaded through the request pipeline.
module App.Env
  ( -- * Environment
    Env (..)
  , Endpoints (..)
  , defaultEndpoints
  , newEnv
  , newEnvWith

    -- * The application monad
  , AppM
  , runAppM
  , attempt
  , failWith
  ) where

import App.Error (AppError)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, runReaderT)
import Data.Text (Text)
import Geo.Nominatim (defaultReverseURL, defaultSearchURL)
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Overpass.Client (defaultOverpassURL)
import Services.Cache (NetworkCache, newCache)

-- | Where the outbound calls go.
--
-- __Why these are data and not constants.__ Go makes each external call through
-- a production function (@Geocode@) with a parallel @…WithBaseURL@ twin that
-- tests call instead — and because the override has to reach the bottom of the
-- stack, @server.Options@, @services.AddressRouteRequest@ and three
-- @…WithOptionalOverride@ helpers all carry test-only URL fields. That is six
-- functions and three record fields existing purely so tests can redirect a
-- hostname.
--
-- Making the endpoints part of the environment removes all of it. There is one
-- 'Geo.Geocode.geocode', and it reads its base URL from here. Tests build an
-- 'Env' pointing at a local stub; production builds one pointing at the real
-- APIs. The production code path and the tested code path are the same path,
-- which is the property the Go arrangement cannot quite claim.
data Endpoints = Endpoints
  { nominatimSearch :: !Text
  -- ^ Used by both geocoding and autocomplete — Nominatim serves them from
  -- the same @\/search@ endpoint, differing only in @limit@.
  , nominatimReverse :: !Text
  , overpassInterpreter :: !Text
  }
  deriving stock (Eq, Show)

-- | The live public APIs.
defaultEndpoints :: Endpoints
defaultEndpoints =
  Endpoints
    { nominatimSearch = defaultSearchURL
    , nominatimReverse = defaultReverseURL
    , overpassInterpreter = defaultOverpassURL
    }

-- | Everything a request handler needs that it did not get from the request.
--
-- If you know ASP.NET Core, this is the set of services you would register as
-- singletons in @Startup@ — created once, shared by every request, never
-- rebuilt per call.
data Env = Env
  { httpManager :: !Manager
  -- ^ __One manager for the whole process.__ A 'Manager' owns a connection
  -- pool, so sharing it means TLS handshakes to Nominatim and Overpass are
  -- paid once rather than per request. Creating one per call — the mistake
  -- this field exists to prevent — leaks connections and is measurably
  -- slower.
  , networkCache :: !NetworkCache
  -- ^ Shared across all requests, so a Dijkstra run and an A* run over the
  -- same addresses share one Overpass fetch.
  , endpoints :: !Endpoints
  , staticDir :: !FilePath
  -- ^ Directory holding the built frontend, served for any path the API does
  -- not claim.
  }

-- | Build an environment pointing at the live APIs.
newEnv :: FilePath -> IO Env
newEnv = newEnvWith defaultEndpoints

-- | Build an environment with explicit endpoints — how tests inject stubs.
newEnvWith :: Endpoints -> FilePath -> IO Env
newEnvWith targets staticPath = do
  manager <- newManager tlsManagerSettings
  cache <- newCache
  pure
    Env
      { httpManager = manager
      , networkCache = cache
      , endpoints = targets
      , staticDir = staticPath
      }

-- | The monad every step of the routing pipeline runs in.
--
-- Read it outside-in: a computation that can read an 'Env' ('ReaderT'), can
-- fail with an 'AppError' ('ExceptT'), and can perform I\/O.
--
-- __Why a transformer stack and not an explicit @Env@ parameter.__ The rewrite
-- plan sketches @routeByAddress :: Env -> Request -> ExceptT AppError IO a@,
-- passing the environment by hand. That works, and for a two-step pipeline it
-- would be simpler. But every helper then grows an @Env@ parameter it only
-- forwards, and the noise scales with the call graph. 'ReaderT' over 'IO' — the
-- shape most production Haskell converges on — makes the environment ambient
-- and available via 'Control.Monad.Reader.ask' wherever it is genuinely needed.
-- The stack is otherwise identical to the plan's: @ExceptT AppError IO@ with
-- @Env@ moved from an argument into the monad.
--
-- __Why a type synonym and not a newtype.__ A synonym inherits 'Monad',
-- 'MonadIO', 'MonadReader' and 'MonadError' instances for free, so there is no
-- deriving boilerplate and no lifting to write. A @newtype@ would buy the
-- ability to hide those instances from callers; at this size that is a cost,
-- not a benefit.
--
-- __The C# analogy.__ @async Task\<T\>@ that can throw a typed @AppError@ and has
-- an ambient injected @Env@. The difference is that here both the failure and
-- the dependency are visible in the type, so a function that cannot fail says
-- so.
type AppM = ReaderT Env (ExceptT AppError IO)

-- | Run a pipeline, surfacing failure as an 'Either'.
--
-- This is where the two layers are peeled off: 'runReaderT' supplies the
-- environment, 'runExceptT' turns a short-circuit into a 'Left'.
runAppM :: Env -> AppM a -> IO (Either AppError a)
runAppM env action = runExceptT (runReaderT action env)

-- | Run an @IO@ action that returns its own error type, and adopt any failure
-- into 'AppM'.
--
-- Every layer below has its own error type, and this is the one place they are
-- adapted. In Go the same job is @if err != nil { return fmt.Errorf(\"…: %w\",
-- err) }@ repeated after each call; here it is a combinator applied at each
-- call, and the wrapping constructor is checked by the compiler.
attempt :: (e -> AppError) -> IO (Either e a) -> AppM a
attempt toAppError action = do
  result <- liftIO action
  case result of
    Left cause -> throwError (toAppError cause)
    Right value -> pure value

-- | Adopt a pure 'Either' into 'AppM'.
--
-- Used for the steps that do no I\/O — building the network, snapping, running
-- the search — so a failure there short-circuits the pipeline the same way an
-- I\/O failure does.
failWith :: (e -> AppError) -> Either e a -> AppM a
failWith toAppError = either (throwError . toAppError) pure
