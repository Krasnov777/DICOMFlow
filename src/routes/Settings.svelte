<script>
  import { settingsStore } from '../stores/settingsStore';

  let workspaceMode = $settingsStore.workspaceMode;
  let autoClearCache = $settingsStore.autoClearCache;
  let maxDiskUsage = $settingsStore.maxDiskUsage / (1024 * 1024 * 1024); // Convert to GB

  function saveSettings() {
    settingsStore.update(store => ({
      ...store,
      workspaceMode,
      autoClearCache,
      maxDiskUsage: maxDiskUsage * 1024 * 1024 * 1024,
    }));
    // TODO: Call Tauri command to persist settings
  }
</script>

<div class="h-full overflow-y-auto">
  <div class="p-6 border-b border-gray-700">
    <h1 class="text-3xl font-bold">Settings</h1>
  </div>

  <div class="p-6 max-w-3xl space-y-8">
    <!-- General Settings -->
    <section>
      <h2 class="text-xl font-semibold mb-4">General</h2>
      <div class="space-y-4">
        <label class="flex items-center gap-3">
          <input
            type="checkbox"
            bind:checked={workspaceMode}
            class="w-4 h-4"
          />
          <div>
            <div class="font-medium">Workspace Mode</div>
            <div class="text-sm text-gray-400">
              Persist studies and settings between sessions
            </div>
          </div>
        </label>

        <label class="flex items-center gap-3">
          <input
            type="checkbox"
            bind:checked={autoClearCache}
            class="w-4 h-4"
          />
          <div>
            <div class="font-medium">Auto Clear Cache</div>
            <div class="text-sm text-gray-400">
              Clear cached data on application exit
            </div>
          </div>
        </label>

        <div>
          <label class="block font-medium mb-2">
            Max Disk Usage (GB)
          </label>
          <input
            type="number"
            bind:value={maxDiskUsage}
            min="0.1"
            step="0.1"
            class="bg-gray-700 rounded px-3 py-2 w-32"
          />
          <p class="text-sm text-gray-400 mt-1">
            Maximum disk space for cached DICOM data
          </p>
        </div>
      </div>
    </section>

    <!-- Viewer Settings -->
    <section>
      <h2 class="text-xl font-semibold mb-4">Viewer</h2>
      <div class="space-y-4">
        <div>
          <label class="block font-medium mb-2">
            Thumbnail Size
          </label>
          <select class="bg-gray-700 rounded px-3 py-2">
            <option value="64">Small (64px)</option>
            <option value="128" selected>Medium (128px)</option>
            <option value="256">Large (256px)</option>
          </select>
        </div>

        <div>
          <label class="block font-medium mb-2">
            Image Interpolation
          </label>
          <select class="bg-gray-700 rounded px-3 py-2">
            <option value="nearest">Nearest Neighbor</option>
            <option value="bilinear" selected>Bilinear</option>
            <option value="bicubic">Bicubic</option>
          </select>
        </div>
      </div>
    </section>

    <!-- DIMSE Settings -->
    <section>
      <h2 class="text-xl font-semibold mb-4">DIMSE</h2>
      <div class="space-y-4">
        <div>
          <label class="block font-medium mb-2">
            Default AE Title
          </label>
          <input
            type="text"
            value="DICOM_TOOLKIT"
            class="bg-gray-700 rounded px-3 py-2 w-64"
          />
        </div>

        <div>
          <label class="block font-medium mb-2">
            Default Port
          </label>
          <input
            type="number"
            value="11112"
            class="bg-gray-700 rounded px-3 py-2 w-32"
          />
        </div>

        <div>
          <label class="block font-medium mb-2">
            Max PDU Size
          </label>
          <input
            type="number"
            value="16384"
            class="bg-gray-700 rounded px-3 py-2 w-32"
          />
        </div>
      </div>
    </section>

    <!-- Save Button -->
    <div class="pt-4 border-t border-gray-700">
      <button
        on:click={saveSettings}
        class="px-6 py-2 bg-primary-600 hover:bg-primary-700 rounded transition"
      >
        Save Settings
      </button>
    </div>
  </div>
</div>
