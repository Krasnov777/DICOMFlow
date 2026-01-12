<script>
  import { activeStudyStore } from '../stores/activeStudyStore';
  import { invoke } from '@tauri-apps/api/core';

  let windowCenter = $activeStudyStore.windowCenter || 128;
  let windowWidth = $activeStudyStore.windowWidth || 256;
  let isLoading = false;

  // Load image when file path changes
  $: if ($activeStudyStore.currentFilePath) {
    loadImage();
  }

  async function loadImage() {
    if (!$activeStudyStore.currentFilePath) return;

    isLoading = true;
    try {
      // Get metadata to retrieve default windowing
      const metadata = await invoke('get_metadata', {
        filePath: $activeStudyStore.currentFilePath
      });

      // Update windowing from metadata if available
      if (metadata.window_center && metadata.window_width) {
        windowCenter = metadata.window_center;
        windowWidth = metadata.window_width;
        activeStudyStore.update(store => ({
          ...store,
          windowCenter: metadata.window_center,
          windowWidth: metadata.window_width
        }));
      }

      // Load image with default or current windowing
      const base64Png = await invoke('get_image_data', {
        filePath: $activeStudyStore.currentFilePath,
        windowCenter: windowCenter,
        windowWidth: windowWidth
      });

      // Update store with image data
      activeStudyStore.update(store => ({
        ...store,
        currentImageData: `data:image/png;base64,${base64Png}`
      }));
    } catch (error) {
      console.error('Failed to load image:', error);
      alert(`Failed to load image: ${error}`);
    } finally {
      isLoading = false;
    }
  }

  async function applyWindowing() {
    if (!$activeStudyStore.currentFilePath) return;

    isLoading = true;
    try {
      // Apply new windowing
      const base64Png = await invoke('apply_windowing', {
        filePath: $activeStudyStore.currentFilePath,
        center: windowCenter,
        width: windowWidth
      });

      // Update store
      activeStudyStore.update(store => ({
        ...store,
        currentImageData: `data:image/png;base64,${base64Png}`,
        windowCenter: windowCenter,
        windowWidth: windowWidth
      }));
    } catch (error) {
      console.error('Failed to apply windowing:', error);
    } finally {
      isLoading = false;
    }
  }
</script>

<div class="flex h-full">
  <!-- Study/Series Browser -->
  <div class="w-64 bg-gray-700 p-4 overflow-y-auto">
    <h2 class="text-lg font-semibold mb-4">Study Browser</h2>
    {#if $activeStudyStore.studyInstanceUID}
      <div class="space-y-2">
        <p class="text-sm"><strong>Patient:</strong> {$activeStudyStore.patientName || 'N/A'}</p>
        <p class="text-sm"><strong>ID:</strong> {$activeStudyStore.patientID || 'N/A'}</p>
        <p class="text-sm"><strong>Date:</strong> {$activeStudyStore.studyDate || 'N/A'}</p>
      </div>
    {:else}
      <p class="text-gray-400 text-sm">No study loaded</p>
    {/if}
  </div>

  <!-- Image Viewport -->
  <div class="flex-1 flex flex-col">
    <div class="flex-1 bg-black flex items-center justify-center relative">
      {#if isLoading}
        <div class="absolute inset-0 flex items-center justify-center bg-black bg-opacity-50 z-10">
          <div class="text-white">Loading image...</div>
        </div>
      {/if}
      {#if $activeStudyStore.currentImageData}
        <img src={$activeStudyStore.currentImageData} alt="DICOM" class="max-w-full max-h-full" />
      {:else if !isLoading}
        <p class="text-gray-500">No image loaded</p>
      {/if}
    </div>

    <!-- Windowing Controls -->
    <div class="bg-gray-700 p-4 space-y-2">
      <div class="flex items-center gap-4">
        <label class="flex items-center gap-2">
          <span class="text-sm">W/C:</span>
          <input
            type="range"
            min="-1000"
            max="1000"
            bind:value={windowCenter}
            on:change={applyWindowing}
            class="w-32"
          />
          <span class="text-sm w-12">{windowCenter}</span>
        </label>
        <label class="flex items-center gap-2">
          <span class="text-sm">W/W:</span>
          <input
            type="range"
            min="1"
            max="2000"
            bind:value={windowWidth}
            on:change={applyWindowing}
            class="w-32"
          />
          <span class="text-sm w-12">{windowWidth}</span>
        </label>
      </div>
    </div>
  </div>

  <!-- Tag Panel -->
  <div class="w-80 bg-gray-700 p-4 overflow-y-auto">
    <h2 class="text-lg font-semibold mb-4">DICOM Tags</h2>
    {#if $activeStudyStore.tags && $activeStudyStore.tags.length > 0}
      <div class="space-y-1 text-xs font-mono">
        {#each $activeStudyStore.tags as tag}
          <div class="flex justify-between gap-2 py-1 border-b border-gray-600 hover:bg-gray-600">
            <span class="text-blue-300">{tag.tag}</span>
            <span class="text-gray-400 truncate flex-1">{tag.name}</span>
            <span class="text-green-300 text-right">{tag.value}</span>
          </div>
        {/each}
      </div>
    {:else}
      <p class="text-gray-400 text-sm">No tags loaded</p>
    {/if}
  </div>
</div>
