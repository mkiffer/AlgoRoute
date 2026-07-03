// map.ts — owns the Leaflet map instance and all layer groups.
// No other module imports from Leaflet directly; all map operations go through
// this class so the Leaflet dependency is isolated to one file.

import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Coord, RouteResponse, MapStyle, Algorithm } from './types';
import { TILE_LAYERS, DEFAULT_MAP_STYLE, ALGORITHM_STYLE, RETREAT_DURATION_MS, RETREAT_JITTER_MS } from './config';

// RetreatOptions controls the algorithm-specific retreat strategy used by
// startRetreat. Dijkstra collapses inward from the origin; A* collapses
// from the sides of the origin→destination corridor.
export interface RetreatOptions {
  algorithm:  Algorithm;
  origin:     Coord;
  dest:       Coord;
  pathCoords: Coord[];
}

export class MapController {
  private readonly map: L.Map;
  private readonly markerGroup:       L.LayerGroup;
  private readonly visitedGroup:      L.LayerGroup;
  private readonly clickMarkerGroup:  L.LayerGroup;
  private routePolyline: L.Polyline | null = null;
  private tileLayer: L.TileLayer;

  // radiusCircle is the semi-transparent circle shown after the first click
  // to indicate the maximum selectable distance for the destination.
  private radiusCircle: L.Circle | null = null;

  // mapClickHandler holds the currently registered click listener so it can
  // be detached before a new one is attached (prevents duplicate listeners).
  private mapClickHandler: ((e: L.LeafletMouseEvent) => void) | null = null;

  constructor(containerId: string) {
    this.map = L.map(containerId, { zoomControl: false }).setView([-37.82, 144.97], 13);
    L.control.zoom({ position: 'topright' }).addTo(this.map);

    const defaultConfig = TILE_LAYERS[DEFAULT_MAP_STYLE];
    this.tileLayer = L.tileLayer(defaultConfig.url, {
      attribution: defaultConfig.attribution,
      detectRetina: true,
    }).addTo(this.map);

    this.markerGroup       = L.layerGroup().addTo(this.map);
    this.visitedGroup      = L.layerGroup().addTo(this.map);
    this.clickMarkerGroup  = L.layerGroup().addTo(this.map);
  }

  // setTileLayer swaps the background tile layer to the given style. The old
  // layer is removed from the map before the new one is added so the two never
  // overlap during the transition.
  setTileLayer(style: MapStyle): void {
    this.map.removeLayer(this.tileLayer);
    const config = TILE_LAYERS[style];
    this.tileLayer = L.tileLayer(config.url, {
      attribution: config.attribution,
      detectRetina: true,
    }).addTo(this.map);
  }

  // fitToBounds adjusts the map viewport to show all given coordinates with
  // a small padding so the full traversal or route is visible before animation.
  fitToBounds(coords: Coord[]): void {
    if (coords.length === 0) return;
    const latLngs = coords.map(c => [c.lat, c.lon] as [number, number]);
    this.map.fitBounds(L.latLngBounds(latLngs), { padding: [30, 30] });
  }

  // addVisitedSeed places the initial node dot with no connecting line.
  // Called for the very first explored node before any tendril can be drawn.
  addVisitedSeed(coord: Coord, colour: string): void {
    L.circleMarker([coord.lat, coord.lon], {
      radius:      3,
      color:       'transparent',
      fillColor:   colour,
      fillOpacity: 0.8,
    }).addTo(this.visitedGroup);
  }

  // addVisitedDot places a small standalone dot for Dijkstra's ripple-style
  // traversal. No connecting line — the natural distance-ordering of Dijkstra
  // settlement makes the dots form expanding concentric rings on their own.
  addVisitedDot(coord: Coord, colour: string): void {
    L.circleMarker([coord.lat, coord.lon], {
      radius:      2,
      color:       'transparent',
      fillColor:   colour,
      fillOpacity: 0.7,
    }).addTo(this.visitedGroup);
  }

