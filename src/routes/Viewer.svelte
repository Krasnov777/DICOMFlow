<script>
  import { activeStudyStore } from '../stores/activeStudyStore';
  import { startLoading, finishLoading, setError } from '../stores/loadingStore';
  import { invoke } from '@tauri-apps/api/core';
  import { save } from '@tauri-apps/plugin-dialog';

  let windowCenter = $activeStudyStore.windowCenter || 128;
  let windowWidth = $activeStudyStore.windowWidth || 256;
  let isLoading = false;
  let loadError = null;
  let currentLoadingPath = null; // Track what's currently loading to prevent duplicates

  // Load image when file path changes
  $: if ($activeStudyStore.currentFilePath && $activeStudyStore.currentFilePath !== currentLoadingPath && !isLoading) {
    console.log('File path changed, loading image:', $activeStudyStore.currentFilePath);
    loadImage();
  }

  async function loadImage() {
    if (!$activeStudyStore.currentFilePath) {
      console.log('No file path, skipping image load');
      return;
    }

    // Prevent multiple simultaneous loads
    if (isLoading) {
      console.log('Already loading, skipping duplicate request');
      return;
    }

    const pathToLoad = $activeStudyStore.currentFilePath;
    currentLoadingPath = pathToLoad;

    console.log('Starting image load for:', pathToLoad);
    isLoading = true;
    loadError = null;

    const startTime = performance.now();
    startLoading('Loading image metadata...');

    try {
      // Get metadata to retrieve default windowing
      console.log('Getting metadata...');
      const metadataStart = performance.now();
      const metadata = await invoke('get_metadata', {
        filePath: pathToLoad
      });
      console.log(`Metadata received in ${(performance.now() - metadataStart).toFixed(0)}ms:`, metadata);

      // Update windowing from metadata if available
      if (metadata.window_center && metadata.window_width) {
        windowCenter = metadata.window_center;
        windowWidth = metadata.window_width;
        console.log('Using windowing from metadata:', windowCenter, windowWidth);
        activeStudyStore.update(store => ({
          ...store,
          windowCenter: metadata.window_center,
          windowWidth: metadata.window_width
        }));
      }

      // Load image with default or current windowing
      startLoading('Decoding pixel data...');
      console.log('Getting image data with windowing:', windowCenter, windowWidth);
      const imageStart = performance.now();
      const base64Png = await invoke('get_image_data', {
        filePath: pathToLoad,
        windowCenter: windowCenter,
        windowWidth: windowWidth
      });
      console.log(`Image data received in ${(performance.now() - imageStart).toFixed(0)}ms, base64 length:`, base64Png.length);

      // Update store with image data
      activeStudyStore.update(store => ({
        ...store,
        currentImageData: `data:image/png;base64,${base64Png}`
      }));

      const totalTime = (performance.now() - startTime).toFixed(0);
      console.log(`Image loaded successfully in ${totalTime}ms total`);

      finishLoading(`Image loaded (${totalTime}ms)`);
    } catch (error) {
      console.error('Failed to load image:', error);
      loadError = error.toString();
      setError(`Failed to load image: ${error}`);
      currentLoadingPath = null; // Reset on error so user can retry
    } finally {
      isLoading = false;
    }
  }

  async function applyWindowing() {
    if (!$activeStudyStore.currentFilePath) return;

    isLoading = true;
    startLoading('Applying windowing...');
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

      finishLoading('Windowing applied');
    } catch (error) {
      console.error('Failed to apply windowing:', error);
      setError(`Failed to apply windowing: ${error}`);
    } finally {
      isLoading = false;
    }
  }

  async function exportPNG() {
    if (!$activeStudyStore.currentFilePath) {
      setError('No image loaded');
      return;
    }

    try {
      const outputPath = await save({
        defaultPath: 'image.png',
        filters: [{
          name: 'PNG Image',
          extensions: ['png']
        }]
      });

      if (!outputPath) return;

      startLoading('Exporting PNG...');

      await invoke('export_image_png', {
        filePath: $activeStudyStore.currentFilePath,
        outputPath,
        windowCenter,
        windowWidth
      });

      finishLoading(`Exported to ${outputPath.split('/').pop()}`);
    } catch (error) {
      console.error('Export failed:', error);
      setError(`Export failed: ${error}`);
    }
  }

  async function loadInstance(seriesIndex, instanceIndex) {
    const series = $activeStudyStore.series[seriesIndex];
    if (!series || !series.instances[instanceIndex]) return;

    const instance = series.instances[instanceIndex];

    // Load tags for this instance
    const tags = await invoke('get_all_tags', { filePath: instance.path });

    activeStudyStore.update(store => ({
      ...store,
      currentSeriesIndex: seriesIndex,
      currentInstanceIndex: instanceIndex,
      currentFilePath: instance.path,
      tags: tags,
    }));
  }

  function nextInstance() {
    const currentSeries = $activeStudyStore.series[$activeStudyStore.currentSeriesIndex];
    if (!currentSeries) return;

    let nextIndex = $activeStudyStore.currentInstanceIndex + 1;
    let nextSeriesIndex = $activeStudyStore.currentSeriesIndex;

    // If we're at the end of this series, go to next series
    if (nextIndex >= currentSeries.instances.length) {
      nextSeriesIndex += 1;
      nextIndex = 0;
    }

    // Check if next series exists
    if (nextSeriesIndex < $activeStudyStore.series.length) {
      loadInstance(nextSeriesIndex, nextIndex);
    }
  }

  function previousInstance() {
    let prevIndex = $activeStudyStore.currentInstanceIndex - 1;
    let prevSeriesIndex = $activeStudyStore.currentSeriesIndex;

    // If we're at the beginning of this series, go to previous series
    if (prevIndex < 0) {
      prevSeriesIndex -= 1;
      if (prevSeriesIndex >= 0) {
        const prevSeries = $activeStudyStore.series[prevSeriesIndex];
        prevIndex = prevSeries.instances.length - 1;
      } else {
        return; // Already at first instance
      }
    }

    loadInstance(prevSeriesIndex, prevIndex);
  }
