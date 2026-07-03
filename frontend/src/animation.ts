// animation.ts — two-phase route animation: explored-node dots then route polyline.
// All timer handles and pending route state are encapsulated in AnimationController
// so no module-level variables pollute the global scope.

import type { MapController } from './map';
import type { RouteResponse, AnimationSpeed, Coord, Algorithm } from './types';
import { SPEED_CONFIG, ALGORITHM_COLOUR, ALGORITHM_STYLE, PATH_ANIMATION_INTERVAL_MS, RETREAT_DURATION_MS } from './config';

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
  private retreatCancel:   (() => void) | null = null;

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

    const algorithm = (data.algorithm as Algorithm) ?? 'dijkstra';
    const originCoord = data.origin_coord;
    const destCoord   = data.destination_coord;

    if (visited.length === 0) {
      this.startPathPhase(data, colour, originAddress, destAddress);
      return;
    }

    this.startTraversalPhase(visited, colour, speed, algorithm, destCoord, () => {
      // Retreat and route drawing start together. The retreat strategy
      // matches the algorithm: Dijkstra collapses inward from the outer
      // ring; A* collapses from the corridor sides.
      this.retreatCancel = this.mapCtrl.startRetreat({
        algorithm,
        origin:     originCoord,
        dest:       destCoord,
        pathCoords,
      }, () => {
        this.retreatCancel = null;
      });
      // Pass RETREAT_DURATION_MS so the polyline finishes drawing at the
      // same moment the last nodes finish retreating.
      this.startPathPhase(data, colour, originAddress, destAddress, RETREAT_DURATION_MS);
    });
  }

  // skip cancels any running animation and immediately draws the complete route.
  skip(): void {
    if (this.pendingRoute === null) return;
    const { data, originAddress, destAddress } = this.pendingRoute;
    const colour = ALGORITHM_COLOUR[data.algorithm as keyof typeof ALGORITHM_COLOUR] ?? '#f59e0b';

    this.cancelTimers();
    this.mapCtrl.clearVisitedLayer();
    this.mapCtrl.drawCompletePolyline(data.path.map(n => ({ lat: n.lat, lon: n.lon })), colour);
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
    algorithm:  Algorithm,
    destCoord:  Coord,
    onDone:     () => void,
  ): void {
    const { batchSize, intervalMs } = SPEED_CONFIG[speed] ?? SPEED_CONFIG.medium;
    const total = visited.length;
    let nextIndex = 0;

    // Tendril glow: pre-compute maximum squared distance to destination so each
    // node's intensity can be normalised to 0–1. Applies to all tendril-style
    // algorithms (A*, Greedy) where the heuristic guides exploration directionally.
    const isTendrils = ALGORITHM_STYLE[algorithm] === 'tendrils';
    const maxSqDistToDest = isTendrils
      ? visited.reduce((m, v) => Math.max(m, squaredDist(v, destCoord)), 0)
      : 0;

    // placedCoords accumulates all nodes drawn so far (A* only). Each new
    // node connects to its nearest neighbour within the last 300 placed nodes,
    // producing the branching tendril growth characteristic of A*'s directed
    // exploration.
    const placedCoords: Coord[] = [];

    this.callbacks.onProgress(
      'Exploring\u2026 (0\u00a0/\u00a0' + total.toLocaleString() + ' nodes settled)'
    );

    this.traversalHandle = setInterval(() => {
      const end = Math.min(nextIndex + batchSize, total);
      for (let i = nextIndex; i < end; i++) {
        const node = visited[i];
        if (node === undefined) continue;

        if (ALGORITHM_STYLE[algorithm] === 'dots') {
          // Dot-style algorithms (Dijkstra, Bidirectional Dijkstra): standalone
          // dots that form expanding concentric rings.
          this.mapCtrl.addVisitedDot(node, colour);
        } else {
          // Tendril-style algorithms (A*, Greedy): directed tendrils with
          // heuristic glow scaling opacity by proximity to the destination.
          const glow = maxSqDistToDest > 0
            ? 1 - squaredDist(node, destCoord) / maxSqDistToDest
            : undefined;
          if (placedCoords.length === 0) {
            this.mapCtrl.addVisitedSeed(node, colour);
          } else {
            const nearest = findNearest(node, placedCoords);
            this.mapCtrl.addVisitedTendril(nearest, node, colour, glow);
          }
          placedCoords.push(node);
        }
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
    colour:        string,
    originAddress: string,
    destAddress:   string,
    // When provided, the polyline is drawn to finish in exactly durationMs so
    // it stays in step with a concurrent retreat animation. When omitted (no
    // retreat), the fixed PATH_ANIMATION_INTERVAL_MS is used instead.
    durationMs?:   number,
  ): void {
    this.mapCtrl.startEmptyPolyline(colour);
    this.callbacks.onProgress('Drawing route\u2026');

    const pathCoords = data.path.map(n => ({ lat: n.lat, lon: n.lon }));
    let i = 0;

    // When syncing to a retreat duration, choose the smallest interval that
    // keeps the browser's minimum timer resolution (8 ms) and batch multiple
    // coords per tick when the path is long so the total time stays on target.
    const MIN_INTERVAL_MS = 8;
    const intervalMs = durationMs !== undefined
      ? Math.max(MIN_INTERVAL_MS, durationMs / pathCoords.length)
      : PATH_ANIMATION_INTERVAL_MS;
    const batchSize = durationMs !== undefined
      ? Math.max(1, Math.ceil(pathCoords.length / (durationMs / MIN_INTERVAL_MS)))
      : 1;

    this.pathHandle = setInterval(() => {
      if (i >= pathCoords.length) {
        clearInterval(this.pathHandle!);
        this.pathHandle = null;
        this.finalise(data, originAddress, destAddress);
        return;
      }
      const end = Math.min(i + batchSize, pathCoords.length);
      for (; i < end; i++) {
        const coord = pathCoords[i];
        if (coord !== undefined) this.mapCtrl.extendPolyline(coord);
      }
    }, intervalMs);
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
    if (this.retreatCancel !== null) {
      this.retreatCancel();
      this.retreatCancel = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Nearest-neighbour helper for tendril routing during live animation
// ---------------------------------------------------------------------------

// findNearest returns the closest coord to `target` among the last 300 entries
// of `placed`. The trailing window keeps each search O(300) regardless of how
// many nodes have been placed, and biases connections toward the active
// exploration frontier, which produces organic branching rather than long
// straight lines back to the origin.
function findNearest(target: Coord, placed: Coord[]): Coord {
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
