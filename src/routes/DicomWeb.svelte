<script>
  import { requestHistoryStore } from '../stores/requestHistoryStore';

  let endpoint = '';
  let method = 'QIDO-RS';
  let queryParams = '';
  let headers = '';
  let response = null;

  async function executeRequest() {
    // TODO: Call Tauri command to execute DICOMweb request
    response = {
      status: 200,
      body: JSON.stringify({ message: 'Placeholder response' }, null, 2),
    };
  }
</script>

<div class="h-full flex flex-col">
  <div class="p-6 border-b border-gray-700">
    <h1 class="text-3xl font-bold">DICOMweb Testing</h1>
  </div>

  <div class="flex-1 flex overflow-hidden">
    <!-- Request Builder -->
    <div class="flex-1 p-6 overflow-y-auto">
      <h2 class="text-xl font-semibold mb-4">Request Builder</h2>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium mb-1">Method</label>
          <select bind:value={method} class="w-full bg-gray-700 rounded px-3 py-2">
            <option>QIDO-RS</option>
            <option>WADO-RS</option>
            <option>STOW-RS</option>
          </select>
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Endpoint URL</label>
          <input
            type="text"
            bind:value={endpoint}
            placeholder="https://dicomserver.com/dicomweb"
            class="w-full bg-gray-700 rounded px-3 py-2"
          />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Query Parameters</label>
          <textarea
            bind:value={queryParams}
            placeholder="PatientName=*&StudyDate=20240101-"
            class="w-full bg-gray-700 rounded px-3 py-2 h-24"
          />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Headers (JSON)</label>
          <textarea
            bind:value={headers}
            placeholder='{{"Authorization": "Bearer token"}}'
            class="w-full bg-gray-700 rounded px-3 py-2 h-24"
          />
        </div>

        <button
          on:click={executeRequest}
          class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition"
        >
          Send Request
        </button>
      </div>

      <!-- Response Viewer -->
      {#if response}
        <div class="mt-6">
          <h2 class="text-xl font-semibold mb-2">Response</h2>
          <div class="bg-gray-700 rounded p-4">
            <p class="text-sm mb-2">
              Status: <span class="text-green-400">{response.status}</span>
            </p>
            <pre class="text-xs overflow-x-auto">{response.body}</pre>
          </div>
        </div>
      {/if}
    </div>

    <!-- Request History -->
    <div class="w-80 bg-gray-700 p-4 overflow-y-auto">
      <h2 class="text-lg font-semibold mb-4">Request History</h2>
      {#if $requestHistoryStore.requests.length > 0}
        <ul class="space-y-2">
          {#each $requestHistoryStore.requests as req}
            <li class="bg-gray-800 p-2 rounded text-xs">
              <div class="font-semibold">{req.method}</div>
              <div class="text-gray-400 truncate">{req.endpoint}</div>
            </li>
          {/each}
        </ul>
      {:else}
        <p class="text-gray-400 text-sm">No history yet</p>
      {/if}
    </div>
  </div>
</div>
