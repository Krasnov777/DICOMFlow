import { writable } from 'svelte/store';

export const connectionStore = writable({
  scpRunning: false,
  scpConfig: {
    aeTitle: 'DICOM_TOOLKIT',
    port: 11112,
  },
  activeDicomWebEndpoint: null,
  pacsEndpoints: [],
  dicomwebEndpoints: [],
});