  // addVisitedTendril draws a thin line from `from` to `to` on the visited
  // layer and marks the tip with a small dot. Together these produce the
  // branching vein-like growth seen during the traversal animation.
  // When glowIntensity (0–1) is provided (A* mode), opacity and dot size
  // scale with proximity to the destination — bright near the goal, dim far away.
  addVisitedTendril(from: Coord, to: Coord, colour: string, glowIntensity?: number): void {
    const lineOpacity = glowIntensity !== undefined ? 0.15 + 0.45 * glowIntensity : 0.45;
    const dotOpacity  = glowIntensity !== undefined ? 0.3  + 0.7  * glowIntensity : 0.75;
    const dotRadius   = glowIntensity !== undefined ? 1 + 1.5 * glowIntensity     : 1;

    L.polyline([[from.lat, from.lon], [to.lat, to.lon]], {
      color:   colour,
      weight:  1.5,
      opacity: lineOpacity,
    }).addTo(this.visitedGroup);
    L.circleMarker([to.lat, to.lon], {
      radius:      dotRadius,
      color:       'transparent',
      fillColor:   colour,
      fillOpacity: dotOpacity,
    }).addTo(this.visitedGroup);
  }

  // clearVisitedLayer removes all explored-node circles from the map.
  clearVisitedLayer(): void {
    this.visitedGroup.clearLayers();
  }

  // startRetreat gradually removes explored-node layers using an algorithm-
  // specific distance metric so the retreat visually matches the exploration
  // pattern. Dijkstra collapses inward from the outer ring toward the origin;
  // A* collapses from the sides, briefly revealing its narrow search corridor.
  // Returns a cancel function that immediately clears all remaining layers.
  startRetreat(opts: RetreatOptions, onDone: () => void): () => void {
    const layers: L.Layer[] = [];
    this.visitedGroup.eachLayer(layer => layers.push(layer));

    if (layers.length === 0) {
      onDone();
      return () => {};
    }

    // Pre-compute distances so the max can be used for normalisation.
    const withDist = layers.map(layer => ({
      layer,
      dist: retreatDistance(layerCoord(layer), opts),
    }));
    const maxDist = withDist.reduce((m, { dist }) => Math.max(m, dist), 0);

    let remaining = layers.length;
    let cancelled = false;
    const handles: ReturnType<typeof setTimeout>[] = [];

    for (const { layer, dist } of withDist) {
      // progress=0 → far from path, fires early;
      // progress=1 → close to path, fires near RETREAT_DURATION_MS.
      const progress = maxDist > 0 ? 1 - dist / maxDist : Math.random();
      const jitter    = (Math.random() - 0.5) * 2 * RETREAT_JITTER_MS;
      const delay     = Math.max(0, progress * RETREAT_DURATION_MS + jitter);

      handles.push(setTimeout(() => {
        if (cancelled) return;
        this.visitedGroup.removeLayer(layer);
        remaining--;
        if (remaining === 0) onDone();
      }, delay));
    }

    return () => {
      cancelled = true;
      for (const h of handles) clearTimeout(h);
      this.visitedGroup.clearLayers();
    };
  }

  // startEmptyPolyline creates a new empty polyline on the map. Call
  // extendPolyline() to grow it one coordinate at a time.
  startEmptyPolyline(colour: string): void {
    this.removePolyline();
    this.routePolyline = L.polyline([], { color: colour, weight: 5, opacity: 0.9 }).addTo(this.map);
  }

  // extendPolyline appends one coordinate to the route polyline, extending it
  // incrementally during the path animation phase.
  extendPolyline(coord: Coord): void {
    this.routePolyline?.addLatLng([coord.lat, coord.lon]);
  }

  // drawCompletePolyline replaces any existing polyline with the full route,
  // used by the skip-animation path.
  drawCompletePolyline(coords: Coord[], colour: string): void {
    this.removePolyline();
    const latLngs = coords.map(c => [c.lat, c.lon] as [number, number]);
    this.routePolyline = L.polyline(latLngs, { color: colour, weight: 5, opacity: 0.9 }).addTo(this.map);
  }

