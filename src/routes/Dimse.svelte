<script>
  import { connectionStore } from '../stores/connectionStore';
  import { invoke } from '@tauri-apps/api/core';

  let activeTab = 'scp';
  let scpPort = 11112;
  let scpAeTitle = 'DICOM_TOOLKIT';

  async function startScp() {
    try {
      await invoke('start_scp', { port: scpPort, aeTitle: scpAeTitle });
      connectionStore.update(store => ({ ...store, scpRunning: true }));
    } catch (error) {
      console.error('Failed to start SCP:', error);
    }
  }

  async function stopScp() {
    try {
      await invoke('stop_scp');
      connectionStore.update(store => ({ ...store, scpRunning: false }));
    } catch (error) {
      console.error('Failed to stop SCP:', error);
    }
  }
</script>

<div class="h-full flex flex-col">
  <div class="p-6 border-b border-gray-700">
    <h1 class="text-3xl font-bold">DIMSE Operations</h1>
  </div>

  <!-- Tabs -->
  <div class="flex border-b border-gray-700">
    <button
      on:click={() => activeTab = 'scp'}
      class="px-6 py-3 {activeTab === 'scp' ? 'border-b-2 border-primary-500 text-primary-400' : 'text-gray-400'}"
    >
      SCP (Receiving)
    </button>
    <button
      on:click={() => activeTab = 'scu'}
      class="px-6 py-3 {activeTab === 'scu' ? 'border-b-2 border-primary-500 text-primary-400' : 'text-gray-400'}"
    >
      SCU (Query/Retrieve)
    </button>
  </div>

  <div class="flex-1 p-6 overflow-y-auto">
    {#if activeTab === 'scp'}
      <!-- SCP Panel -->
      <div class="space-y-4">
        <h2 class="text-xl font-semibold">SCP Configuration</h2>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium mb-1">AE Title</label>
            <input
              type="text"
              bind:value={scpAeTitle}
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">Port</label>
            <input
              type="number"
              bind:value={scpPort}
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
        </div>

        <div class="flex gap-3">
          {#if $connectionStore.scpRunning}
            <button
              on:click={stopScp}
              class="px-6 py-2 bg-red-600 hover:bg-red-700 rounded transition"
            >
              Stop Listener
            </button>
          {:else}
            <button
              on:click={startScp}
              class="px-6 py-2 bg-green-600 hover:bg-green-700 rounded transition"
            >
              Start Listener
            </button>
          {/if}
        </div>

        <!-- Incoming Connections Log -->
        <div class="mt-6">
          <h3 class="text-lg font-semibold mb-2">Incoming Connections</h3>
          <div class="bg-gray-700 rounded p-4 h-64 overflow-y-auto">
            <p class="text-gray-400 text-sm">No connections yet</p>
          </div>
        </div>
      </div>
    {:else}
      <!-- SCU Panel -->
      <div class="space-y-4">
        <h2 class="text-xl font-semibold">Query PACS</h2>

        <div>
          <label class="block text-sm font-medium mb-1">PACS Endpoint</label>
          <select class="w-full bg-gray-700 rounded px-3 py-2">
            <option>Select endpoint...</option>
          </select>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium mb-1">Patient Name</label>
            <input type="text" class="w-full bg-gray-700 rounded px-3 py-2" />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">Patient ID</label>
            <input type="text" class="w-full bg-gray-700 rounded px-3 py-2" />
          </div>
        </div>

        <button class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition">
          Search
        </button>

        <!-- Results -->
        <div class="mt-6">
          <h3 class="text-lg font-semibold mb-2">Results</h3>
          <div class="bg-gray-700 rounded p-4">
            <p class="text-gray-400 text-sm">No results</p>
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>