</script>

<div class="flex h-full">
  <!-- Study/Series Browser -->
  <div class="w-64 bg-gray-700 p-4 overflow-y-auto">
    <h2 class="text-lg font-semibold mb-4">Study Browser</h2>
    {#if $activeStudyStore.studyInstanceUID}
      <div class="space-y-4">
        <div class="space-y-2">
          <p class="text-sm"><strong>Patient:</strong> {$activeStudyStore.patientName || 'N/A'}</p>
          <p class="text-sm"><strong>ID:</strong> {$activeStudyStore.patientID || 'N/A'}</p>
          <p class="text-sm"><strong>Date:</strong> {$activeStudyStore.studyDate || 'N/A'}</p>
        </div>

        {#if $activeStudyStore.series && $activeStudyStore.series.length > 0}
          <div class="space-y-2">
            <h3 class="text-sm font-semibold">Series ({$activeStudyStore.series.length})</h3>
            {#each $activeStudyStore.series as series, seriesIndex}
              <div
                class="p-2 rounded text-xs cursor-pointer transition"
                class:bg-primary-600={seriesIndex === $activeStudyStore.currentSeriesIndex}
                class:bg-gray-600={seriesIndex !== $activeStudyStore.currentSeriesIndex}
                class:hover:bg-gray-500={seriesIndex !== $activeStudyStore.currentSeriesIndex}
                on:click={() => loadInstance(seriesIndex, 0)}
              >
                <div class="font-semibold">{series.modality || 'Unknown'}</div>
                <div class="text-gray-300">{series.instances.length} images</div>
              </div>
            {/each}
          </div>

          {#if $activeStudyStore.series[$activeStudyStore.currentSeriesIndex]}
            <div class="space-y-2">
              <h3 class="text-sm font-semibold">Instance</h3>
              <div class="text-xs">
                {$activeStudyStore.currentInstanceIndex + 1} / {$activeStudyStore.series[$activeStudyStore.currentSeriesIndex].instances.length}
              </div>
              <div class="flex gap-2">
                <button
                  on:click={previousInstance}
                  class="flex-1 px-2 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs"
                  disabled={$activeStudyStore.currentSeriesIndex === 0 && $activeStudyStore.currentInstanceIndex === 0}
                >
                  ← Prev
                </button>
                <button
                  on:click={nextInstance}
                  class="flex-1 px-2 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs"
                >
                  Next →
                </button>
              </div>
            </div>
          {/if}
        {/if}
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
          <div class="flex flex-col items-center gap-2">
            <svg class="animate-spin h-8 w-8 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            <div class="text-white">Loading image...</div>
          </div>
        </div>
      {/if}
      {#if loadError}
        <div class="text-center p-8">
          <p class="text-red-400 mb-2">Failed to load image</p>
          <p class="text-gray-500 text-sm">{loadError}</p>
        </div>
      {:else if $activeStudyStore.currentImageData}
        <div class="w-full h-full flex items-center justify-center relative">
          <img
            src={$activeStudyStore.currentImageData}
            alt="DICOM"
            class="max-w-full max-h-full"
            on:load={() => console.log('Image loaded successfully!')}
            on:error={(e) => console.error('Image failed to load:', e, 'src length:', $activeStudyStore.currentImageData?.length)}
          />
          <div class="absolute bottom-2 left-2 bg-black bg-opacity-50 text-white text-xs p-2 rounded">
            Data length: {$activeStudyStore.currentImageData?.length || 0}
          </div>
        </div>
      {:else if !isLoading}
        <p class="text-gray-500">No image loaded. Use "Open File" or "Open Directory" to load DICOM files.</p>
      {/if}
    </div>

    <!-- Windowing Controls -->
    <div class="bg-gray-700 p-4 space-y-2">
      <div class="flex items-center justify-between gap-4">
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
        <button
          on:click={exportPNG}
          class="px-4 py-2 bg-primary-600 hover:bg-primary-700 rounded text-sm transition"
          disabled={!$activeStudyStore.currentImageData}
        >
          Export PNG
        </button>
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
