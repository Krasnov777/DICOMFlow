<script>
  import { connectionStore } from '../stores/connectionStore';
  import { invoke } from '@tauri-apps/api/core';

  let activeTab = 'scp';
  let scpPort = 11112;
  let scpAeTitle = 'DICOM_TOOLKIT';

  // SCU variables
  let pacsEndpoints = [
    {
      name: 'Local Test PACS',
      ae_title: 'TESTPACS',
      host: 'localhost',
      port: 11112,
      our_ae_title: 'DICOMFLOW'
    }
  ];
  let selectedEndpointIndex = 0;
  let queryPatientName = '';
  let queryPatientId = '';
  let queryStudyDate = '';
  let queryModality = '';
  let queryResults = [];
  let isQuerying = false;
  let echoStatus = '';

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

  async function testConnection() {
    if (pacsEndpoints.length === 0) return;

    const endpoint = pacsEndpoints[selectedEndpointIndex];
    echoStatus = 'Testing connection...';

    try {
      const result = await invoke('c_echo', { endpoint });
      echoStatus = result ? '✓ Connection successful!' : '✗ Connection failed';
    } catch (error) {
      console.error('C-ECHO failed:', error);
      echoStatus = `✗ Error: ${error}`;
    }
  }

  async function searchPacs() {
    if (pacsEndpoints.length === 0) return;

    const endpoint = pacsEndpoints[selectedEndpointIndex];
    isQuerying = true;
    queryResults = [];

    try {
      const params = {
        patient_name: queryPatientName || null,
        patient_id: queryPatientId || null,
        study_date: queryStudyDate || null,
        modality: queryModality || null,
        accession_number: null
      };

      const results = await invoke('c_find', { endpoint, params });
      queryResults = results;
    } catch (error) {
      console.error('C-FIND failed:', error);
      alert(`Search failed: ${error}`);
    } finally {
      isQuerying = false;
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
          <select bind:value={selectedEndpointIndex} class="w-full bg-gray-700 rounded px-3 py-2">
            {#each pacsEndpoints as endpoint, i}
              <option value={i}>{endpoint.name} ({endpoint.host}:{endpoint.port})</option>
            {/each}
          </select>
        </div>

        <div class="flex gap-2">
          <button
            on:click={testConnection}
            class="flex-1 bg-blue-600 hover:bg-blue-700 py-2 rounded transition"
          >
            Test Connection (C-ECHO)
          </button>
        </div>

        {#if echoStatus}
          <div class="p-3 rounded {echoStatus.includes('✓') ? 'bg-green-600/20 text-green-300' : 'bg-red-600/20 text-red-300'}">
            {echoStatus}
          </div>
        {/if}

        <hr class="border-gray-600" />

        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium mb-1">Patient Name</label>
            <input
              type="text"
              bind:value={queryPatientName}
              placeholder="e.g., Doe^John"
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">Patient ID</label>
            <input
              type="text"
              bind:value={queryPatientId}
              placeholder="e.g., 12345"
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">Study Date</label>
            <input
              type="text"
              bind:value={queryStudyDate}
              placeholder="YYYYMMDD"
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
          <div>
            <label class="block text-sm font-medium mb-1">Modality</label>
            <input
              type="text"
              bind:value={queryModality}
              placeholder="e.g., CT, MR"
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          </div>
        </div>

        <button
          on:click={searchPacs}
          disabled={isQuerying}
          class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition disabled:opacity-50"
        >
          {isQuerying ? 'Searching...' : 'Search (C-FIND)'}
        </button>

        <!-- Results -->
        <div class="mt-6">
          <h3 class="text-lg font-semibold mb-2">
            Results {queryResults.length > 0 ? `(${queryResults.length})` : ''}
          </h3>
          <div class="bg-gray-700 rounded p-4 max-h-96 overflow-y-auto">
            {#if queryResults.length > 0}
              <div class="space-y-3">
                {#each queryResults as result}
                  <div class="border border-gray-600 rounded p-3 hover:bg-gray-600 transition">
                    <div class="flex justify-between items-start mb-2">
                      <div>
                        <p class="font-semibold">{result.patient_name}</p>
                        <p class="text-sm text-gray-400">ID: {result.patient_id}</p>
                      </div>
                      <span class="text-xs bg-blue-600 px-2 py-1 rounded">{result.modality}</span>
                    </div>
                    <p class="text-sm">{result.study_description}</p>
                    <p class="text-xs text-gray-400 mt-1">
                      Date: {result.study_date} |
                      Series: {result.number_of_series} |
                      Instances: {result.number_of_instances}
                    </p>
                  </div>
                {/each}
              </div>
            {:else}
              <p class="text-gray-400 text-sm">No results yet. Run a search to find studies.</p>
            {/if}
          </div>
        </div>
      </div>
    {/if}
  </div>
</div>
