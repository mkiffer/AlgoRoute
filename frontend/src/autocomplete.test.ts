import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { setupAutocomplete } from './autocomplete';
import type { SuggestResult } from './types';

// jsdom does not implement scrollIntoView; stub it globally so tests that
// trigger ArrowDown/ArrowUp do not throw "Not implemented".
Element.prototype.scrollIntoView = vi.fn();

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

function makeElements() {
  const input    = document.createElement('input');
  const dropdown = document.createElement('ul');
  document.body.appendChild(input);
  document.body.appendChild(dropdown);
  return { input, dropdown };
}

function cleanup() {
  document.body.innerHTML = '';
}

const suggestions: SuggestResult[] = [
  { display_name: 'Chapel St, South Yarra', lat: -37.84, lon: 144.99 },
  { display_name: 'Chapel St, Windsor',     lat: -37.85, lon: 144.99 },
];

// ---------------------------------------------------------------------------
// Suggestion fetch and rendering
// ---------------------------------------------------------------------------

describe('setupAutocomplete — fetch and render', () => {
  beforeEach(() => { vi.stubGlobal('fetch', vi.fn()); });
  afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });

  it('fetches suggestions and renders them in the dropdown', async () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(suggestions), { status: 200 })
    );
    vi.useFakeTimers();

    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);

    input.value = 'Chapel';
    input.dispatchEvent(new Event('input'));

    // Advance past the debounce delay.
    await vi.runAllTimersAsync();

    expect(dropdown.style.display).toBe('block');
    expect(dropdown.querySelectorAll('.autocomplete-item').length).toBe(2);
    expect(dropdown.querySelectorAll('.autocomplete-item')[0]?.textContent)
      .toBe('Chapel St, South Yarra');
  });

  it('does not fetch when query is shorter than the minimum length', async () => {
    vi.useFakeTimers();

    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);

    input.value = 'C'; // below AUTOCOMPLETE_MIN_QUERY_LENGTH (2)
    input.dispatchEvent(new Event('input'));
    await vi.runAllTimersAsync();

    expect(fetch).not.toHaveBeenCalled();
    expect(dropdown.style.display).not.toBe('block');
  });

  it('closes the dropdown when fetch returns an empty array', async () => {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify([]), { status: 200 })
    );
    vi.useFakeTimers();

    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);

    input.value = 'zzz';
    input.dispatchEvent(new Event('input'));
    await vi.runAllTimersAsync();

    expect(dropdown.style.display).not.toBe('block');
  });
});

// ---------------------------------------------------------------------------
// Keyboard navigation
// ---------------------------------------------------------------------------

describe('setupAutocomplete — keyboard navigation', () => {
  beforeEach(() => {
    vi.stubGlobal('fetch', vi.fn());
    vi.useFakeTimers();
  });
  afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.useRealTimers(); });

  async function openDropdown(input: HTMLInputElement) {
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(suggestions), { status: 200 })
    );
    input.value = 'Chapel';
    input.dispatchEvent(new Event('input'));
    await vi.runAllTimersAsync();
  }

  it('ArrowDown highlights the first item', async () => {
    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);
    await openDropdown(input);

    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));

    const items = dropdown.querySelectorAll('.autocomplete-item');
    expect(items[0]?.classList.contains('active')).toBe(true);
    expect(items[1]?.classList.contains('active')).toBe(false);
  });

  it('ArrowUp does not go below -1 (no selection)', async () => {
    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);
    await openDropdown(input);

    // At -1; pressing up should stay at -1.
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true }));

    const items = dropdown.querySelectorAll('.autocomplete-item');
    items.forEach(item => expect(item.classList.contains('active')).toBe(false));
  });

  it('Enter on a highlighted item selects it and closes the dropdown', async () => {
    const { input, dropdown } = makeElements();
    const onSelect = vi.fn();
    setupAutocomplete(input, dropdown, onSelect);
    await openDropdown(input);

    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true }));
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));

    expect(input.value).toBe('Chapel St, South Yarra');
    expect(dropdown.style.display).not.toBe('block');
    expect(onSelect).toHaveBeenCalledWith(suggestions[0]);
  });

  it('Escape closes the dropdown', async () => {
    const { input, dropdown } = makeElements();
    setupAutocomplete(input, dropdown);
    await openDropdown(input);

    expect(dropdown.style.display).toBe('block');
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(dropdown.style.display).not.toBe('block');
  });
});

// ---------------------------------------------------------------------------
// Teardown
// ---------------------------------------------------------------------------

describe('setupAutocomplete — teardown', () => {
  afterEach(cleanup);

  it('teardown function closes the dropdown', async () => {
    vi.stubGlobal('fetch', vi.fn());
    vi.useFakeTimers();
    vi.mocked(fetch).mockResolvedValue(
      new Response(JSON.stringify(suggestions), { status: 200 })
    );

    const { input, dropdown } = makeElements();
    const teardown = setupAutocomplete(input, dropdown);

    input.value = 'Chapel';
    input.dispatchEvent(new Event('input'));
    await vi.runAllTimersAsync();

    teardown();
    expect(dropdown.style.display).not.toBe('block');

    vi.unstubAllGlobals();
    vi.useRealTimers();
  });
});
