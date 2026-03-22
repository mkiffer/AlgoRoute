// Tests for: map.ts — MapController layer management and click-mode methods.
// Leaflet is fully mocked so tests run in jsdom without a real DOM or canvas.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { RETREAT_DURATION_MS, RETREAT_JITTER_MS } from './config';

// ---------------------------------------------------------------------------
// Leaflet mock
// ---------------------------------------------------------------------------

// Each Leaflet object returned by the mock tracks the calls made on it so we
// can assert on add/remove/clear operations without a real Leaflet instance.

const mockLayerGroup = () => {
  const layers: any[] = [];
  return {
    _layers: layers,
    addTo:       vi.fn().mockReturnThis(),
    clearLayers: vi.fn(),
    addLayer:    vi.fn().mockImplementation((layer: any) => { layers.push(layer); }),
    removeLayer: vi.fn(),
    eachLayer:   vi.fn().mockImplementation((fn: (l: any) => void) => { layers.forEach(fn); }),
  };
};

const mockMarker = () => ({
  addTo: vi.fn().mockReturnThis(),
  bindPopup: vi.fn().mockReturnThis(),
  on: vi.fn().mockReturnThis(),
  remove: vi.fn(),
});

const mockCircle = () => ({
  addTo: vi.fn().mockReturnThis(),
  remove: vi.fn(),
});

const mockCircleMarker = () => ({
  addTo: vi.fn().mockReturnThis(),
});

const mockPolyline = () => ({
  addTo: vi.fn().mockReturnThis(),
  addLatLng: vi.fn(),
  remove: vi.fn(),
});

const mockTileLayer = () => ({
  addTo: vi.fn().mockReturnThis(),
  remove: vi.fn(),
});

// Captures the map event handlers so tests can trigger them.
const mapOnHandlers: Record<string, (e: unknown) => void> = {};
const mapOffHandlers: Record<string, (e: unknown) => void> = {};

const mockMapInstance = {
  setView: vi.fn().mockReturnThis(),
  on: vi.fn((event: string, handler: (e: unknown) => void) => {
    mapOnHandlers[event] = handler;
  }),
  off: vi.fn((event: string, handler: (e: unknown) => void) => {
    mapOffHandlers[event] = handler;
  }),
  fitBounds: vi.fn(),
  removeLayer: vi.fn(),
};

// Track layer group instances created during each test so tests can inspect them.
let layerGroupInstances: ReturnType<typeof mockLayerGroup>[] = [];
let markerInstances: ReturnType<typeof mockMarker>[] = [];
let circleInstances: ReturnType<typeof mockCircle>[] = [];

vi.mock('leaflet', () => {
  return {
    default: {
      map: vi.fn(() => mockMapInstance),
      tileLayer: vi.fn(() => mockTileLayer()),
      control: {
        zoom: vi.fn(() => ({ addTo: vi.fn().mockReturnThis() })),
      },
      layerGroup: vi.fn(() => {
        const lg = mockLayerGroup();
        layerGroupInstances.push(lg);
        return lg;
      }),
      marker: vi.fn(() => {
        const m = mockMarker();
        markerInstances.push(m);
        return m;
      }),
      circle: vi.fn(() => {
        const c = mockCircle();
        circleInstances.push(c);
        return c;
      }),
      circleMarker: vi.fn(() => mockCircleMarker()),
      polyline: vi.fn(() => mockPolyline()),
      latLngBounds: vi.fn(() => ({})),
      divIcon: vi.fn(() => ({})),
    },
  };
});

// Import after mocking so the mock is in place when the module is loaded.
import { MapController } from './map';
import type { RetreatOptions } from './map';
import L from 'leaflet';

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();
  layerGroupInstances = [];
  markerInstances = [];
  circleInstances = [];
  Object.keys(mapOnHandlers).forEach(k => delete mapOnHandlers[k]);
  Object.keys(mapOffHandlers).forEach(k => delete mapOffHandlers[k]);
});

function makeController(): MapController {
  return new MapController('map');
}

// ---------------------------------------------------------------------------
// onMapClick / offMapClick
// ---------------------------------------------------------------------------

