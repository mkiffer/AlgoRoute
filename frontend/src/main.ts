// main.ts — entry point for the AlgoRoute frontend.
// Initialises all subsystems, wires DOM events, and owns the small amount of
// page-level state that does not belong to any individual module:
//   • visitedNodesVisible  — whether the explored-node overlay is shown
//   • lastRoute            — the most-recent RouteResponse (for the toggle)
//   • lastAlgorithmColour  — the colour of the most-recent traversal
//   • clickPhase           — tracks where in the two-click placement flow we are
//   • originClickCoord     — the coordinate placed by the first map click
//   • isClickMode          — true whenever at least one pin has been placed by clicking

import './styles.css';
import { MapController }       from './map';
import { AnimationController } from './animation';
import { setupAutocomplete }   from './autocomplete';
import { fetchRoute, fetchReverseGeocode } from './api';
import * as ui                 from './ui';
import { ALGORITHM_COLOUR, MAX_CLICK_RADIUS_METERS } from './config';
import { haversineMeters }     from './geo';
import type { RouteResponse, AnimationSpeed, MapStyle, Coord } from './types';

// ---------------------------------------------------------------------------
// Subsystem initialisation
// ---------------------------------------------------------------------------

const mapCtrl = new MapController('map');

const animCtrl = new AnimationController(mapCtrl, {
  onProgress: (msg) => ui.showStatus(msg),
  onComplete:  finalizeRoute,
});

setupAutocomplete(
  document.getElementById('origin-input') as HTMLInputElement,
  document.getElementById('origin-suggestions') as HTMLUListElement,
);

setupAutocomplete(
  document.getElementById('destination-input') as HTMLInputElement,
  document.getElementById('destination-suggestions') as HTMLUListElement,
);

// ---------------------------------------------------------------------------
// Event wiring
// ---------------------------------------------------------------------------

document.getElementById('find-route-button')!.addEventListener('click', findRoute);
document.getElementById('skip-button')!.addEventListener('click', () => animCtrl.skip());
document.getElementById('toggle-visited-button')!.addEventListener('click', toggleVisitedNodes);
document.getElementById('map-style-select')!.addEventListener('change', (e) => {
  mapCtrl.setTileLayer((e.target as HTMLSelectElement).value as MapStyle);
});

// When the user types in an address field while click mode is active, clear
// the click pins and radius circle so typed and clicked modes don't conflict.
const originInput      = document.getElementById('origin-input')      as HTMLInputElement;
const destinationInput = document.getElementById('destination-input') as HTMLInputElement;

originInput.addEventListener('input', handleAddressTyped);
destinationInput.addEventListener('input', handleAddressTyped);

// Attach the map click handler once, immediately after the map is created.
mapCtrl.onMapClick(handleMapClick);

// ---------------------------------------------------------------------------
// Page-level state
// ---------------------------------------------------------------------------

let lastRoute:            RouteResponse | null = null;
let lastAlgorithmColour   = '#f59e0b';
let visitedNodesVisible   = false;

// Click-to-place state machine.
// Phase 'idle':                waiting for the first click (origin placement).
// Phase 'awaiting-destination': origin placed, waiting for the second click.
type ClickPhase = 'idle' | 'awaiting-destination';
let clickPhase:        ClickPhase = 'idle';
let originClickCoord:  Coord | null = null;
let isClickMode        = false;

// ---------------------------------------------------------------------------
// Click-mode handlers
// ---------------------------------------------------------------------------

async function handleMapClick(coord: Coord): Promise<void> {
  // If an animation is running, cancel it and clean up before processing
  // the click so timers cannot continue drawing onto cleared layers.
  if (animCtrl.isActive()) {
    animCtrl.cancel();
    mapCtrl.clearRouteOverlays();
    ui.showSkipButton(false);
    ui.showToggleVisitedButton(false, false);
  }

  if (clickPhase === 'idle' && isClickMode) {
    // Third click — full reset and start over with the new click as origin.
    resetClickMode();
  }

  if (clickPhase === 'idle') {
    // First click — place origin pin and show the radius circle.
    isClickMode        = true;
    originClickCoord   = coord;
    clickPhase         = 'awaiting-destination';

    mapCtrl.placeClickMarker(coord, 'origin', handleOriginDragEnd);
    mapCtrl.showRadiusCircle(coord, MAX_CLICK_RADIUS_METERS);

    const address = await fetchReverseGeocode(coord.lat, coord.lon);
    originInput.value  = address || `${coord.lat.toFixed(5)}, ${coord.lon.toFixed(5)}`;
    destinationInput.value = '';
    ui.showStatus('Origin set — click within the circle to set your destination.');
    return;
  }

  if (clickPhase === 'awaiting-destination') {
    // Second click — validate distance, then place destination pin.
    if (originClickCoord !== null &&
        haversineMeters(originClickCoord, coord) > MAX_CLICK_RADIUS_METERS) {
      ui.showStatus('Destination too far — select within the highlighted area', /*isError=*/true);
      return;
    }

    mapCtrl.placeClickMarker(coord, 'destination', handleDestinationDragEnd);
    mapCtrl.hideRadiusCircle();
    clickPhase = 'idle';

    const address = await fetchReverseGeocode(coord.lat, coord.lon);
    destinationInput.value = address || `${coord.lat.toFixed(5)}, ${coord.lon.toFixed(5)}`;

    await findRoute();
  }
}

