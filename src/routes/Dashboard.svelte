<script>
  import { connectionStore } from '../stores/connectionStore';
  import { onMount } from 'svelte';

  let recentStudies = [];
  let stats = {
    studiesLoaded: 0,
    tagsIndexed: 0,
    diskUsage: '0 MB',
  };

  onMount(async () => {
    // TODO: Load dashboard data
  });
</script>

<div class="p-6 space-y-6">
  <h1 class="text-3xl font-bold">Dashboard</h1>

  <!-- Connection Status Cards -->
  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
    <div class="bg-gray-700 p-6 rounded-lg">
      <h2 class="text-lg font-semibold mb-2">DIMSE Listener</h2>
      <div class="flex items-center gap-3">
        <div class="w-3 h-3 rounded-full {$connectionStore.scpRunning ? 'bg-green-500' : 'bg-red-500'}"></div>
        <span>{$connectionStore.scpRunning ? 'Running' : 'Stopped'}</span>
      </div>
      {#if $connectionStore.scpRunning}
        <p class="mt-2 text-sm text-gray-300">
          AE Title: {$connectionStore.scpConfig.aeTitle}<br>
          Port: {$connectionStore.scpConfig.port}
        </p>
      {/if}
    </div>

    <div class="bg-gray-700 p-6 rounded-lg">
      <h2 class="text-lg font-semibold mb-2">DICOMweb Endpoint</h2>
      {#if $connectionStore.activeDicomWebEndpoint}
        <p class="text-sm text-gray-300">{$connectionStore.activeDicomWebEndpoint}</p>
      {:else}
        <p class="text-sm text-gray-400">No active endpoint</p>
      {/if}
    </div>
  </div>

  <!-- Quick Stats -->
  <div class="grid grid-cols-3 gap-4">
    <div class="bg-gray-700 p-4 rounded-lg text-center">
      <div class="text-3xl font-bold text-primary-400">{stats.studiesLoaded}</div>
      <div class="text-sm text-gray-400">Studies Loaded</div>
    </div>
    <div class="bg-gray-700 p-4 rounded-lg text-center">
      <div class="text-3xl font-bold text-primary-400">{stats.tagsIndexed}</div>
      <div class="text-sm text-gray-400">Tags Indexed</div>
    </div>
    <div class="bg-gray-700 p-4 rounded-lg text-center">
      <div class="text-3xl font-bold text-primary-400">{stats.diskUsage}</div>
      <div class="text-sm text-gray-400">Disk Usage</div>
    </div>
  </div>

  <!-- Recent Activity -->
  <div class="bg-gray-700 p-6 rounded-lg">
    <h2 class="text-xl font-semibold mb-4">Recent Activity</h2>
    {#if recentStudies.length > 0}
      <ul class="space-y-2">
        {#each recentStudies as study}
          <li class="p-3 bg-gray-800 rounded">{study.name}</li>
        {/each}
      </ul>
    {:else}
      <p class="text-gray-400">No recent activity</p>
    {/if}
  </div>
</div>
