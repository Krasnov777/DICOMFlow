import { writable } from 'svelte/store';

export const activeStudyStore = writable({
  studyInstanceUID: null,
  patientName: null,
  patientID: null,
  studyDate: null,
  modality: null,
  series: [], // Array of SeriesInfo objects
  currentSeriesIndex: 0,
  currentInstanceIndex: 0,
  currentImageData: null,
  currentFilePath: null,
  tags: [],
  windowCenter: 128,
  windowWidth: 256,
});
