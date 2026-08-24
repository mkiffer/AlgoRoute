{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Entry point for BOTH executables (see the two @executable@ stanzas in
-- @backend-hs.cabal@). One source file, two builds:
--
--   * @backend-hs-local@ — plain Warp server (this file, no CPP define).
--   * @backend-hs@       — AWS Lambda, built with @cpp-options: -DLAMBDA@, which
--     selects the @#ifdef LAMBDA@ branch and the HAL runtime.
--
-- Both branches build the exact same WAI 'Application'
-- (@corsApp (serve (Proxy @API) (server env))@) — only the runner differs.
module Main (main) where

import Data.Proxy (Proxy (..))
import Network.Wai (Application)
import Servant (serve)

import API.Handlers (corsApp, server)
import API.Types (API)
import Services.Routing (Env, newEnv)

#ifdef LAMBDA
import qualified Network.Wai.Handler.Hal as Hal
#else
import qualified Network.Wai.Handler.Warp as Warp
import Options.Applicative
#endif

-- | The shared application: CORS-wrapped Servant server over "API.Types.API".
--
-- TODO: @corsApp (serve (Proxy \@API) (server env))@.
app :: Env -> Application
app = undefined

#ifdef LAMBDA

-- | Lambda entry: HAL's @run@ drives the custom-runtime event loop; we just
-- hand it the 'Application'. (Plan §8.2.) The binary is deployed as @bootstrap@.
--
-- TODO: @newEnv >>= Hal.run . app@.
main :: IO ()
main = undefined

#else

-- | Local server config from the CLI. (Go: the @-port@/@-serve@ flags.)
newtype CliOptions = CliOptions
  { port :: Int
  }

-- | @optparse-applicative@ parser for 'CliOptions'. (Plan §8.1.)
--
-- TODO: a single @--port@ option, default 8080, via @option auto@.
cliParser :: ParserInfo CliOptions
cliParser = undefined

-- | Local entry: parse flags, build the 'Env', serve with Warp.
--
-- TODO:
--   opts <- execParser cliParser
--   env  <- newEnv
--   putStrLn ("listening on :" <> show (port opts))
--   Warp.run (port opts) (app env)
main :: IO ()
main = undefined

#endif
