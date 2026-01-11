<script>
  import { connectionStore } from '../../stores/connectionStore';

  function handleOpenFile() {
    // TODO: Trigger file open dialog
  }

  function handleOpenDirectory() {
    // TODO: Trigger directory open dialog
  }
</script>

<header class="h-14 bg-gray-900 border-b border-gray-700 flex items-center justify-between px-6">
  <div class="flex items-center gap-4">
    <span class="text-sm text-gray-400">Connections:</span>
    {#if $connectionStore.scpRunning}
      <span class="px-2 py-1 bg-green-600 text-xs rounded">SCP Active</span>
    {/if}
    {#if $connectionStore.activeDicomWebEndpoint}
      <span class="px-2 py-1 bg-blue-600 text-xs rounded">
        DICOMweb: {$connectionStore.activeDicomWebEndpoint}
      </span>
    {/if}
  </div>

  <div class="flex items-center gap-3">
    <button
      on:click={handleOpenFile}
      class="px-4 py-2 bg-primary-600 hover:bg-primary-700 rounded text-sm transition"
    >
      Open File
    </button>
    <button
      on:click={handleOpenDirectory}
      class="px-4 py-2 bg-primary-600 hover:bg-primary-700 rounded text-sm transition"
    >
      Open Directory
    </button>
  </div>
</header>
