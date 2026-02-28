// ui.ts — stateless DOM helper functions for the AlgoRoute control bar.
// Each function reads an element by its well-known ID and updates it.
// No state is held here; callers own the state and pass it in as arguments.

// showStatus updates the status bar text. Pass isError=true to apply red styling.
export function showStatus(message: string, isError = false): void {
  const el = document.getElementById('status-message')!;
  el.textContent = message;
  el.className = isError ? 'error' : '';
}

// showSkipButton shows or hides the skip-animation button.
export function showSkipButton(visible: boolean): void {
  document.getElementById('skip-button')!.style.display = visible ? 'block' : 'none';
}

// showToggleVisitedButton shows or hides the explored-node toggle button and
// keeps its label in sync with the current visibility state.
export function showToggleVisitedButton(visible: boolean, nodesCurrentlyVisible: boolean): void {
  const btn = document.getElementById('toggle-visited-button')!;
  btn.style.display = visible ? 'block' : 'none';
  if (visible) updateToggleVisitedButtonLabel(nodesCurrentlyVisible);
}

// updateToggleVisitedButtonLabel sets the button label to reflect whether
// explored nodes are currently shown or hidden.
export function updateToggleVisitedButtonLabel(nodesVisible: boolean): void {
  document.getElementById('toggle-visited-button')!.textContent =
    nodesVisible ? 'Hide explored nodes' : 'Show explored nodes';
}

// updateLegend sets the explored-node swatch colour and label to match the
// chosen algorithm, then makes the legend bar visible.
export function updateLegend(algorithm: string, colour: string): void {
  const swatch = document.getElementById('legend-visited-swatch')!;
  const label  = document.getElementById('legend-visited-label')!;
  swatch.style.background = colour;
  label.textContent = algorithm === 'astar' ? 'A* explored nodes' : 'Dijkstra explored nodes';
  document.getElementById('legend')!.classList.add('visible');
}