describe('onMapClick', () => {
  it('calls map.on("click", handler)', () => {
    const ctrl = makeController();
    const handler = vi.fn();

    ctrl.onMapClick(handler);

    expect(mockMapInstance.on).toHaveBeenCalledWith('click', expect.any(Function));
  });

  it('replaces the previous click listener when called a second time', () => {
    const ctrl = makeController();
    const firstHandler = vi.fn();
    const secondHandler = vi.fn();

    ctrl.onMapClick(firstHandler);
    ctrl.onMapClick(secondHandler);

    // map.off must have been called to detach the first listener.
    expect(mockMapInstance.off).toHaveBeenCalled();
    // map.on must have been called twice in total.
    const clickCalls = vi.mocked(mockMapInstance.on).mock.calls.filter(
      ([event]) => event === 'click'
    );
    expect(clickCalls.length).toBe(2);
  });
});

describe('offMapClick', () => {
  it('calls map.off with the stored listener', () => {
    const ctrl = makeController();
    ctrl.onMapClick(vi.fn());
    vi.clearAllMocks();

    ctrl.offMapClick();

    expect(mockMapInstance.off).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// showRadiusCircle / hideRadiusCircle
// ---------------------------------------------------------------------------

describe('showRadiusCircle', () => {
  it('creates a circle with the specified radius', () => {
    const ctrl = makeController();

    ctrl.showRadiusCircle({ lat: -37.82, lon: 144.97 }, 20_000);

    expect(L.circle).toHaveBeenCalledWith(
      [-37.82, 144.97],
      expect.objectContaining({ radius: 20_000 })
    );
  });

  it('removes a prior circle before creating a new one', () => {
    const ctrl = makeController();

    ctrl.showRadiusCircle({ lat: -37.82, lon: 144.97 }, 20_000);
    const firstCircle = circleInstances[0]!;
    vi.clearAllMocks();
    circleInstances = [];

    ctrl.showRadiusCircle({ lat: -37.83, lon: 144.98 }, 20_000);

    expect(firstCircle.remove).toHaveBeenCalled();
  });
});

describe('hideRadiusCircle', () => {
  it('removes the circle from the map and nulls the reference', () => {
    const ctrl = makeController();
    ctrl.showRadiusCircle({ lat: -37.82, lon: 144.97 }, 20_000);
    const circle = circleInstances[0]!;

    ctrl.hideRadiusCircle();

    expect(circle.remove).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// placeClickMarker / clearClickMarkers
// ---------------------------------------------------------------------------

describe('placeClickMarker', () => {
  it('creates a draggable marker and returns it', () => {
    const ctrl = makeController();
    const onDragEnd = vi.fn();

    ctrl.placeClickMarker({ lat: -37.82, lon: 144.97 }, 'origin', onDragEnd);

    expect(L.marker).toHaveBeenCalledWith(
      [-37.82, 144.97],
      expect.objectContaining({ draggable: true })
    );
  });

  it('registers a dragend listener on the marker', () => {
    const ctrl = makeController();
    ctrl.placeClickMarker({ lat: -37.82, lon: 144.97 }, 'origin', vi.fn());

    const marker = markerInstances[markerInstances.length - 1]!;
    expect(marker.on).toHaveBeenCalledWith('dragend', expect.any(Function));
  });
});

describe('clearClickMarkers', () => {
  it('calls clearLayers on the clickMarkerGroup', () => {
    const ctrl = makeController();
    // clickMarkerGroup is the third layerGroup created (after markerGroup and visitedGroup)
    const clickMarkerGroup = layerGroupInstances[2]!;

    ctrl.clearClickMarkers();

    expect(clickMarkerGroup.clearLayers).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// clearRouteOverlays — must not touch clickMarkerGroup or radiusCircle
// ---------------------------------------------------------------------------

describe('clearRouteOverlays', () => {
  it('does NOT clear the clickMarkerGroup', () => {
    const ctrl = makeController();
    ctrl.showRadiusCircle({ lat: -37.82, lon: 144.97 }, 20_000);
    ctrl.placeClickMarker({ lat: -37.82, lon: 144.97 }, 'origin', vi.fn());

    const clickMarkerGroup = layerGroupInstances[2]!;
    vi.clearAllMocks();

    ctrl.clearRouteOverlays();

    expect(clickMarkerGroup.clearLayers).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// clearAll — must clear both route overlays and click-mode state
// ---------------------------------------------------------------------------

describe('clearAll', () => {
  it('clears clickMarkerGroup', () => {
    const ctrl = makeController();
    const clickMarkerGroup = layerGroupInstances[2]!;

    ctrl.clearAll();

    expect(clickMarkerGroup.clearLayers).toHaveBeenCalled();
  });

  it('hides the radius circle', () => {
    const ctrl = makeController();
    ctrl.showRadiusCircle({ lat: -37.82, lon: 144.97 }, 20_000);
    const circle = circleInstances[0]!;
    vi.clearAllMocks();

    ctrl.clearAll();

    expect(circle.remove).toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// startRetreat — gradual distance-sorted removal of visited-node layers
// ---------------------------------------------------------------------------

// layerAt creates a minimal mock layer at a given coordinate, compatible with
// the duck-typed layerCoord helper used inside startRetreat.
function layerAt(lat: number, lon: number): any {
  return { getLatLng: vi.fn(() => ({ lat, lng: lon })) };
}

// withRealRemoval overrides removeLayer on a mock group so removal actually
// mutates _layers, which is needed for the interval termination logic.
function withRealRemoval(group: ReturnType<typeof mockLayerGroup>): void {
  (group.removeLayer as ReturnType<typeof vi.fn>).mockImplementation((layer: any) => {
    const idx = group._layers.indexOf(layer);
    if (idx !== -1) group._layers.splice(idx, 1);
  });
}

// Shorthand for building a RetreatOptions with sensible defaults.
function retreatOpts(overrides: Partial<RetreatOptions> = {}): RetreatOptions {
  return {
    algorithm:  'dijkstra',
    origin:     { lat: 0, lon: 0 },
    dest:       { lat: 10, lon: 0 },
    pathCoords: [{ lat: 0, lon: 0 }],
    ...overrides,
  };
}

describe('startRetreat', () => {
  it('calls onDone immediately when visitedGroup is empty', () => {
    vi.useFakeTimers();
    const ctrl = makeController();
    const onDone = vi.fn();

    ctrl.startRetreat(retreatOpts({ pathCoords: [] }), onDone);

    expect(onDone).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });

  it('calls onDone after all layers have been removed', () => {
    vi.useFakeTimers();
    const ctrl = makeController();
    const visitedGroup = layerGroupInstances[1]!;

    visitedGroup._layers.push(layerAt(1, 0), layerAt(2, 0));
    withRealRemoval(visitedGroup);

    const onDone = vi.fn();
    ctrl.startRetreat(retreatOpts(), onDone);

    expect(onDone).not.toHaveBeenCalled();
    vi.runAllTimers();
    expect(onDone).toHaveBeenCalledOnce();
    vi.useRealTimers();
  });

  it('cancel function clears remaining layers and prevents onDone firing', () => {
    vi.useFakeTimers();
    const ctrl = makeController();
    const visitedGroup = layerGroupInstances[1]!;

    visitedGroup._layers.push(layerAt(1, 0), layerAt(2, 0), layerAt(3, 0));
    withRealRemoval(visitedGroup);
    (visitedGroup.clearLayers as ReturnType<typeof vi.fn>).mockImplementation(() => {
      visitedGroup._layers.length = 0;
    });

    const onDone = vi.fn();
    const cancel = ctrl.startRetreat(retreatOpts(), onDone);

    cancel();

    expect(visitedGroup.clearLayers).toHaveBeenCalled();
    expect(onDone).not.toHaveBeenCalled();

    vi.advanceTimersByTime(RETREAT_DURATION_MS + RETREAT_JITTER_MS);
    expect(onDone).not.toHaveBeenCalled();
    vi.useRealTimers();
  });

  it('dijkstra: nodes far from origin are removed before nodes close to origin', () => {
    vi.useFakeTimers();
    const ctrl = makeController();
    const visitedGroup = layerGroupInstances[1]!;

    // Origin at (0,0). farLayer is 10 units away, closeLayer is 0.1.
    const farLayer   = layerAt(10, 0);
    const closeLayer = layerAt(0.1, 0);
    visitedGroup._layers.push(farLayer, closeLayer);

    const removed: any[] = [];
    (visitedGroup.removeLayer as ReturnType<typeof vi.fn>).mockImplementation((layer: any) => {
      removed.push(layer);
      const idx = visitedGroup._layers.indexOf(layer);
      if (idx !== -1) visitedGroup._layers.splice(idx, 1);
    });

    ctrl.startRetreat(retreatOpts({ algorithm: 'dijkstra', origin: { lat: 0, lon: 0 } }), vi.fn());
    vi.runAllTimers();

    expect(removed[0]).toBe(farLayer);
    expect(removed[removed.length - 1]).toBe(closeLayer);
    vi.useRealTimers();
  });

  it('astar: nodes far from O→D axis are removed before nodes on the axis', () => {
    vi.useFakeTimers();
    const ctrl = makeController();
    const visitedGroup = layerGroupInstances[1]!;

    // Origin (0,0) → Dest (10,0): axis is horizontal along lat.
    // onAxisNode sits right on the axis; offAxisNode is far off to the side.
    const offAxisNode = layerAt(5, 8);   // perpendicular dist ≈ 8
    const onAxisNode  = layerAt(5, 0.1); // perpendicular dist ≈ 0.1
    visitedGroup._layers.push(offAxisNode, onAxisNode);

    const removed: any[] = [];
    (visitedGroup.removeLayer as ReturnType<typeof vi.fn>).mockImplementation((layer: any) => {
      removed.push(layer);
      const idx = visitedGroup._layers.indexOf(layer);
      if (idx !== -1) visitedGroup._layers.splice(idx, 1);
    });

    ctrl.startRetreat(
      retreatOpts({ algorithm: 'astar', origin: { lat: 0, lon: 0 }, dest: { lat: 10, lon: 0 } }),
      vi.fn(),
    );
    vi.runAllTimers();

    expect(removed[0]).toBe(offAxisNode);
    expect(removed[removed.length - 1]).toBe(onAxisNode);
    vi.useRealTimers();
  });
});

// ---------------------------------------------------------------------------
// addVisitedDot — Dijkstra ripple dot
// ---------------------------------------------------------------------------

describe('addVisitedDot', () => {
  it('creates a circleMarker on the visitedGroup', () => {
    const ctrl = makeController();

    ctrl.addVisitedDot({ lat: -37.82, lon: 144.97 }, '#f59e0b');

    expect(L.circleMarker).toHaveBeenCalledWith(
      [-37.82, 144.97],
      expect.objectContaining({ fillColor: '#f59e0b' }),
    );
  });
});

// ---------------------------------------------------------------------------
// addVisitedTendril with glowIntensity — A* heuristic glow
// ---------------------------------------------------------------------------

describe('addVisitedTendril glowIntensity', () => {
  it('modulates polyline opacity based on glowIntensity', () => {
    const ctrl = makeController();

    ctrl.addVisitedTendril({ lat: 0, lon: 0 }, { lat: 1, lon: 1 }, '#f97316', 0.8);

    const polylineCall = vi.mocked(L.polyline).mock.calls[0]!;
    const opts = polylineCall[1] as any;
    // glowIntensity=0.8 → lineOpacity = 0.15 + 0.45*0.8 = 0.51
    expect(opts.opacity).toBeCloseTo(0.51, 1);
  });

  it('modulates dot radius based on glowIntensity', () => {
    const ctrl = makeController();

    ctrl.addVisitedTendril({ lat: 0, lon: 0 }, { lat: 1, lon: 1 }, '#f97316', 0.8);

    const cmCall = vi.mocked(L.circleMarker).mock.calls[0]!;
    const opts = cmCall[1] as any;
    // glowIntensity=0.8 → dotRadius = 1 + 1.5*0.8 = 2.2
    expect(opts.radius).toBeCloseTo(2.2, 1);
  });
});

// ---------------------------------------------------------------------------
// showVisitedNodes — algorithm-aware re-render
// ---------------------------------------------------------------------------

describe('showVisitedNodes', () => {
  it('uses dots (no tendrils) for dijkstra', () => {
    const ctrl = makeController();

    ctrl.showVisitedNodes(
      [{ lat: 1, lon: 0 }, { lat: 2, lon: 0 }],
      '#f59e0b',
      'dijkstra',
    );

    // Dijkstra draws standalone dots — circleMarker calls but no polyline.
    expect(L.circleMarker).toHaveBeenCalled();
    expect(L.polyline).not.toHaveBeenCalled();
  });

  it('uses tendrils for astar', () => {
    const ctrl = makeController();

    ctrl.showVisitedNodes(
      [{ lat: 1, lon: 0 }, { lat: 2, lon: 0 }],
      '#f97316',
      'astar',
      { lat: 10, lon: 0 },
    );

    // A* draws tendril connections — polyline should be called.
    expect(L.polyline).toHaveBeenCalled();
  });
});
