import { writable } from 'svelte/store';

export const settingsStore = writable({
  workspaceMode: true,
  autoClearCache: false,
  maxDiskUsage: 1024 * 1024 * 1024, // 1 GB
  defaultWindowPresets: {
    CT: [
      { name: 'Lung', center: -600, width: 1500 },
      { name: 'Bone', center: 400, width: 1800 },
      { name: 'Soft Tissue', center: 50, width: 350 },
    ],
  },
  thumbnailSize: 128,
  imageInterpolation: 'bilinear',
});
