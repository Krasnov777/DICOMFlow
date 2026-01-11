<script>
  import { settingsStore } from '../../stores/settingsStore';

  let diskUsage = '0 MB';
  let activeTasks = 0;
  let lastLogMessage = '';
</script>

<footer class="h-8 bg-gray-900 border-t border-gray-700 flex items-center justify-between px-6 text-xs text-gray-400">
  <div class="flex items-center gap-6">
    <span>Tasks: {activeTasks}</span>
    <span>Storage: {diskUsage}</span>
    {#if $settingsStore.workspaceMode}
      <span class="text-green-400">Workspace Mode</span>
    {:else}
      <span class="text-yellow-400">Ephemeral Mode</span>
    {/if}
  </div>

  <div class="flex items-center gap-4">
    {#if lastLogMessage}
      <span class="truncate max-w-md">{lastLogMessage}</span>
    {/if}
  </div>
</footer>
