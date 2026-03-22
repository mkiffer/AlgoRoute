// Tests for: map.ts — MapController layer management and click-mode methods.
// Leaflet is fully mocked so tests run in jsdom without a real DOM or canvas.

import { describe, it, expect, vi, beforeEach } from 'vitest';

// ---------------------------------------------------------------------------
// Leaflet mock
// ---------------------------------------------------------------------------

// Each Leaflet object returned by the mock tracks the calls made on it so we
// can assert on add/remove/clear operations without a real Leaflet instance.

const mockLayerGroup = () => ({
  addTo: vi.fn().mockReturnThis(),
  clearLayers: vi.fn(),
  addLayer: vi.fn(),
});

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
