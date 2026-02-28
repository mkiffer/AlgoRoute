import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { fetchRoute, fetchSuggestions } from './api';
import type { RouteResponse, SuggestResult } from './types';

// ---------------------------------------------------------------------------
// fetchRoute
// ---------------------------------------------------------------------------

describe('fetchRoute', () => {
  beforeEach(() => { vi.stubGlobal('fetch', vi.fn()); });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('sends a POST with JSON body and returns parsed RouteResponse', async () => {
    const mockResponse: RouteResponse = {
      algorithm: 'dijkstra',
      distance_meters: 1200,
      path: [{ node_id: 1, lat: -37.82, lon: 144.97 }],
      visited_nodes: [{ lat: -37.82, lon: 144.97 }],
      origin_coord: { lat: -37.82, lon: 144.97 },
      destination_coord: { lat: -37.83, lon: 144.98 },
    };

    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(mockResponse), { status: 200 })
    );

    const result = await fetchRoute({
      origin: 'Origin St',
      destination: 'Dest Ave',
      algorithm: 'dijkstra',
    });

    expect(result).toEqual(mockResponse);

    const [url, init] = vi.mocked(fetch).mock.calls[0] as [string, RequestInit];
    expect(url).toBe('/api/route');
    expect(init.method).toBe('POST');
    expect(JSON.parse(init.body as string)).toEqual({
      origin: 'Origin St',
      destination: 'Dest Ave',
      algorithm: 'dijkstra',
    });
  });

  it('throws when the response contains an error field', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({ error: 'route not found' }), { status: 500 })
    );

    await expect(
      fetchRoute({ origin: 'A', destination: 'B', algorithm: 'astar' })
    ).rejects.toThrow('route not found');
  });

  it('throws when ok is false and there is no error field', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify({}), { status: 400, statusText: 'Bad Request' })
    );

    await expect(
      fetchRoute({ origin: 'A', destination: 'B', algorithm: 'dijkstra' })
    ).rejects.toThrow('Bad Request');
  });
});

// ---------------------------------------------------------------------------
// fetchSuggestions
// ---------------------------------------------------------------------------

describe('fetchSuggestions', () => {
  beforeEach(() => { vi.stubGlobal('fetch', vi.fn()); });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('fetches from /api/suggest with URL-encoded query and returns results', async () => {
    const mockResults: SuggestResult[] = [
      { display_name: 'Chapel St, South Yarra', lat: -37.84, lon: 144.99 },
    ];

    vi.mocked(fetch).mockResolvedValueOnce(
      new Response(JSON.stringify(mockResults), { status: 200 })
    );

    const results = await fetchSuggestions('Chapel St');

    expect(results).toEqual(mockResults);

    const [url] = vi.mocked(fetch).mock.calls[0] as [string];
    expect(url).toBe('/api/suggest?q=Chapel%20St');
  });

  it('returns an empty array when the response is not ok', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(
      new Response('', { status: 503 })
    );

    const results = await fetchSuggestions('anything');
    expect(results).toEqual([]);
  });

  it('returns an empty array on network error', async () => {
    vi.mocked(fetch).mockRejectedValueOnce(new Error('Network failure'));

    const results = await fetchSuggestions('anything');
    expect(results).toEqual([]);
  });
});
