import { writable } from 'svelte/store';

export const loadingStore = writable({
  isLoading: false,
  currentOperation: '',
  progress: 0, // 0-100 percentage, or -1 for indeterminate
  message: ''
});

// Helper functions to update loading state
export function startLoading(operation, message = '') {
  loadingStore.set({
    isLoading: true,
    currentOperation: operation,
    progress: -1, // indeterminate
    message: message
  });
}

export function updateProgress(progress, message = '') {
  loadingStore.update(state => ({
    ...state,
    progress,
    message: message || state.message
  }));
}

export function finishLoading(message = '') {
  loadingStore.set({
    isLoading: false,
    currentOperation: '',
    progress: 0,
    message: message
  });

  // Clear success message after 3 seconds
  if (message) {
    setTimeout(() => {
      loadingStore.update(state => {
        if (!state.isLoading) {
          return { ...state, message: '' };
        }
        return state;
      });
    }, 3000);
  }
}

export function setError(error) {
  loadingStore.set({
    isLoading: false,
    currentOperation: '',
    progress: 0,
    message: `Error: ${error}`
  });

  // Clear error message after 5 seconds
  setTimeout(() => {
    loadingStore.update(state => ({
      ...state,
      message: ''
    }));
  }, 5000);
}
