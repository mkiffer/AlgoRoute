// map.ts — owns the Leaflet map instance and all layer groups.
// No other module imports from Leaflet directly; all map operations go through
// this class so the Leaflet dependency is isolated to one file.

import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { Coord, RouteResponse } from './types';

export class MapController {
  private readonly map: L.Map;
  private readonly markerGroup:  L.LayerGroup;
  private readonly visitedGroup: L.LayerGroup;
  private routePolyline: L.Polyline | null = null;

  constructor(containerId: string) {
    this.map = L.map(containerId).setView([-37.82, 144.97], 13);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
    }).addTo(this.map);

    this.markerGroup  = L.layerGroup().addTo(this.map);
    this.visitedGroup = L.layerGroup().addTo(this.map);
  }

  // fitToBounds adjusts the map viewport to show all given coordinates with
  // a small padding so the full traversal or route is visible before animation.
  fitToBounds(coords: Coord[]): void {
    if (coords.length === 0) return;
    const latLngs = coords.map(c => [c.lat, c.lon] as [number, number]);
    this.map.fitBounds(L.latLngBounds(latLngs), { padding: [30, 30] });
  }

  // addVisitedMarker places a semi-transparent circle on the visited-nodes
  // layer. Called once per settled node during the traversal animation.
  addVisitedMarker(coord: Coord, colour: string): void {
    L.circleMarker([coord.lat, coord.lon], {
      radius:      3,
      color:       'transparent',
      fillColor:   colour,
      fillOpacity: 0.35,
    }).addTo(this.visitedGroup);
  }

  // clearVisitedLayer removes all explored-node circles from the map.
  clearVisitedLayer(): void {
    this.visitedGroup.clearLayers();
  }

  // startEmptyPolyline creates a new empty polyline on the map. Call
  // extendPolyline() to grow it one coordinate at a time.
  startEmptyPolyline(): void {
    this.removePolyline();
    this.routePolyline = L.polyline([], { color: '#2563eb', weight: 4 }).addTo(this.map);
  }

  // extendPolyline appends one coordinate to the route polyline, extending it
  // incrementally during the path animation phase.
  extendPolyline(coord: Coord): void {
    this.routePolyline?.addLatLng([coord.lat, coord.lon]);
  }

  // drawCompletePolyline replaces any existing polyline with the full route,
  // used by the skip-animation path.
  drawCompletePolyline(coords: Coord[]): void {
    this.removePolyline();
    const latLngs = coords.map(c => [c.lat, c.lon] as [number, number]);
    this.routePolyline = L.polyline(latLngs, { color: '#2563eb', weight: 4 }).addTo(this.map);
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

  // showVisitedNodes re-renders explored-node circles from a saved list. Used
  // by the toggle button to restore the dots after animation has cleared them.
  showVisitedNodes(coords: Coord[], colour: string): void {
    this.visitedGroup.clearLayers();
    for (const coord of coords) {
      this.addVisitedMarker(coord, colour);
    }
  }

  // clearAll removes all route overlays (polyline, markers, visited dots) from
  // the map. Called before starting a new route request.
  clearAll(): void {
    this.removePolyline();
    this.markerGroup.clearLayers();
    this.visitedGroup.clearLayers();
  }

  private removePolyline(): void {
    if (this.routePolyline !== null) {
      this.map.removeLayer(this.routePolyline);
      this.routePolyline = null;
    }
  }
}
