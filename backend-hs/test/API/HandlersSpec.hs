{-# LANGUAGE OverloadedRecordDot #-}

-- | Ports @backend/server/handlers_test.go@ and @middleware_test.go@.
--
-- These tests drive a real Warp server and talk to it over a real socket, the
-- direct equivalent of Go's @httptest.Server@. Invoking the WAI 'Application'
-- in process would be faster, but it would skip exactly the parts most likely
-- to be wrong: content negotiation, status codes and the CORS middleware.
module API.HandlersSpec (spec) where

import API.Handlers (application)
import API.Types
  ( CoordJSON (..)
  , PathNodeJSON (..)
  , ReverseResponseJSON (..)
  , RouteResponseJSON (..)
  )
import App.Env (Endpoints (..), newEnvWith)
import Data.Aeson (Value, decode, encode, object, (.=))
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Geo.Suggest (SuggestResult (..))
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , Response (..)
  , defaultManagerSettings
  , httpLbs
  , newManager
  , parseRequest
  )
import Network.HTTP.Types (HeaderName, status404, statusCode)
import Network.Wai (Application, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)
import Test.Hspec
import TestSupport (jsonResponse, lookupQuery, routeByPath, shouldBeApprox, withStubUpstream)

spec :: Spec
spec = do
  describe "POST /api/route" $ do
    it "answers 200 with a path, distance and visited nodes" $
      withBackend upstream $ \manager base -> do
        response <- post manager (base <> "/api/route") (routeBody "dijkstra")
        statusCode response.responseStatus `shouldBe` 200
        body <- decodeBody response
        body.algorithm `shouldBe` "dijkstra"
        body.distanceMeters `shouldBeApprox` 349.24
        map (.nodeId) body.path `shouldBe` [27347732, 27347731, 27347730, 27347728, 27347729, 271299529, 27347552]
        length body.visitedNodes `shouldSatisfy` (> 0)

    it "returns the geocoded origin and destination coordinates" $
      withBackend upstream $ \manager base -> do
        response <- post manager (base <> "/api/route") (routeBody "dijkstra")
        body <- decodeBody response
        body.originCoord.lat `shouldBeApprox` (-37.8916497)
        body.destinationCoord.lon `shouldBeApprox` 145.1069308

    it "accepts every algorithm the frontend offers" $
      withBackend upstream $ \manager base ->
        mapM_
          ( \name -> do
              response <- post manager (base <> "/api/route") (routeBody name)
              statusCode response.responseStatus `shouldBe` 200
              body <- decodeBody response
              body.algorithm `shouldBe` name
          )
          ["dijkstra", "astar", "greedy", "bidijkstra"]

    it "defaults to Dijkstra when the algorithm field is omitted" $
      withBackend upstream $ \manager base -> do
        let body = object ["origin" .= originAddress, "destination" .= destinationAddress]
        response <- post manager (base <> "/api/route") body
        statusCode response.responseStatus `shouldBe` 200
        decoded <- decodeBody response
        decoded.algorithm `shouldBe` "dijkstra"

    it "answers 400 when the origin is missing" $
      withBackend upstream $ \manager base -> do
        let body = object ["origin" .= ("" :: Text), "destination" .= destinationAddress]
        response <- post manager (base <> "/api/route") body
        statusCode response.responseStatus `shouldBe` 400
        errorText response `shouldSatisfy` (`contains` "origin and destination are required")

    it "answers 400 for an unknown algorithm" $
      withBackend upstream $ \manager base -> do
        response <- post manager (base <> "/api/route") (routeBody "quicksort")
        statusCode response.responseStatus `shouldBe` 400
        errorText response `shouldSatisfy` (`contains` "unknown algorithm")

    it "answers 400 for a malformed JSON body" $
      withBackend upstream $ \manager base -> do
        response <- postRaw manager (base <> "/api/route") "{not json"
        statusCode response.responseStatus `shouldBe` 400

    it "answers with a JSON error body, not plain text" $
      -- The frontend parses `data.error`. Servant's default error body is
      -- text/plain, so this is a real thing to get wrong.
      withBackend upstream $ \manager base -> do
        response <- post manager (base <> "/api/route") (routeBody "quicksort")
        (decode response.responseBody :: Maybe Value) `shouldSatisfy` isJust'
        header "Content-Type" response `shouldSatisfy` (`contains` "application/json")

  describe "GET /api/suggest" $ do
    it "returns parsed suggestions" $
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/suggest?q=Gillon")
        statusCode response.responseStatus `shouldBe` 200
        let decoded = decode response.responseBody :: Maybe [SuggestResult]
        fmap (map (.displayName)) decoded `shouldBe` Just ["stub"]

    it "returns an empty array for an empty query" $
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/suggest?q=")
        statusCode response.responseStatus `shouldBe` 200
        response.responseBody `shouldBe` "[]"

    it "returns an empty array when the query parameter is absent" $
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/suggest")
        statusCode response.responseStatus `shouldBe` 200
        response.responseBody `shouldBe` "[]"

    it "returns an empty array with a 200 when Nominatim fails" $
      -- Autocomplete fires on every keystroke. A transient upstream hiccup must
      -- not become a red error banner.
      withBackend brokenUpstream $ \manager base -> do
        response <- get manager (base <> "/api/suggest?q=Gillon")
        statusCode response.responseStatus `shouldBe` 200
        response.responseBody `shouldBe` "[]"

  describe "GET /api/reverse" $ do
    it "returns the reverse-geocoded address" $
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/reverse?lat=-37.82&lon=144.97")
        statusCode response.responseStatus `shouldBe` 200
        let decoded = decode response.responseBody :: Maybe ReverseResponseJSON
        fmap (.address) decoded `shouldBe` Just "123 Test Street, Melbourne"

    it "answers 400 for an unparseable latitude" $
      -- The caller sent something wrong and should be told, unlike an upstream
      -- failure which is not their fault.
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/reverse?lat=abc&lon=144.97")
        statusCode response.responseStatus `shouldBe` 400
        errorText response `shouldSatisfy` (`contains` "invalid lat")

    it "answers 400 when the latitude is missing entirely" $
      withBackend upstream $ \manager base -> do
        response <- get manager (base <> "/api/reverse?lon=144.97")
        statusCode response.responseStatus `shouldBe` 400

    it "answers 200 with an empty address when Nominatim fails" $
      -- The frontend can still drop its pin and let the user type the address.
      withBackend brokenUpstream $ \manager base -> do
        response <- get manager (base <> "/api/reverse?lat=-37.82&lon=144.97")
        statusCode response.responseStatus `shouldBe` 200
        let decoded = decode response.responseBody :: Maybe ReverseResponseJSON
        fmap (.address) decoded `shouldBe` Just ""

  describe "CORS" $ do
    it "adds Access-Control-Allow-Origin to a normal cross-origin response" $
      -- The Vite dev server runs on a different port, so without this the
      -- browser refuses every response.
      withBackend upstream $ \manager base -> do
        response <- getWithOrigin manager (base <> "/api/suggest?q=") "http://localhost:5173"
        header "Access-Control-Allow-Origin" response `shouldSatisfy` (/= "")

    it "answers a preflight OPTIONS request without reaching a handler" $
      withBackend upstream $ \manager base -> do
        response <- preflight manager (base <> "/api/route") "http://localhost:5173"
        statusCode response.responseStatus `shouldSatisfy` (< 300)
        header "Access-Control-Allow-Methods" response `shouldSatisfy` (`contains` "POST")

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