  // placeMarkers adds origin and destination markers with address popups.
  placeMarkers(route: RouteResponse, originAddress: string, destinationAddress: string): void {
    this.markerGroup.clearLayers();
    L.marker([route.origin_coord.lat, route.origin_coord.lon])
      .bindPopup('<strong>Origin</strong><br>' + originAddress)
      .addTo(this.markerGroup);
    L.marker([route.destination_coord.lat, route.destination_coord.lon])
      .bindPopup('<strong>Destination</strong><br>' + destinationAddress)
      .addTo(this.markerGroup);
  }

  // showVisitedNodes re-renders the explored-node overlay from a saved
  // coordinate list, matching the algorithm-specific style used during live
  // animation. Dijkstra draws standalone dots; A* draws tendril connections
  // with heuristic glow toward the destination.
  showVisitedNodes(
    coords:    Coord[],
    colour:    string,
    algorithm: Algorithm,
    destCoord?: Coord,
  ): void {
    this.visitedGroup.clearLayers();
    if (coords.length === 0) return;

    if (ALGORITHM_STYLE[algorithm] === 'dots') {
      for (const coord of coords) {
        this.addVisitedDot(coord, colour);
      }
      return;
    }

    // Tendril-style algorithms (A*, Greedy): connected network with heuristic glow.
    const maxSqDist = destCoord
      ? coords.reduce((m, c) => Math.max(m, squaredDist(c, destCoord)), 0)
      : 0;
    const placed: Coord[] = [];
    for (const coord of coords) {
      const nearest = nearestInWindow(coord, placed);
      const glow = maxSqDist > 0 && destCoord
        ? 1 - squaredDist(coord, destCoord) / maxSqDist
        : undefined;
      if (nearest === null) {
        this.addVisitedSeed(coord, colour);
      } else {
        this.addVisitedTendril(nearest, coord, colour, glow);
      }
      placed.push(coord);
    }
  }

  // onMapClick attaches a click handler to the map. Any previously registered
  // handler is detached first so only one listener is active at a time.
  onMapClick(handler: (coord: Coord) => void): void {
    if (this.mapClickHandler !== null) {
      this.map.off('click', this.mapClickHandler);
    }
    this.mapClickHandler = (e: L.LeafletMouseEvent) => {
      handler({ lat: e.latlng.lat, lon: e.latlng.lng });
    };
    this.map.on('click', this.mapClickHandler);
  }

  // offMapClick detaches the stored click listener from the map.
  offMapClick(): void {
    if (this.mapClickHandler !== null) {
      this.map.off('click', this.mapClickHandler);
      this.mapClickHandler = null;
    }
  }

  // showRadiusCircle draws a semi-transparent circle centred on coord with the
  // given radius in metres. Any existing circle is removed first.
  showRadiusCircle(coord: Coord, radiusMeters: number): void {
    this.hideRadiusCircle();
    this.radiusCircle = L.circle([coord.lat, coord.lon], {
      radius:      radiusMeters,
      color:       '#3b82f6',
      fillColor:   '#3b82f6',
      fillOpacity: 0.08,
      weight:      1.5,
    }).addTo(this.map);
  }

  // hideRadiusCircle removes the radius circle from the map.
  hideRadiusCircle(): void {
    if (this.radiusCircle !== null) {
      this.radiusCircle.remove();
      this.radiusCircle = null;
    }
  }

  // placeClickMarker adds a draggable coloured pin to the clickMarkerGroup.
  // The onDragEnd callback receives the new coordinate after the user drops it.
  placeClickMarker(
    coord: Coord,
    type: 'origin' | 'destination',
    onDragEnd: (newCoord: Coord) => void,
  ): L.Marker {
    const colour = type === 'origin' ? '#16a34a' : '#dc2626';
    const icon = L.divIcon({
      className: '',
      html: `<div style="width:14px;height:14px;border-radius:50%;background:${colour};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.4)"></div>`,
      iconSize:   [14, 14],
      iconAnchor: [7, 7],
    });

    const marker = L.marker([coord.lat, coord.lon], { draggable: true, icon })
      .addTo(this.clickMarkerGroup)
      .on('dragend', (e: L.LeafletEvent) => {
        const latLng = (e as L.DragEndEvent).target.getLatLng();
        onDragEnd({ lat: latLng.lat, lon: latLng.lng });
      });

    return marker;
  }

