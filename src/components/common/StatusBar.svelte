<script>
  import { settingsStore } from '../../stores/settingsStore';
  import { loadingStore } from '../../stores/loadingStore';
</script>

<footer class="h-8 bg-gray-900 border-t border-gray-700 flex items-center justify-between px-6 text-xs relative">
  <!-- Progress bar -->
  {#if $loadingStore.isLoading && $loadingStore.progress >= 0}
    <div class="absolute bottom-0 left-0 h-1 bg-primary-600 transition-all duration-300" style="width: {$loadingStore.progress}%"></div>
  {:else if $loadingStore.isLoading}
    <div class="absolute bottom-0 left-0 h-1 bg-primary-600 animate-pulse w-full"></div>
  {/if}

  <div class="flex items-center gap-6 text-gray-400">
    {#if $settingsStore.workspaceMode}
      <span class="text-green-400">Workspace Mode</span>
    {:else}
      <span class="text-yellow-400">Ephemeral Mode</span>
    {/if}
  </div>

  <div class="flex items-center gap-4">
    {#if $loadingStore.isLoading}
      <div class="flex items-center gap-2 text-primary-400">
        <svg class="animate-spin h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span>{$loadingStore.currentOperation}</span>
        {#if $loadingStore.progress >= 0}
          <span class="text-gray-400">({$loadingStore.progress}%)</span>
        {/if}
      </div>
    {:else if $loadingStore.message}
      <span class="truncate max-w-md" class:text-red-400={$loadingStore.message.startsWith('Error')} class:text-green-400={!$loadingStore.message.startsWith('Error')}>
        {$loadingStore.message}
      </span>
    {:else}
      <span class="text-gray-500">Ready</span>
    {/if}
  </div>
</footer>