originAddress, destinationAddress :: Text
originAddress = "Gillon Court, Melbourne"
destinationAddress = "Estelle Street, Melbourne"

routeBody :: Text -> Value
routeBody algorithm =
  object
    [ "origin" .= originAddress
    , "destination" .= destinationAddress
    , "algorithm" .= algorithm
    ]

-- | Start a stub upstream, build an 'Env' pointing at it, start the real
-- backend on another free port, and hand both to the action.
withBackend :: Application -> (Manager -> String -> IO a) -> IO a
withBackend upstreamApp action =
  withStubUpstream upstreamApp $ \upstreamBase -> do
    env <-
      newEnvWith
        Endpoints
          { nominatimSearch = upstreamBase <> "/search"
          , nominatimReverse = upstreamBase <> "/reverse"
          , overpassInterpreter = upstreamBase <> "/interpreter"
          }
        "test/testdata"
    manager <- newManager defaultManagerSettings
    testWithApplication (pure (application env)) $ \port ->
      action manager ("http://127.0.0.1:" <> show port)

-- | A stub standing in for Nominatim search, Nominatim reverse and Overpass.
upstream :: Application
upstream =
  routeByPath
    [ ("/search", searchApp)
    , ("/reverse", jsonResponse "{\"display_name\":\"123 Test Street, Melbourne\"}")
    , ("/interpreter", overpassApp)
    ]
    notFound
  where
    searchApp request respond = jsonResponse (hitFor query) request respond
      where
        query = maybe "" BS8.unpack (lookupQuery "q" request)

    hitFor query
      | take 6 query == "Gillon" = latLonHit "-37.8916497" "145.1044461"
      | otherwise = latLonHit "-37.8931412" "145.1069308"

    overpassApp request respond = do
      body <- LBS.readFile "test/testdata/sample_overpass.json"
      jsonResponse body request respond

