<script>
  import { activeStudyStore } from '../stores/activeStudyStore';
  import { invoke } from '@tauri-apps/api/core';

  let windowCenter = 128;
  let windowWidth = 256;

  async function applyWindowing() {
    // TODO: Call Tauri command to apply windowing
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
    <div class="flex-1 bg-black flex items-center justify-center">
      {#if $activeStudyStore.currentImageData}
        <img src={$activeStudyStore.currentImageData} alt="DICOM" class="max-w-full max-h-full" />
      {:else}
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
