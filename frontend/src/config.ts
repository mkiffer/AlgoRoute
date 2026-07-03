// config.ts — application-wide constants extracted from the original index.html.
// Keeping configuration in one place makes tuning animation feel and autocomplete
// behaviour easy without touching any logic files.

import type { Algorithm, AnimationSpeed, MapStyle } from './types';

// AlgorithmVisualStyle determines how explored nodes are rendered during
// traversal animation. 'dots' draws standalone circular markers that form
// expanding concentric rings; 'tendrils' draws connected line segments that
// grow toward the destination like branching veins.
export type AlgorithmVisualStyle = 'dots' | 'tendrils';

// ALGORITHM_STYLE maps each algorithm to its traversal animation style.
// Centralising this here prevents scattered algorithm === 'dijkstra' checks
// across animation.ts and map.ts.
export const ALGORITHM_STYLE: Record<Algorithm, AlgorithmVisualStyle> = {
  dijkstra:   'dots',     // radial expansion → concentric rings
  bidijkstra: 'dots',     // two radial expansions → two concentric rings
  astar:      'tendrils', // directed heuristic search → corridor tendrils
  greedy:     'tendrils', // aggressive heuristic sprint → narrower tendrils
};

// SpeedSetting controls how many explored-node markers are added per animation
// tick and how many milliseconds elapse between ticks.
export interface SpeedSetting {
  batchSize: number;
  intervalMs: number;
}

// SPEED_CONFIG maps each AnimationSpeed option to its rendering parameters.
// Larger batches at higher speeds keep the interval callback lightweight even
// for networks with tens of thousands of explored nodes.
export const SPEED_CONFIG: Record<AnimationSpeed, SpeedSetting> = {
  slow:   { batchSize:  1, intervalMs: 60 },
  medium: { batchSize:  5, intervalMs: 20 },
  fast:   { batchSize: 20, intervalMs:  8 },
};

// ALGORITHM_COLOUR maps each algorithm to its visualisation colour.
export const ALGORITHM_COLOUR: Record<Algorithm, string> = {
  dijkstra:   '#f59e0b',  // amber    — radial warm glow
  astar:      '#f97316',  // orange   — directed warm sprint
  greedy:     '#10b981',  // emerald  — fast heuristic sprint toward goal
  bidijkstra: '#8b5cf6',  // purple   — two-frontier pincer
};

// Milliseconds between each node appended during the path-drawing animation.
// The route path is typically short relative to the explored set, so a fixed
// rate gives a smooth, visible draw without feeling sluggish.
export const PATH_ANIMATION_INTERVAL_MS = 0.5;

// Total duration of the retreat animation in milliseconds. Each node is
// assigned its own timeout within this window based on its distance from
// the route — far nodes fire early, close nodes linger until the end.
export const RETREAT_DURATION_MS = 800;

// Maximum random timing offset applied to each node's retreat delay, in
// milliseconds. The jitter de-synchronises nodes at similar distances so
// removal feels scattered and organic rather than advancing in lock-step.
export const RETREAT_JITTER_MS = 150;

// Minimum query length before a suggestion fetch is triggered. Fewer than two
// characters return too many irrelevant results from Nominatim.
export const AUTOCOMPLETE_MIN_QUERY_LENGTH = 2;

// Milliseconds to wait after the last keystroke before sending a suggestion
// request. 300 ms avoids hammering Nominatim on every keystroke while keeping
// the dropdown feeling responsive.
export const AUTOCOMPLETE_DEBOUNCE_MS = 300;

// TileLayerConfig holds the Leaflet tile layer parameters for one map style.
export interface TileLayerConfig {
  name: string;
  url: string;
  attribution: string;
}

// CARTO_ATTRIBUTION is shared by all CartoDB tile styles.
const CARTO_ATTRIBUTION =
  '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
  '&copy; <a href="https://carto.com/attributions">CARTO</a>';

// TILE_LAYERS maps each MapStyle key to its Leaflet tile layer parameters.
// All four providers are free and require no API key.
// The {r} placeholder in CartoDB URLs resolves to "@2x" on retina displays
// when Leaflet's detectRetina option is enabled.
export const TILE_LAYERS: Record<MapStyle, TileLayerConfig> = {
  standard: {
    name: 'Standard',
    url: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  },
  dark: {
    name: 'Dark',
    url: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
    attribution: CARTO_ATTRIBUTION,
  },
  voyager: {
    name: 'Voyager',
    url: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
    attribution: CARTO_ATTRIBUTION,
  },
  minimal: {
    name: 'Minimal',
    url: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    attribution: CARTO_ATTRIBUTION,
  },
};

// DEFAULT_MAP_STYLE is the tile layer shown on initial load.
// Dark is the default so the amber traversal tendrils glow against the background.
export const DEFAULT_MAP_STYLE: MapStyle = 'dark';

// MAX_CLICK_RADIUS_METERS is the maximum distance from the origin at which a
// destination click is accepted. 20 km produces a bounding box of ≈ 400 km²,
// which stays under the 500 km² backend limit for Overpass queries.
export const MAX_CLICK_RADIUS_METERS = 20_000;