  // clearClickMarkers removes all click-placed origin/destination pins.
  clearClickMarkers(): void {
    this.clickMarkerGroup.clearLayers();
  }

  // clearRouteOverlays removes the route polyline, address markers, and
  // visited-node dots. It intentionally leaves click markers and the radius
  // circle in place so they survive re-routes triggered by pin dragging.
  clearRouteOverlays(): void {
    this.removePolyline();
    this.markerGroup.clearLayers();
    this.visitedGroup.clearLayers();
  }

  // clearAll removes every overlay from the map, including click markers and
  // the radius circle. Call this for a full reset to the empty-map state.
  clearAll(): void {
    this.clearRouteOverlays();
    this.clearClickMarkers();
    this.hideRadiusCircle();
  }

  private removePolyline(): void {
    if (this.routePolyline !== null) {
      this.map.removeLayer(this.routePolyline);
      this.routePolyline = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Nearest-neighbour helpers for tendril drawing
// ---------------------------------------------------------------------------

// nearestInWindow returns the closest coord to `target` among the last 300
// entries of `placed`. Using a fixed-size trailing window keeps each search
// O(300) even for large exploration sets, and biases connections towards the
// recent frontier — exactly where organic branching occurs.
function nearestInWindow(target: Coord, placed: Coord[]): Coord | null {
  if (placed.length === 0) return null;
  const start = Math.max(0, placed.length - 300);
  let best = placed[start]!;
  let bestDist = squaredDist(target, best);
  for (let i = start + 1; i < placed.length; i++) {
    const d = squaredDist(target, placed[i]!);
    if (d < bestDist) { bestDist = d; best = placed[i]!; }
  }
  return best;
}

function squaredDist(a: Coord, b: Coord): number {
  return (a.lat - b.lat) ** 2 + (a.lon - b.lon) ** 2;
}

// ---------------------------------------------------------------------------
// Helpers for startRetreat distance sorting
// ---------------------------------------------------------------------------

// layerCoord extracts a representative coordinate from a Leaflet layer using
// duck typing so it works with both real Leaflet objects and test mocks.
// CircleMarker → its centre point; Polyline → midpoint of its coordinate array.
function layerCoord(layer: L.Layer): Coord | null {
  if ('getLatLng' in layer && typeof (layer as any).getLatLng === 'function') {
    const ll = (layer as L.CircleMarker).getLatLng();
    return { lat: ll.lat, lon: ll.lng };
  }
  if ('getLatLngs' in layer && typeof (layer as any).getLatLngs === 'function') {
    const lls = (layer as L.Polyline).getLatLngs() as L.LatLng[];
    if (lls.length > 0) {
      const mid = lls[Math.floor(lls.length / 2)]!;
      return { lat: mid.lat, lon: mid.lng };
    }
  }
  return null;
}

// retreatDistance selects the algorithm-appropriate distance metric for the
// retreat animation. Dijkstra uses distance from origin (concentric ring
// collapse); A* uses perpendicular distance from the O→D axis (corridor
// collapse from the sides).
function retreatDistance(coord: Coord | null, opts: RetreatOptions): number {
  if (coord === null) return Infinity;
  if (ALGORITHM_STYLE[opts.algorithm] === 'dots') {
    // Dot-style algorithms (Dijkstra, Bidirectional): collapse inward from the
    // outer ring toward the origin.
    return squaredDist(coord, opts.origin);
  }
  // Tendril-style algorithms (A*, Greedy): collapse from the sides of the
  // origin→destination corridor.
  return sqDistToSegment(coord, opts.origin, opts.dest);
}

// sqDistToSegment returns the squared distance from point p to the closest
// point on the line segment a→b. Used by the A* retreat to measure how far
// off the search corridor each explored node sits.
function sqDistToSegment(p: Coord, a: Coord, b: Coord): number {
  const dx = b.lat - a.lat;
  const dy = b.lon - a.lon;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) return squaredDist(p, a);
  const t = Math.max(0, Math.min(1, ((p.lat - a.lat) * dx + (p.lon - a.lon) * dy) / lenSq));
  const proj: Coord = { lat: a.lat + t * dx, lon: a.lon + t * dy };
  return squaredDist(p, proj);
}
