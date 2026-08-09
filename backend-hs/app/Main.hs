{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- |
-- Module      : Main
-- Description : Entry point — local Warp server, CLI routing, or AWS Lambda.
--
-- Ports @backend/main.go@, including its two modes: @-serve@ starts the HTTP
-- server, and without it the program routes between two node IDs in a local
-- OSM JSON file and prints the result.
--
-- __One file, two executables.__ @backend-hs.cabal@ compiles this module twice:
-- once as @backend-hs-local@, and once — only under @cabal build -f lambda@ —
-- as @backend-hs@ with @-DLAMBDA@ defined, which selects the AWS Lambda branch
-- of 'main' below. That is what the @cpp-options@ line in the .cabal file is
-- for, and it is the same trick as a C @#ifdef@ because it /is/ a C @#ifdef@:
-- GHC runs the C preprocessor over the file first.
module Main (main) where

import API.Handlers (application)
import App.Env (newEnv)
import App.Error (errorMessage)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Graph (NodeID (..))
import Mapping (defaultBuildOptions)
import Options.Applicative
import Routefinding.Router (algorithmName, allAlgorithms, parseAlgorithm, runRouter)
import Routefinding.Types (RouteResult (..))
import Services.Routing (loadNetworkFromFile)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import Text.Printf (printf)

#ifdef LAMBDA
import Network.Wai.Handler.Hal (runWithOptions, defaultOptions)
#else
import Network.Wai.Handler.Warp (run)
#endif

-- | What the program was asked to do.
--
-- Go uses a single flat set of @flag@ variables and decides between modes by
-- testing @*serveMode@, so a nonsensical combination (@-serve -start 42@) is
-- accepted and the extra flags silently ignored. A sum type makes the two modes
-- exclusive: a 'Serve' carries no node IDs because serving does not have any.
data Command
  = -- | Run the HTTP server.
    Serve ServeOptions
  | -- | Route between two node IDs in a local OSM JSON file.
    RouteFile FileOptions

data ServeOptions = ServeOptions
  { port :: !Int
  , frontendDir :: !FilePath
  }

data FileOptions = FileOptions
  { dataFile :: !FilePath
  , startNode :: !Integer
  , goalNode :: !Integer
  , algorithmArg :: !String
  }

-- | Command-line parser.
--
-- @optparse-applicative@ builds parsers the way @aeson@ builds decoders: small
-- pieces combined with @\<$\>@ and @\<*\>@. The payoff over Go's @flag@ package
-- is @--help@ generated from the same description that does the parsing, so the
-- two cannot drift apart.
commandParser :: Parser Command
commandParser =
  -- --serve selects server mode; its absence selects file mode, matching
  -- main.go's `if *serveMode { … }`.
  flag' () (long "serve" <> help "Run as an HTTP server instead of routing a file")
    *> (Serve <$> serveOptions)
    <|> (RouteFile <$> fileOptions)
  where
    serveOptions =
      ServeOptions
        <$> option
          auto
          ( long "port"
              <> metavar "PORT"
              <> value 8080
              <> showDefault
              <> help "HTTP listen port"
          )
        <*> strOption
          ( long "frontend"
              <> metavar "DIR"
              <> value "../frontend/dist"
              <> showDefault
              <> help "Directory containing the built frontend"
          )

    fileOptions =
      FileOptions
        <$> strOption
          (long "data" <> metavar "FILE" <> help "Path to an OSM JSON file")
        <*> option
          auto
          (long "start" <> metavar "NODE_ID" <> help "Start node ID")
        <*> option
          auto
          (long "end" <> metavar "NODE_ID" <> help "Goal node ID")
        <*> strOption
          ( long "algo"
              <> metavar "NAME"
              <> value "dijkstra"
              <> showDefault
              <> help ("Routing algorithm: " <> algorithmChoices)
          )

    algorithmChoices =
      T.unpack (T.intercalate " | " (map algorithmName allAlgorithms))

-- | Parse arguments, then run the chosen mode.
main :: IO ()
main = do
  -- Force UTF-8 on the output handles.
  --
  -- Haskell picks a handle's encoding from the process locale, so on a machine
  -- with LANG=C or LANG=POSIX — common in containers and CI — writing a single
  -- non-ASCII character (the em dash in --help, or a street name like
  -- "Grüner Weg" from OSM) throws `commitBuffer: invalid argument` and kills
  -- the program. Go has no equivalent failure mode: its strings are already
  -- UTF-8 bytes and it writes them unchanged. Two lines here buy the same
  -- behaviour.
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  invocation <-
    execParser $
      info
        (commandParser <**> helper)
        ( fullDesc
            <> progDesc "AlgoRoute — OpenStreetMap route finding"
            <> header "algoroute — Haskell backend"
        )
  case invocation of
    Serve options -> runServer options
    RouteFile options -> runFileRoute options

#ifdef LAMBDA

-- | AWS Lambda entry point.
--
-- @wai-handler-hal@ adapts a WAI 'Network.Wai.Application' to the Lambda custom
-- runtime: it owns the invocation loop, decodes each API Gateway event into a
-- WAI 'Network.Wai.Request', and encodes the response back. Our application
-- code is unchanged — the same 'application' the Warp server runs.
--
-- The Lambda runtime executes a binary named @bootstrap@; @flake.nix@ renames
-- this executable accordingly when packaging the zip.
--
-- The port and frontend directory are meaningless here: nothing is listening on
-- a socket, and there is no local disk to serve a frontend from (the frontend
-- would be on S3 or a CDN). The static directory is still set so that any
-- request reaching the @Raw@ fallback produces a clean 404 rather than an
-- exception.
runServer :: ServeOptions -> IO ()
runServer options = do
  env <- newEnv options.frontendDir
  runWithOptions defaultOptions (application env)

#else

-- | Start the local Warp server.
--
-- Go builds an @http.Server@, starts it in a goroutine, waits on a
-- @signal.NotifyContext@, and calls @Shutdown@ with a 5-second grace period.
-- Warp's 'run' already installs the equivalent: on @SIGINT@\/@SIGTERM@ it stops
-- accepting new connections and lets in-flight requests finish. Around 30 lines
-- of @main.go@ have no counterpart here because the server library does the job.
runServer :: ServeOptions -> IO ()
runServer options = do
  env <- newEnv options.frontendDir
  putStrLn $ "AlgoRoute server listening on http://localhost:" <> show options.port
  putStrLn $ "Serving frontend from " <> show options.frontendDir
  run options.port (application env)

#endif

-- | Route between two node IDs in a local OSM JSON file and print the result.
--
-- The original CLI behaviour, preserved. Useful for exercising the algorithms
-- against a fixture with no network access at all.
runFileRoute :: FileOptions -> IO ()
runFileRoute options = do
  algorithm <- case parseAlgorithm (T.pack options.algorithmArg) of
    Left message -> die' message
    Right parsed -> pure parsed

  loaded <- loadNetworkFromFile options.dataFile defaultBuildOptions
  network <- either (die' . errorMessage) pure loaded

  let start = NodeID (fromIntegral options.startNode)
      goal = NodeID (fromIntegral options.goalNode)
  case runRouter algorithm network start goal of
    Left err -> die' (T.pack (show err))
    Right result -> do
      TIO.putStrLn ("Algorithm:      " <> algorithmName algorithm)
      printf "Total distance: %.2f meters\n" result.distance
      printf "Path (%d nodes):\n" (length result.path)
      mapM_ (\nodeID -> printf "  %d\n" (unNodeID nodeID)) result.path

-- | Print a message to stderr and exit non-zero.
die' :: T.Text -> IO a
die' message = do
  hPutStrLn stderr ("error: " <> T.unpack message)
  exitFailure
