// config.ts — application-wide constants extracted from the original index.html.
// Keeping configuration in one place makes tuning animation feel and autocomplete
// behaviour easy without touching any logic files.

import type { Algorithm, AnimationSpeed } from './types';

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
// Dijkstra uses blue (the same family as the UI accent) to reinforce that it is
// the default algorithm. A* uses orange to highlight its directed nature.
export const ALGORITHM_COLOUR: Record<Algorithm, string> = {
  dijkstra: '#3b82f6',
  astar:    '#f97316',
};

// Milliseconds between each node appended during the path-drawing animation.
// The route path is typically short relative to the explored set, so a fixed
// rate gives a smooth, visible draw without feeling sluggish.
export const PATH_ANIMATION_INTERVAL_MS = 0.5;

// Minimum query length before a suggestion fetch is triggered. Fewer than two
// characters return too many irrelevant results from Nominatim.
export const AUTOCOMPLETE_MIN_QUERY_LENGTH = 2;

// Milliseconds to wait after the last keystroke before sending a suggestion
// request. 300 ms avoids hammering Nominatim on every keystroke while keeping
// the dropdown feeling responsive.
export const AUTOCOMPLETE_DEBOUNCE_MS = 300;
