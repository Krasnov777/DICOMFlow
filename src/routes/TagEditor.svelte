<script>
  import { tagEditorStore } from '../stores/tagEditorStore';
  import { activeStudyStore } from '../stores/activeStudyStore';
  import { invoke } from '@tauri-apps/api/core';
  import { save } from '@tauri-apps/plugin-dialog';

  let searchQuery = '';
  let anonymizationTemplate = 'Basic';
  let templates = [];
  let editingTag = null;
  let editValue = '';
  let filteredTags = [];
  let isAnonymizing = false;

  $: {
    // Filter tags based on search query
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filteredTags = $activeStudyStore.tags.filter(tag =>
        tag.tag.toLowerCase().includes(query) ||
        tag.name.toLowerCase().includes(query) ||
        tag.value.toLowerCase().includes(query)
      );
    } else {
      filteredTags = $activeStudyStore.tags;
    }
  }

  // Load anonymization templates
  async function loadTemplates() {
    try {
      templates = await invoke('get_anonymization_templates');
      console.log('Loaded templates:', templates);
    } catch (error) {
      console.error('Failed to load templates:', error);
    }
  }

  loadTemplates();

  function handleSearch() {
    // Filtering is reactive, no action needed
  }

  function startEdit(tag) {
    editingTag = tag;
    editValue = tag.value;
  }

  function cancelEdit() {
    editingTag = null;
    editValue = '';
  }

  async function saveEdit() {
    if (!editingTag || !$activeStudyStore.currentFilePath) return;

    try {
      await invoke('update_tag', {
        filePath: $activeStudyStore.currentFilePath,
        tag: editingTag.tag,
        value: editValue
      });

      // Update local tag value
      const tagIndex = $activeStudyStore.tags.findIndex(t => t.tag === editingTag.tag);
      if (tagIndex !== -1) {
        activeStudyStore.update(store => {
          const newTags = [...store.tags];
          newTags[tagIndex] = { ...newTags[tagIndex], value: editValue };
          return { ...store, tags: newTags };
        });
      }

      alert('Tag updated successfully');
      cancelEdit();
    } catch (error) {
      console.error('Failed to update tag:', error);
      alert(`Failed to update tag: ${error}`);
    }
  }

  async function deleteTag(tag) {
    if (!$activeStudyStore.currentFilePath) return;
    if (!confirm(`Delete tag ${tag.tag}?`)) return;

    try {
      await invoke('delete_tag', {
        filePath: $activeStudyStore.currentFilePath,
        tag: tag.tag
      });

      // Remove tag from local store
      activeStudyStore.update(store => ({
        ...store,
        tags: store.tags.filter(t => t.tag !== tag.tag)
      }));

      alert('Tag deleted successfully');
    } catch (error) {
      console.error('Failed to delete tag:', error);
      alert(`Failed to delete tag: ${error}`);
    }
  }

  async function handleAnonymize() {
    if (!$activeStudyStore.currentFilePath) {
      alert('No file loaded');
      return;
    }

    isAnonymizing = true;

    try {
      const anonymizedPaths = await invoke('anonymize_study', {
        filePaths: [$activeStudyStore.currentFilePath],
        templateName: anonymizationTemplate
      });

      alert(`Anonymized file created: ${anonymizedPaths[0]}`);
    } catch (error) {
      console.error('Anonymization failed:', error);
      alert(`Anonymization failed: ${error}`);
    } finally {
      isAnonymizing = false;
    }
  }

  async function handleExport(format) {
    if (!$activeStudyStore.currentFilePath) {
      alert('No file loaded');
      return;
    }

    try {
      const outputPath = await save({
        defaultPath: `tags.${format}`,
        filters: [{
          name: format.toUpperCase(),
          extensions: [format]
        }]
      });

      if (!outputPath) return;

      if (format === 'json') {
        await invoke('export_tags_json', {
          filePath: $activeStudyStore.currentFilePath,
          outputPath
        });
      } else if (format === 'xml') {
        await invoke('export_tags_xml', {
          filePath: $activeStudyStore.currentFilePath,
          outputPath
        });
      }

      alert(`Tags exported to ${outputPath}`);
    } catch (error) {
      console.error('Export failed:', error);
      alert(`Export failed: ${error}`);
    }
  }

  async function deletePrivateTags() {
    if (!$activeStudyStore.currentFilePath) return;
    if (!confirm('Delete all private tags? This cannot be undone.')) return;

    // Filter and delete all private tags
    const privateTags = $activeStudyStore.tags.filter(t => t.is_private);

    for (const tag of privateTags) {
      try {
        await invoke('delete_tag', {
          filePath: $activeStudyStore.currentFilePath,
          tag: tag.tag
        });
      } catch (error) {
        console.error(`Failed to delete ${tag.tag}:`, error);
      }
    }

    // Update local store
    activeStudyStore.update(store => ({
      ...store,
      tags: store.tags.filter(t => !t.is_private)
    }));

    alert(`Deleted ${privateTags.length} private tags`);
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
      <button
        on:click={deletePrivateTags}
        class="px-4 py-2 bg-gray-600 hover:bg-gray-500 rounded text-sm transition"
      >
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
          {#if filteredTags.length > 0}
            {#each filteredTags as tag}
              <tr class="border-t border-gray-700 hover:bg-gray-700">
                <td class="p-2 font-mono text-xs">{tag.tag}</td>
                <td class="p-2">{tag.name}</td>
                <td class="p-2 font-mono text-xs">{tag.vr}</td>
                <td class="p-2 max-w-md">
                  {#if editingTag === tag}
                    <input
                      type="text"
                      bind:value={editValue}
                      class="bg-gray-600 rounded px-2 py-1 w-full text-sm"
                      autofocus
                    />
                  {:else}
                    <span class="truncate block">{tag.value}</span>
                  {/if}
                </td>
                <td class="p-2">
                  {#if editingTag === tag}
                    <button
                      on:click={saveEdit}
                      class="text-green-400 hover:text-green-300 text-xs mr-2"
                    >
                      Save
                    </button>
                    <button
                      on:click={cancelEdit}
                      class="text-red-400 hover:text-red-300 text-xs"
                    >
                      Cancel
                    </button>
                  {:else}
                    <button
                      on:click={() => startEdit(tag)}
                      class="text-primary-400 hover:text-primary-300 text-xs mr-2"
                    >
                      Edit
                    </button>
                    <button
                      on:click={() => deleteTag(tag)}
                      class="text-red-400 hover:text-red-300 text-xs"
                    >
                      Delete
                    </button>
                  {/if}
                </td>
              </tr>
            {/each}
          {:else}
            <tr>
              <td colspan="5" class="p-4 text-center text-gray-400">
                {#if searchQuery}
                  No tags match your search
                {:else}
                  No tags loaded
                {/if}
              </td>
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
            {#each templates as template}
              <option value={template.name}>{template.name}</option>
            {/each}
          </select>
        </div>

        <button
          on:click={handleAnonymize}
          disabled={isAnonymizing}
          class="w-full bg-primary-600 hover:bg-primary-700 py-2 rounded transition disabled:bg-gray-500 disabled:cursor-not-allowed"
        >
          {isAnonymizing ? 'Anonymizing...' : 'Anonymize'}
        </button>

        <div class="text-xs text-gray-300 space-y-1">
          {#each templates as template}
            <p><strong>{template.name}:</strong> {template.description}</p>
          {/each}
        </div>
      </div>
    </div>
  </div>
</div>
