// map.ts — owns the Leaflet map instance and all layer groups.
// No other module imports from Leaflet directly; all map operations go through
// this class so the Leaflet dependency is isolated to one file.

import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Coord, RouteResponse, MapStyle } from './types';
import { TILE_LAYERS, DEFAULT_MAP_STYLE } from './config';

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
    this.map = L.map(containerId).setView([-37.82, 144.97], 13);

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

  // addVisitedTendril draws a thin line from `from` to `to` on the visited
  // layer and marks the tip with a small dot. Together these produce the
  // branching vein-like growth seen during the traversal animation.
  addVisitedTendril(from: Coord, to: Coord, colour: string): void {
    L.polyline([[from.lat, from.lon], [to.lat, to.lon]], {
      color:   colour,
      weight:  1.5,
      opacity: 0.45,
    }).addTo(this.visitedGroup);
    L.circleMarker([to.lat, to.lon], {
      radius:      2,
      color:       'transparent',
      fillColor:   colour,
      fillOpacity: 0.75,
    }).addTo(this.visitedGroup);
  }

  // clearVisitedLayer removes all explored-node circles from the map.
  clearVisitedLayer(): void {
    this.visitedGroup.clearLayers();
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

  // showVisitedNodes re-renders the traversal tendril network from a saved
  // coordinate list. Each node is connected to its nearest already-placed
  // neighbour (within a sliding window) to reproduce the organic branching
  // that was drawn during the live animation.
  showVisitedNodes(coords: Coord[], colour: string): void {
    this.visitedGroup.clearLayers();
    if (coords.length === 0) return;

    const placed: Coord[] = [];
    for (const coord of coords) {
      const nearest = nearestInWindow(coord, placed);
      if (nearest === null) {
        this.addVisitedSeed(coord, colour);
      } else {
        this.addVisitedTendril(nearest, coord, colour);
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