async function handleOriginDragEnd(newCoord: Coord): Promise<void> {
  originClickCoord   = newCoord;
  mapCtrl.showRadiusCircle(newCoord, MAX_CLICK_RADIUS_METERS);

  const address = await fetchReverseGeocode(newCoord.lat, newCoord.lon);
  originInput.value  = address || `${newCoord.lat.toFixed(5)}, ${newCoord.lon.toFixed(5)}`;

  if (destinationInput.value.trim() !== '') {
    await findRoute();
  }
}

async function handleDestinationDragEnd(newCoord: Coord): Promise<void> {
  if (originClickCoord !== null &&
      haversineMeters(originClickCoord, newCoord) > MAX_CLICK_RADIUS_METERS) {
    ui.showStatus('Destination too far — select within the highlighted area', /*isError=*/true);
    return;
  }

  const address = await fetchReverseGeocode(newCoord.lat, newCoord.lon);
  destinationInput.value = address || `${newCoord.lat.toFixed(5)}, ${newCoord.lon.toFixed(5)}`;

  await findRoute();
}

// handleAddressTyped clears click-mode pins when the user starts typing so the
// two input methods (click and type) do not conflict.
function handleAddressTyped(): void {
  if (!isClickMode) return;
  mapCtrl.clearClickMarkers();
  mapCtrl.hideRadiusCircle();
  clickPhase       = 'idle';
  originClickCoord = null;
  isClickMode      = false;
}

// resetClickMode clears all click state and overlays for a full fresh start.
function resetClickMode(): void {
  mapCtrl.clearAll();
  originInput.value      = '';
  destinationInput.value = '';
  clickPhase       = 'idle';
  originClickCoord = null;
  isClickMode      = false;
}

// ---------------------------------------------------------------------------
// Route request
// ---------------------------------------------------------------------------

async function findRoute(): Promise<void> {
  const originAddress      = originInput.value.trim();
  const destinationAddress = destinationInput.value.trim();
  const algorithm          = (document.getElementById('algorithm-select')  as HTMLSelectElement).value;
  const button             = document.getElementById('find-route-button') as HTMLButtonElement;

  if (!originAddress || !destinationAddress) {
    ui.showStatus('Please enter both an origin and a destination.', /*isError=*/true);
    return;
  }

  // Cancel any running animation from a previous request before starting a
  // new one so the map is always in a clean state.
  animCtrl.cancel();
  // Preserve click markers and radius circle through re-routes so pin positions
  // are not lost when the user triggers a new route by dragging or re-clicking.
  mapCtrl.clearRouteOverlays();
  lastRoute           = null;
  visitedNodesVisible = false;
  ui.showSkipButton(false);
  ui.showToggleVisitedButton(false, false);

  button.disabled = true;
  ui.showStatus('Geocoding addresses and fetching road network\u2026');

  try {
    const data = await fetchRoute({
      origin:      originAddress,
      destination: destinationAddress,
      algorithm:   algorithm as 'dijkstra' | 'astar',
    });

    const speed = (document.getElementById('speed-select') as HTMLSelectElement).value as AnimationSpeed;
    ui.showSkipButton(true);
    ui.updateLegend(
      data.algorithm,
      ALGORITHM_COLOUR[data.algorithm as keyof typeof ALGORITHM_COLOUR] ?? '#f59e0b',
    );
    animCtrl.start(data, originAddress, destinationAddress, speed);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    ui.showStatus('Error: ' + message, /*isError=*/true);
  } finally {
    button.disabled = false;
  }
}

// ---------------------------------------------------------------------------
// Route finalisation (called by AnimationController on completion)
// ---------------------------------------------------------------------------

function finalizeRoute(
  route:            RouteResponse,
  originAddress:    string,
  destAddress:      string,
): void {
  lastRoute           = route;
  lastAlgorithmColour = ALGORITHM_COLOUR[route.algorithm as keyof typeof ALGORITHM_COLOUR] ?? '#f59e0b';
  visitedNodesVisible = false;

  mapCtrl.placeMarkers(route, originAddress, destAddress);

  const distanceKm    = (route.distance_meters / 1000).toFixed(2);
  const exploredCount = route.visited_nodes.length;
  ui.showStatus(
    'Route found \u2014 ' + route.algorithm + ' \u2014 ' +
    distanceKm + '\u00a0km \u2014 ' + route.path.length + ' nodes' +
    ' (' + exploredCount.toLocaleString() + ' explored)'
  );

  ui.showSkipButton(false);
  ui.showToggleVisitedButton(true, visitedNodesVisible);
}

// ---------------------------------------------------------------------------
// Explored-node toggle
// ---------------------------------------------------------------------------

// toggleVisitedNodes shows or hides the explored-node circles. The circles are
// re-rendered from lastRoute on each toggle-on so no live Leaflet layers are
// held in memory when the overlay is hidden.
function toggleVisitedNodes(): void {
  if (lastRoute === null) return;

  if (visitedNodesVisible) {
    mapCtrl.clearVisitedLayer();
    visitedNodesVisible = false;
  } else {
    mapCtrl.showVisitedNodes(
      lastRoute.visited_nodes,
      lastAlgorithmColour,
      lastRoute.algorithm as import('./types').Algorithm,
      lastRoute.destination_coord,
    );
    visitedNodesVisible = true;
  }

  ui.updateToggleVisitedButtonLabel(visitedNodesVisible);
}
