<script>
  import { requestHistoryStore, addRequest } from '../stores/requestHistoryStore';
  import { invoke } from '@tauri-apps/api/core';

  let endpoint = 'http://localhost:8080/dicomweb';
  let method = 'QIDO-RS';
  let authType = 'None';
  let username = '';
  let password = '';
  let bearerToken = '';

  // QIDO-RS fields
  let patientName = '';
  let patientId = '';
  let studyDate = '';
  let queryLevel = 'Studies';

  // WADO-RS fields
  let studyUid = '';
  let seriesUid = '';
  let instanceUid = '';

  let response = null;
  let isLoading = false;

  async function executeRequest() {
    isLoading = true;
    response = null;

    try {
      // Build endpoint object
      const dicomwebEndpoint = {
        name: 'User Endpoint',
        base_url: endpoint,
        auth_type: buildAuthType(),
        headers: {}
      };

      let result;

      if (method === 'QIDO-RS') {
        // Build query parameters
        const params = {};
        if (patientName) params['00100010'] = patientName; // Patient Name
        if (patientId) params['00100020'] = patientId; // Patient ID
        if (studyDate) params['00080020'] = studyDate; // Study Date

        const query = {
          level: queryLevel,
          params,
          limit: 100,
          offset: null
        };

        result = await invoke('qido_rs', { endpoint: dicomwebEndpoint, query });
        response = {
          status: 200,
          body: JSON.stringify(result, null, 2)
        };
      } else if (method === 'WADO-RS') {
        if (!studyUid || !seriesUid || !instanceUid) {
          throw new Error('Study UID, Series UID, and Instance UID are required for WADO-RS');
        }

        result = await invoke('wado_rs', {
          endpoint: dicomwebEndpoint,
          studyUid,
          seriesUid,
          instanceUid
        });

        response = {
          status: 200,
          body: `Retrieved instance (base64 length: ${result.length} characters)`
        };
      } else if (method === 'STOW-RS') {
        response = {
          status: 200,
          body: 'STOW-RS requires file selection (not yet implemented in UI)'
        };
      }

      // Add to history
      addRequest({
        method,
        endpoint,
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      console.error('DICOMweb request failed:', error);
      response = {
        status: 500,
        body: `Error: ${error}`
      };
    } finally {
      isLoading = false;
    }
  }

  function buildAuthType() {
    if (authType === 'Basic') {
      return { Basic: { username, password } };
    } else if (authType === 'Bearer') {
      return { Bearer: { token: bearerToken } };
    } else {
      return 'None';
    }
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
            placeholder="http://localhost:8080/dicomweb"
            class="w-full bg-gray-700 rounded px-3 py-2"
          />
        </div>

        <div>
          <label class="block text-sm font-medium mb-1">Authentication</label>
          <select bind:value={authType} class="w-full bg-gray-700 rounded px-3 py-2 mb-2">
            <option>None</option>
            <option>Basic</option>
            <option>Bearer</option>
          </select>

          {#if authType === 'Basic'}
            <div class="grid grid-cols-2 gap-2">
              <input
                type="text"
                bind:value={username}
                placeholder="Username"
                class="bg-gray-700 rounded px-3 py-2"
              />
              <input
                type="password"
                bind:value={password}
                placeholder="Password"
                class="bg-gray-700 rounded px-3 py-2"
              />
            </div>
          {:else if authType === 'Bearer'}
            <input
              type="text"
              bind:value={bearerToken}
              placeholder="Bearer Token"
              class="w-full bg-gray-700 rounded px-3 py-2"
            />
          {/if}
        </div>

        <hr class="border-gray-600" />

        {#if method === 'QIDO-RS'}
          <div>
            <label class="block text-sm font-medium mb-1">Query Level</label>
            <select bind:value={queryLevel} class="w-full bg-gray-700 rounded px-3 py-2">
              <option>Studies</option>
              <option>Series</option>
              <option>Instances</option>
            </select>
          </div>

          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="block text-sm font-medium mb-1">Patient Name</label>
              <input
                type="text"
                bind:value={patientName}
                placeholder="Doe^John or *"
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Patient ID</label>
              <input
                type="text"
                bind:value={patientId}
                placeholder="12345"
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Study Date</label>
              <input
                type="text"
                bind:value={studyDate}
                placeholder="20240101-20241231"
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
          </div>
        {:else if method === 'WADO-RS'}
          <div class="space-y-3">
            <div>
              <label class="block text-sm font-medium mb-1">Study Instance UID</label>
              <input
                type="text"
                bind:value={studyUid}
                placeholder="1.2.840.113..."
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">Series Instance UID</label>
              <input
                type="text"
                bind:value={seriesUid}
                placeholder="1.2.840.113..."
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
            <div>
              <label class="block text-sm font-medium mb-1">SOP Instance UID</label>
              <input
                type="text"
                bind:value={instanceUid}
                placeholder="1.2.840.113..."
                class="w-full bg-gray-700 rounded px-3 py-2"
              />
            </div>
          </div>
        {:else if method === 'STOW-RS'}
          <div class="bg-yellow-600/20 border border-yellow-600 rounded p-3">
            <p class="text-sm text-yellow-300">
              STOW-RS file upload UI coming soon. Use file selection dialog to upload DICOM files.
            </p>
          </div>
        {/if}

        <button
          on:click={executeRequest}
          disabled={isLoading}
          class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition disabled:opacity-50"
        >
          {isLoading ? 'Sending...' : 'Send Request'}
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
