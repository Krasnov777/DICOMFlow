<script>
  import { tagEditorStore } from '../stores/tagEditorStore';

  let searchQuery = '';
  let anonymizationTemplate = 'basic';

  function handleSearch() {
    tagEditorStore.update(store => ({ ...store, searchQuery }));
  }

  async function handleAnonymize() {
    // TODO: Call Tauri command to anonymize
  }

  async function handleExport(format) {
    // TODO: Call Tauri command to export tags
  }
</script>

<div class="h-full flex flex-col">
  <div class="p-6 border-b border-gray-700">
    <h1 class="text-3xl font-bold">Tag Editor</h1>
  </div>

  <!-- Toolbar -->
  <div class="p-4 border-b border-gray-700 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <input
        type="text"
        bind:value={searchQuery}
        on:input={handleSearch}
        placeholder="Search tags..."
        class="bg-gray-700 rounded px-3 py-2 w-64"
      />
      <button class="px-4 py-2 bg-gray-600 hover:bg-gray-500 rounded text-sm transition">
        Delete Private Tags
      </button>
    </div>

    <div class="flex items-center gap-3">
      <button
        on:click={() => handleExport('json')}
        class="px-4 py-2 bg-gray-600 hover:bg-gray-500 rounded text-sm transition"
      >
        Export JSON
      </button>
      <button
        on:click={() => handleExport('xml')}
        class="px-4 py-2 bg-gray-600 hover:bg-gray-500 rounded text-sm transition"
      >
        Export XML
      </button>
    </div>
  </div>

  <div class="flex-1 flex overflow-hidden">
    <!-- Tag Table -->
    <div class="flex-1 p-6 overflow-y-auto">
      <table class="w-full text-sm">
        <thead class="bg-gray-700 sticky top-0">
          <tr>
            <th class="p-2 text-left">Tag</th>
            <th class="p-2 text-left">Name</th>
            <th class="p-2 text-left">VR</th>
            <th class="p-2 text-left">Value</th>
            <th class="p-2 text-left">Actions</th>
          </tr>
        </thead>
        <tbody>
          {#if $tagEditorStore.tags.length > 0}
            {#each $tagEditorStore.tags as tag}
              <tr class="border-t border-gray-700 hover:bg-gray-700">
                <td class="p-2 font-mono text-xs">{tag.tag}</td>
                <td class="p-2">{tag.name}</td>
                <td class="p-2 font-mono text-xs">{tag.vr}</td>
                <td class="p-2 truncate max-w-md">{tag.value}</td>
                <td class="p-2">
                  <button class="text-primary-400 hover:text-primary-300 text-xs">Edit</button>
                </td>
              </tr>
            {/each}
          {:else}
            <tr>
              <td colspan="5" class="p-4 text-center text-gray-400">No tags loaded</td>
            </tr>
          {/if}
        </tbody>
      </table>
    </div>

    <!-- Anonymization Panel -->
    <div class="w-80 bg-gray-700 p-4 overflow-y-auto">
      <h2 class="text-lg font-semibold mb-4">Anonymization</h2>

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium mb-1">Template</label>
          <select bind:value={anonymizationTemplate} class="w-full bg-gray-600 rounded px-3 py-2">
            <option value="basic">Basic</option>
            <option value="full">Full</option>
            <option value="research">Research-Safe</option>
          </select>
        </div>

        <button
          on:click={handleAnonymize}
          class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition"
        >
          Anonymize
        </button>

        <div class="text-xs text-gray-300 space-y-1">
          <p><strong>Basic:</strong> Removes patient identifiers</p>
          <p><strong>Full:</strong> Comprehensive anonymization</p>
          <p><strong>Research:</strong> Preserves study relationships</p>
        </div>
      </div>
    </div>
  </div>
</div>
