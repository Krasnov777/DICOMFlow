import { writable } from 'svelte/store';

export const activeStudyStore = writable({
  studyInstanceUID: null,
  patientName: null,
  patientID: null,
  studyDate: null,
  modality: null,
  series: [],
  currentSeriesUID: null,
  currentInstanceUID: null,
  currentImageData: null,
  windowCenter: 128,
  windowWidth: 256,
});
