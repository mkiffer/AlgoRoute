// autocomplete.ts — address suggestion dropdown for a text input.
// All state (debounce timer, active index, suggestions list) is local to each
// call, so two inputs on the same page are fully independent.

import { fetchSuggestions } from './api';
import {
  AUTOCOMPLETE_MIN_QUERY_LENGTH,
  AUTOCOMPLETE_DEBOUNCE_MS,
} from './config';
import type { SuggestResult } from './types';

// SelectCallback is invoked when the user confirms a suggestion by clicking or
// pressing Enter. The caller can use the Coord fields to snap the map view.
type SelectCallback = (suggestion: SuggestResult) => void;

// setupAutocomplete wires predictive address suggestions to an input element.
// Suggestions are fetched from GET /api/suggest?q=<query> with a debounce.
// Keyboard: ArrowDown/ArrowUp navigate, Enter selects or submits, Escape closes.
//
// Returns a teardown function that cancels any pending debounce and closes the
// dropdown — call it when the input is removed from the DOM.
export function setupAutocomplete(
  inputEl: HTMLInputElement,
  dropdownEl: HTMLUListElement,
  onSelect?: SelectCallback,
): () => void {
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let activeIndex = -1;
  let suggestions: SuggestResult[] = [];

  inputEl.addEventListener('input', handleInput);
  inputEl.addEventListener('keydown', handleKeydown);
  // Delay closing so a mousedown on a list item fires before blur removes it.
  inputEl.addEventListener('blur', handleBlur);

  function handleInput() {
    if (debounceTimer !== null) clearTimeout(debounceTimer);
    const query = inputEl.value.trim();
    if (query.length < AUTOCOMPLETE_MIN_QUERY_LENGTH) {
      closeDropdown();
      return;
    }
    debounceTimer = setTimeout(() => triggerFetch(query), AUTOCOMPLETE_DEBOUNCE_MS);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      activeIndex = Math.min(activeIndex + 1, suggestions.length - 1);
      highlightActive();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      activeIndex = Math.max(activeIndex - 1, -1);
      highlightActive();
    } else if (e.key === 'Enter') {
      const selected = activeIndex >= 0 ? suggestions[activeIndex] : undefined;
      if (selected !== undefined) {
        // Select the highlighted suggestion and suppress the event from
        // propagating to the find-route button's click listener.
        e.stopImmediatePropagation();
        e.preventDefault();
        selectSuggestion(selected);
      } else {
        // No suggestion active — let the caller handle submission.
        closeDropdown();
      }
    } else if (e.key === 'Escape') {
      closeDropdown();
    }
  }

  function handleBlur() {
    setTimeout(closeDropdown, 150);
  }

  async function triggerFetch(query: string) {
    suggestions  = await fetchSuggestions(query);
    activeIndex  = -1;
    renderDropdown();
  }

  function renderDropdown() {
    dropdownEl.innerHTML = '';
    if (suggestions.length === 0) {
      closeDropdown();
      return;
    }
    for (const suggestion of suggestions) {
      const li = document.createElement('li');
      li.className   = 'autocomplete-item';
      li.textContent = suggestion.display_name;
      // mousedown fires before blur so the click is not swallowed.
      li.addEventListener('mousedown', (e) => {
        e.preventDefault();
        selectSuggestion(suggestion);
      });
      dropdownEl.appendChild(li);
    }
    dropdownEl.style.display = 'block';
  }

  function highlightActive() {
    const items = dropdownEl.querySelectorAll('.autocomplete-item');
    items.forEach((item, i) => item.classList.toggle('active', i === activeIndex));
    const activeItem = items[activeIndex];
    if (activeIndex >= 0 && activeItem !== undefined) {
      activeItem.scrollIntoView({ block: 'nearest' });
    }
  }

  function selectSuggestion(suggestion: SuggestResult) {
    inputEl.value = suggestion.display_name;
    onSelect?.(suggestion);
    closeDropdown();
  }

  function closeDropdown() {
    dropdownEl.style.display = 'none';
    dropdownEl.innerHTML     = '';
    activeIndex              = -1;
    suggestions              = [];
  }

  return () => {
    if (debounceTimer !== null) clearTimeout(debounceTimer);
    closeDropdown();
  };
}
