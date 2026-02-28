// animation.ts — two-phase route animation: explored-node dots then route polyline.
// All timer handles and pending route state are encapsulated in AnimationController
// so no module-level variables pollute the global scope.

import type { MapController } from './map';
import type { RouteResponse, AnimationSpeed, Coord } from './types';
import { SPEED_CONFIG, ALGORITHM_COLOUR, PATH_ANIMATION_INTERVAL_MS } from './config';

// AnimationCallbacks connect the animation lifecycle to the caller (main.ts).
// onProgress is called with a status message at each interval tick.
// onComplete is called once the path is fully drawn and the route is ready.
export interface AnimationCallbacks {
  onProgress: (message: string) => void;
  onComplete:  (route: RouteResponse, originAddress: string, destinationAddress: string) => void;
}

export class AnimationController {
  private traversalHandle: ReturnType<typeof setInterval> | null = null;
  private pathHandle:      ReturnType<typeof setInterval> | null = null;

  // pendingRoute holds the full API response while either animation phase is
  // running so skip() can finalise the route without re-fetching.
  private pendingRoute: {
    data:            RouteResponse;
    originAddress:   string;
    destAddress:     string;
  } | null = null;

  constructor(
    private readonly mapCtrl:    MapController,
    private readonly callbacks:  AnimationCallbacks,
  ) {}

  // start kicks off phase 1 (traversal dots) then phase 2 (polyline drawing).
  start(
    data:          RouteResponse,
    originAddress: string,
    destAddress:   string,
    speed:         AnimationSpeed,
  ): void {
    this.pendingRoute = { data, originAddress, destAddress };

    const visited   = data.visited_nodes;
    const colour    = ALGORITHM_COLOUR[data.algorithm as keyof typeof ALGORITHM_COLOUR]
                      ?? '#3b82f6';
    const pathCoords = data.path.map(n => ({ lat: n.lat, lon: n.lon }));
    const allCoords: Coord[] = [...visited, ...pathCoords];

    this.mapCtrl.fitToBounds(allCoords);

    if (visited.length === 0) {
      this.startPathPhase(data, originAddress, destAddress);
      return;
    }

    this.startTraversalPhase(visited, colour, speed, () => {
      this.mapCtrl.clearVisitedLayer();
      this.startPathPhase(data, originAddress, destAddress);
    });
  }

  // skip cancels any running animation and immediately draws the complete route.
  skip(): void {
    if (this.pendingRoute === null) return;
    const { data, originAddress, destAddress } = this.pendingRoute;

    this.cancelTimers();
    this.mapCtrl.clearVisitedLayer();
    this.mapCtrl.drawCompletePolyline(data.path.map(n => ({ lat: n.lat, lon: n.lon })));
    this.finalise(data, originAddress, destAddress);
  }

  // cancel stops all animations without finalising. Used when a new route
  // request arrives before the previous one has finished.
  cancel(): void {
    this.cancelTimers();
    this.pendingRoute = null;
  }

  isActive(): boolean {
    return this.pendingRoute !== null;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  private startTraversalPhase(
    visited:    Coord[],
    colour:     string,
    speed:      AnimationSpeed,
    onDone:     () => void,
  ): void {
    const { batchSize, intervalMs } = SPEED_CONFIG[speed] ?? SPEED_CONFIG.medium;
    const total = visited.length;
    let nextIndex = 0;

    this.callbacks.onProgress(
      'Exploring\u2026 (0\u00a0/\u00a0' + total.toLocaleString() + ' nodes settled)'
    );

    this.traversalHandle = setInterval(() => {
      const end = Math.min(nextIndex + batchSize, total);
      for (let i = nextIndex; i < end; i++) {
        const node = visited[i];
        if (node !== undefined) this.mapCtrl.addVisitedMarker(node, colour);
      }
      nextIndex = end;

      this.callbacks.onProgress(
        'Exploring\u2026 (' + nextIndex.toLocaleString() +
        '\u00a0/\u00a0' + total.toLocaleString() + ' nodes settled)'
      );

      if (nextIndex >= total) {
        clearInterval(this.traversalHandle!);
        this.traversalHandle = null;
        onDone();
      }
    }, intervalMs);
  }

  private startPathPhase(
    data:          RouteResponse,
    originAddress: string,
    destAddress:   string,
  ): void {
    this.mapCtrl.startEmptyPolyline();
    this.callbacks.onProgress('Drawing route\u2026');

    const pathCoords = data.path.map(n => ({ lat: n.lat, lon: n.lon }));
    let i = 0;

    this.pathHandle = setInterval(() => {
      if (i >= pathCoords.length) {
        clearInterval(this.pathHandle!);
        this.pathHandle = null;
        this.finalise(data, originAddress, destAddress);
        return;
      }
      const coord = pathCoords[i];
      if (coord !== undefined) this.mapCtrl.extendPolyline(coord);
      i++;
    }, PATH_ANIMATION_INTERVAL_MS);
  }

  private finalise(
    data:          RouteResponse,
    originAddress: string,
    destAddress:   string,
  ): void {
    this.pendingRoute = null;
    this.callbacks.onComplete(data, originAddress, destAddress);
  }

  private cancelTimers(): void {
    if (this.traversalHandle !== null) {
      clearInterval(this.traversalHandle);
      this.traversalHandle = null;
    }
    if (this.pathHandle !== null) {
      clearInterval(this.pathHandle);
      this.pathHandle = null;
    }
  }
}
