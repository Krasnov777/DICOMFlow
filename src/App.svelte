<script>
  import Router from 'svelte-spa-router';
  import { routes } from './routes';
  import Sidebar from './components/common/Sidebar.svelte';
  import TopBar from './components/common/TopBar.svelte';
  import StatusBar from './components/common/StatusBar.svelte';
</script>

<div class="flex flex-col h-screen bg-gray-900 text-white">
  <!-- Top Bar -->
  <TopBar />

  <!-- Main Content Area -->
  <div class="flex flex-1 overflow-hidden">
    <!-- Sidebar -->
    <Sidebar />

    <!-- Router Content -->
    <main class="flex-1 overflow-auto bg-gray-800">
      <Router {routes} />
    </main>
  </div>

  <!-- Status Bar -->
  <StatusBar />
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
  }
</style>
