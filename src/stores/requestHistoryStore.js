import { writable } from 'svelte/store';

export const requestHistoryStore = writable({
  requests: [],
  maxHistory: 50,
});

export function addRequest(request) {
  requestHistoryStore.update((store) => {
    const requests = [request, ...store.requests].slice(0, store.maxHistory);
    return { ...store, requests };
  });
}
