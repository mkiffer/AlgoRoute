# `Services/Routing.hs` — the address-to-route pipeline

Where the whole backend comes together. Seven steps, each of which can fail,
composed into one `do` block that reads top to bottom.

## The Go code it replaces

`backend/services/address_routing.go`, `routing.go`, `address_options.go` and
`load_network.go`.

## The pipeline

```haskell
routeByAddress request = do
  from      <- geocodeAddress "origin" request.origin
  to        <- geocodeAddress "destination" request.destination
  let bbox   = BBox.fromCoords from to bboxPaddingDegrees
      area   = BBox.approxAreaKm2 bbox
  when (area > maxBBoxAreaKm2) $ throwError (AreaTooLarge area maxBBoxAreaKm2)
  response  <- fetchRoadData bbox
  when (null response.ways) $ throwError NoRoadsInArea
  (net, _)  <- failWith NetworkBuildFailed (buildNetwork request.buildOptions response)
  startNode <- failWith (SnapFailed "origin") (nearestNode net from)
  goalNode  <- failWith (SnapFailed "destination") (nearestNode net to)
  result    <- failWith RoutingFailed (runRouter request.algorithm net startNode goalNode)
  pure RouteOutcome { ... }
```

**Read what is not there.** No error checking between the steps. `AppM` carries
an `ExceptT`, so the first `throwError` abandons the rest of the block.

The Go equivalent is the same seven steps interleaved with **eight**
`if err != nil { return AddressRouteResult{}, fmt.Errorf(...) }` blocks — the
same control flow, with the failure path written out by hand at every join.

If you have written C#: this reads like `await`-ing seven calls inside a `try`,
except the failure type is in the signature rather than in documentation.

## The steps, and why each guard exists

**1–2. Geocode both addresses.** Two Nominatim calls. The address is threaded
into the error so the message can say *which* one failed — Go's
`"geocode origin:"` prefix.

**3. Build a padded box.** `0.01°` ≈ 1 km. Without it, a geocode that lands
200 m from the nearest mapped road can produce a box containing no usable
network. See `src/Geo/BBox.README.md`.

**4. Reject an oversized box.** 500 km² is about a 22 km square. A
Melbourne→Geelong request spans roughly 1,800 km², and that Overpass response
can exceed 100 MB and take the process out of memory. Rejecting from four
multiplications is far cheaper than surviving the response.

**5. Fetch, or hit the cache.** See `fetchRoadData` below.

**6. Reject an empty road network.** Overpass answering with no ways is not an
error from its point of view, but there is nothing to route on — and
"no path found" would send the user hunting for a routing bug that does not
exist. This is a distinct error for a distinct cause.

**7. Build the graph, snap both endpoints, run the search.** The search is the
only genuinely *pure* step in the whole pipeline, and the only one that is about
routing rather than plumbing. Everything else is I/O and validation.

**8. Enrich.** Node IDs become `Node` values with coordinates, so the HTTP layer
can draw a polyline without a second lookup.

## `fetchRoadData`

```haskell
cached <- liftIO (lookupCache env.networkCache bbox)
case cached of
  Just response -> pure response
  Nothing -> do
    response <- attempt RoadDataUnavailable (fetchFromAPI ...)
    liftIO (insertCache env.networkCache bbox response)
    pure response
```

The cache is shared across all requests via `Env`, so a Dijkstra run and an A*
run over the same addresses share one Overpass fetch. There is a test asserting
the cache holds exactly one entry after two requests.

## `resolveNodes` and a small improvement over Go

```haskell
resolveNodes network = mapMaybe (`Graph.lookupNode` network)
```

`mapMaybe` silently drops IDs the network does not contain. That cannot happen —
every ID came out of a search over this very network — but writing it this way
means a future bug produces a **slightly short polyline** rather than a crash.

Go writes `network.Nodes[nodeID]`, which for a missing ID inserts a zero-valued
node at coordinate (0, 0) — drawing a line from Melbourne to the Gulf of Guinea.
Neither is *correct*, but one is much easier to diagnose.

## `RouteRequest` has no test-only fields

Compare Go's `AddressRouteRequest`, which also carries `GeocoderBaseURL`,
`DestGeocoderBaseURL` and `OverpassBaseURL` — three fields production always
leaves empty and only tests ever set. Those now live in `App.Env.Endpoints`, so
this type describes the *request* and nothing else. See
`src/App/Env.README.md`.

`algorithm` is an `Algorithm`, not a `Text`: parsing happens once at the HTTP
boundary, so by the time a request reaches this module, "invalid algorithm name"
is not a thing that can still go wrong. Pushing parsing to the edge and carrying
parsed values inward is the general habit — "parse, don't validate".

## `RouteOutcome`

`pathNodes` and `visitedNodes` carry whole `Node` values rather than bare IDs,
so the HTTP layer can serialise coordinates without a second lookup — same
reason as Go's `AddressRouteResult`.

`originCoord` and `destinationCoord` are the **geocoded** points, not the
snapped nodes. The frontend draws both: a pin where the user asked for, and a
polyline starting wherever the road network actually begins. The gap between
them is usually a driveway; occasionally it is informative.

## `loadNetworkFromFile` is plain `IO`

```haskell
loadNetworkFromFile :: FilePath -> BuildOptions -> IO (Either AppError Network)
```

Not `AppM`. It needs no environment, and **saying so in the type** means the CLI
path in `app/Main.hs` can call it without constructing one. A function that does
not need a dependency should not ask for it — and in Haskell that is visible
rather than a matter of discipline.
