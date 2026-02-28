import { describe, it, expect, beforeEach } from 'vitest';
import {
  showStatus,
  showSkipButton,
  showToggleVisitedButton,
  updateToggleVisitedButtonLabel,
  updateLegend,
} from './ui';

// Each test gets a fresh DOM that mirrors the elements in src/index.html.
function setupDOM() {
  document.body.innerHTML = `
    <div id="status-message"></div>
    <button id="skip-button" style="display:none"></button>
    <button id="toggle-visited-button" style="display:none">Show explored nodes</button>
    <div id="legend"></div>
    <span id="legend-visited-swatch"></span>
    <span id="legend-visited-label"></span>
  `;
}

describe('showStatus', () => {
  beforeEach(setupDOM);

  it('sets text content and removes error class', () => {
    const el = document.getElementById('status-message')!;
    el.className = 'error';

    showStatus('Route found');

    expect(el.textContent).toBe('Route found');
    expect(el.className).toBe('');
  });

  it('sets error class when isError is true', () => {
    showStatus('Something went wrong', true);

    const el = document.getElementById('status-message')!;
    expect(el.className).toBe('error');
  });
});

describe('showSkipButton', () => {
  beforeEach(setupDOM);

  it('shows the skip button', () => {
    showSkipButton(true);
    expect(document.getElementById('skip-button')!.style.display).toBe('block');
  });

  it('hides the skip button', () => {
    showSkipButton(false);
    expect(document.getElementById('skip-button')!.style.display).toBe('none');
  });
});

describe('showToggleVisitedButton', () => {
  beforeEach(setupDOM);

  it('shows the toggle button and updates its label', () => {
    showToggleVisitedButton(true, false);

    const btn = document.getElementById('toggle-visited-button')!;
    expect(btn.style.display).toBe('block');
    expect(btn.textContent).toBe('Show explored nodes');
  });

  it('hides the toggle button', () => {
    showToggleVisitedButton(false, false);
    expect(document.getElementById('toggle-visited-button')!.style.display).toBe('none');
  });
});

describe('updateToggleVisitedButtonLabel', () => {
  beforeEach(setupDOM);

  it('shows "Hide explored nodes" when nodes are visible', () => {
    updateToggleVisitedButtonLabel(true);
    expect(document.getElementById('toggle-visited-button')!.textContent).toBe('Hide explored nodes');
  });

  it('shows "Show explored nodes" when nodes are hidden', () => {
    updateToggleVisitedButtonLabel(false);
    expect(document.getElementById('toggle-visited-button')!.textContent).toBe('Show explored nodes');
  });
});

describe('updateLegend', () => {
  beforeEach(setupDOM);

  it('sets dijkstra label and swatch colour, makes legend visible', () => {
    updateLegend('dijkstra', '#3b82f6');

    const legend = document.getElementById('legend')!;
    const swatch = document.getElementById('legend-visited-swatch')!;
    const label  = document.getElementById('legend-visited-label')!;

    expect(legend.classList.contains('visible')).toBe(true);
    // jsdom normalises hex colours to rgb() notation.
    expect(swatch.style.background).toMatch(/^(#3b82f6|rgb\(59,\s*130,\s*246\))$/);
    expect(label.textContent).toBe('Dijkstra explored nodes');
  });

  it('sets A* label when algorithm is astar', () => {
    updateLegend('astar', '#f97316');

    const label = document.getElementById('legend-visited-label')!;
    expect(label.textContent).toBe('A* explored nodes');
  });
});
