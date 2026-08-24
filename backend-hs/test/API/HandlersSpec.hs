{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | HTTP-level tests for the Servant handlers, via hspec-wai — the Haskell
-- equivalent of Go's httptest.Server tests in @server/handlers_test.go@.
--
-- Only the input-validation / graceful-degradation paths are exercised here so
-- the suite never makes a live Nominatim/Overpass call. (A full happy-path test
-- would inject fake upstream servers — add that once the pipeline works.)
module API.HandlersSpec (spec) where

import Network.Wai (Application)
import Servant (Proxy (..), serve)
import Test.Hspec
import Test.Hspec.Wai

import API.Handlers (server)
import API.Types (API)
import Services.Routing (newEnv)

-- | Build the WAI app once per run, backed by a real Env (TLS manager + cache).
-- No network is touched unless a handler actually calls upstream.
app :: IO Application
app = do
  env <- newEnv
  pure (serve (Proxy @API) (server env))

spec :: Spec
spec = with app $ do
  describe "POST /api/route" $ do
    it "rejects a body missing origin/destination with 400" $
      post "/api/route" "{\"origin\":\"\",\"destination\":\"\",\"algorithm\":\"dijkstra\"}"
        `shouldRespondWith` 400

    it "rejects malformed JSON with 400" $
      post "/api/route" "{ not json" `shouldRespondWith` 400

  describe "GET /api/suggest" $
    it "returns 200 and an empty array when q is absent" $
      get "/api/suggest" `shouldRespondWith` "[]" { matchStatus = 200 }

  describe "GET /api/reverse" $
    it "rejects missing lat/lon with 400" $
      get "/api/reverse" `shouldRespondWith` 400
