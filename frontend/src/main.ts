// main.ts — entry point for the AlgoRoute frontend.
// Initialises all subsystems, wires DOM events, and owns the small amount of
// page-level state that does not belong to any individual module:
//   • visitedNodesVisible  — whether the explored-node overlay is shown
//   • lastRoute            — the most-recent RouteResponse (for the toggle)
//   • lastAlgorithmColour  — the colour of the most-recent traversal

import './styles.css';
import { MapController }       from './map';
import { AnimationController } from './animation';
import { setupAutocomplete }   from './autocomplete';
import { fetchRoute }          from './api';
import * as ui                 from './ui';
import { ALGORITHM_COLOUR }    from './config';
import type { RouteResponse, AnimationSpeed } from './types';

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

// ---------------------------------------------------------------------------
// Page-level state
// ---------------------------------------------------------------------------

let lastRoute:            RouteResponse | null = null;
let lastAlgorithmColour   = '#3b82f6';
let visitedNodesVisible   = false;

// ---------------------------------------------------------------------------
// Route request
// ---------------------------------------------------------------------------

async function findRoute(): Promise<void> {
  const originAddress      = (document.getElementById('origin-input')      as HTMLInputElement).value.trim();
  const destinationAddress = (document.getElementById('destination-input') as HTMLInputElement).value.trim();
  const algorithm          = (document.getElementById('algorithm-select')  as HTMLSelectElement).value;
  const button             = document.getElementById('find-route-button') as HTMLButtonElement;

  if (!originAddress || !destinationAddress) {
    ui.showStatus('Please enter both an origin and a destination.', /*isError=*/true);
    return;
  }

  // Cancel any running animation from a previous request before starting a
  // new one so the map is always in a clean state.
  animCtrl.cancel();
  mapCtrl.clearAll();
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
      ALGORITHM_COLOUR[data.algorithm as keyof typeof ALGORITHM_COLOUR] ?? '#3b82f6',
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
  lastAlgorithmColour = ALGORITHM_COLOUR[route.algorithm as keyof typeof ALGORITHM_COLOUR] ?? '#3b82f6';
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
    mapCtrl.showVisitedNodes(lastRoute.visited_nodes, lastAlgorithmColour);
    visitedNodesVisible = true;
  }

  ui.updateToggleVisitedButtonLabel(visitedNodesVisible);
}
