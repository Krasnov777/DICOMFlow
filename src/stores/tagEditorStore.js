import { writable } from 'svelte/store';

export const tagEditorStore = writable({
  tags: [],
  modifiedTags: new Map(),
  searchQuery: '',
  selectedTags: [],
  anonymizationTemplate: null,
});
