import { describe, it, expect } from 'vitest';
import { TILE_LAYERS, DEFAULT_MAP_STYLE, MAX_CLICK_RADIUS_METERS } from './config';
import type { MapStyle } from './types';

// These tests validate the tile layer configuration data that drives the
// map style switcher. The config is pure data with no Leaflet dependency,
// so it can be verified completely in the jsdom test environment.

const EXPECTED_STYLES: MapStyle[] = ['standard', 'dark', 'voyager', 'minimal'];

describe('TILE_LAYERS', () => {
  it('contains exactly the four expected style keys', () => {
    expect(Object.keys(TILE_LAYERS).sort()).toEqual([...EXPECTED_STYLES].sort());
  });

  for (const style of EXPECTED_STYLES) {
    describe(`${style} entry`, () => {
      it('has a non-empty name', () => {
        expect(TILE_LAYERS[style].name.length).toBeGreaterThan(0);
      });

      it('has a URL starting with https://', () => {
        expect(TILE_LAYERS[style].url).toMatch(/^https:\/\//);
      });

      it('has a non-empty attribution string', () => {
        expect(TILE_LAYERS[style].attribution.length).toBeGreaterThan(0);
      });
    });
  }
});

describe('MAX_CLICK_RADIUS_METERS', () => {
  it('is a positive number', () => {
    expect(typeof MAX_CLICK_RADIUS_METERS).toBe('number');
    expect(MAX_CLICK_RADIUS_METERS).toBeGreaterThan(0);
  });
});

describe('DEFAULT_MAP_STYLE', () => {
  it('is dark', () => {
    expect(DEFAULT_MAP_STYLE).toBe('dark');
  });

  it('refers to a key that exists in TILE_LAYERS', () => {
    expect(TILE_LAYERS[DEFAULT_MAP_STYLE]).toBeDefined();
  });
});
