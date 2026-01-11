<script>
  import { location } from 'svelte-spa-router';

  const navItems = [
    { path: '/', label: 'Dashboard', icon: '📊' },
    { path: '/viewer', label: 'Viewer', icon: '🖼️' },
    { path: '/dicomweb', label: 'DICOMweb', icon: '🌐' },
    { path: '/dimse', label: 'DIMSE', icon: '📡' },
    { path: '/tags', label: 'Tag Editor', icon: '🏷️' },
    { path: '/settings', label: 'Settings', icon: '⚙️' },
  ];

  function isActive(path) {
    return $location === path;
  }
</script>

<aside class="w-64 bg-gray-900 border-r border-gray-700 flex flex-col">
  <div class="p-4 border-b border-gray-700">
    <h1 class="text-xl font-bold text-primary-400">DICOMFlow</h1>
  </div>

  <nav class="flex-1 p-4 space-y-2">
    {#each navItems as item}
      <a
        href="#{item.path}"
        class="flex items-center gap-3 px-4 py-3 rounded-lg transition-colors
               {isActive(item.path)
                 ? 'bg-primary-600 text-white'
                 : 'text-gray-300 hover:bg-gray-800'}"
      >
        <span class="text-xl">{item.icon}</span>
        <span>{item.label}</span>
      </a>
    {/each}
  </nav>
</aside>