-- | An upstream that fails every request, for the graceful-degradation tests.
brokenUpstream :: Application
brokenUpstream _ respond = respond (responseLBS status404 [] "upstream is down")

notFound :: Application
notFound _ respond = respond (responseLBS status404 [] "no such stub route")

latLonHit :: Text -> Text -> LBS.ByteString
latLonHit latitude longitude =
  "[{\"lat\":\""
    <> textBytes latitude
    <> "\",\"lon\":\""
    <> textBytes longitude
    <> "\",\"display_name\":\"stub\"}]"
  where
    textBytes = LBS.fromStrict . TE.encodeUtf8

-- ---------------------------------------------------------------------------
-- Tiny HTTP client helpers
-- ---------------------------------------------------------------------------

get :: Manager -> String -> IO (Response LBS.ByteString)
get manager url = do
  request <- parseRequest url
  httpLbs (allow4xx request) manager

getWithOrigin :: Manager -> String -> BS8.ByteString -> IO (Response LBS.ByteString)
getWithOrigin manager url origin = do
  request <- parseRequest url
  httpLbs (allow4xx request) {requestHeaders = [("Origin", origin)]} manager

preflight :: Manager -> String -> BS8.ByteString -> IO (Response LBS.ByteString)
preflight manager url origin = do
  request <- parseRequest url
  httpLbs
    (allow4xx request)
      { method = "OPTIONS"
      , requestHeaders =
          [ ("Origin", origin)
          , ("Access-Control-Request-Method", "POST")
          , ("Access-Control-Request-Headers", "Content-Type")
          ]
      }
    manager

post :: Manager -> String -> Value -> IO (Response LBS.ByteString)
post manager url body = postRaw manager url (encode body)

postRaw :: Manager -> String -> LBS.ByteString -> IO (Response LBS.ByteString)
postRaw manager url body = do
  request <- parseRequest url
  httpLbs
    (allow4xx request)
      { method = "POST"
      , requestBody = RequestBodyLBS body
      , requestHeaders = [("Content-Type", "application/json")]
      }
    manager

-- | Stop http-client throwing on 4xx/5xx: these tests assert on status codes.
allow4xx :: Request -> Request
allow4xx request = request {checkResponse = \_ _ -> pure ()}

decodeBody :: Response LBS.ByteString -> IO RouteResponseJSON
decodeBody response =
  case decode response.responseBody of
    Just value -> pure value
    Nothing ->
      fail ("could not decode route response: " <> show response.responseBody)

-- | The response body as a String, for substring assertions.
errorText :: Response LBS.ByteString -> String
errorText response = BS8.unpack (LBS.toStrict response.responseBody)

-- | A response header's value, or "" if absent.
--
-- The literal at each call site is a 'HeaderName' (a case-insensitive
-- ByteString) thanks to OverloadedStrings, so header lookups are
-- case-insensitive without any explicit conversion.
header :: HeaderName -> Response LBS.ByteString -> String
header name response =
  maybe "" BS8.unpack (lookup name response.responseHeaders)

contains :: String -> String -> Bool
contains haystack needle = needle `isInfixOf` haystack

isJust' :: Maybe a -> Bool
isJust' (Just _) = True
isJust' Nothing = False
