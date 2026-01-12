<script>
  import { connectionStore } from '../../stores/connectionStore';
  import { activeStudyStore } from '../../stores/activeStudyStore';
  import { invoke } from '@tauri-apps/api/core';
  import { open } from '@tauri-apps/plugin-dialog';
  import { push } from 'svelte-spa-router';

  async function handleOpenFile() {
    console.log('Open File button clicked');
    try {
      console.log('Opening file dialog...');
      // Open file dialog
      const selected = await open({
        multiple: false,
        filters: [{
          name: 'DICOM Files',
          extensions: ['dcm', 'dicom', '*']
        }]
      });
      console.log('Selected file:', selected);

      if (selected) {
        // Call backend to load the file
        const fileInfo = await invoke('open_dicom_file', { path: selected });

        // Load tags for this file
        const tags = await invoke('get_all_tags', { filePath: selected });

        // Update the active study store
        activeStudyStore.update(store => ({
          ...store,
          studyInstanceUID: fileInfo.study_instance_uid,
          patientName: fileInfo.patient_name,
          patientID: fileInfo.patient_id,
          studyDate: fileInfo.study_date,
          modality: fileInfo.modality,
          currentInstanceUID: fileInfo.sop_instance_uid,
          currentSeriesUID: fileInfo.series_instance_uid,
          currentFilePath: selected,
          tags: tags,
          series: [], // Clear series for single file
        }));

        console.log('Loaded DICOM file:', fileInfo);

        // Navigate to viewer
        push('/viewer');
      }
    } catch (error) {
      console.error('Failed to open file:', error);
      alert('Failed to open file: ' + error);
    }
  }

  async function handleOpenDirectory() {
    try {
      // Open directory dialog
      const selected = await open({
        directory: true,
        multiple: false
      });

      if (selected) {
        console.log('Opening directory:', selected);

        // Organize directory into study/series structure
        const studyInfo = await invoke('organize_directory', { path: selected });

        if (studyInfo && studyInfo.series.length > 0) {
          // Get first instance of first series
          const firstSeries = studyInfo.series[0];
          const firstInstance = firstSeries.instances[0];

          // Load tags for first instance
          const tags = await invoke('get_all_tags', { filePath: firstInstance.path });

          // Update store with organized structure
          activeStudyStore.update(store => ({
            ...store,
            studyInstanceUID: studyInfo.study_instance_uid,
            patientName: studyInfo.patient_name,
            patientID: studyInfo.patient_id,
            studyDate: studyInfo.study_date,
            series: studyInfo.series,
            currentSeriesIndex: 0,
            currentInstanceIndex: 0,
            currentFilePath: firstInstance.path,
            tags: tags,
          }));

          console.log('Loaded study with', studyInfo.series.length, 'series');

          // Navigate to viewer
          push('/viewer');
        } else {
          alert('No DICOM files found in the selected directory');
        }
      }
    } catch (error) {
      console.error('Failed to open directory:', error);
      alert('Failed to open directory: ' + error);
    }
  }
</script>

<header class="h-14 bg-gray-900 border-b border-gray-700 flex items-center justify-between px-6">
  <div class="flex items-center gap-4 flex-1 overflow-hidden">
    <div class="flex items-center gap-2">
      <span class="text-sm text-gray-400">Connections:</span>
      {#if $connectionStore.scpRunning}
        <span class="px-2 py-1 bg-green-600 text-xs rounded">SCP Active</span>
      {/if}
      {#if $connectionStore.activeDicomWebEndpoint}
        <span class="px-2 py-1 bg-blue-600 text-xs rounded">
          DICOMweb: {$connectionStore.activeDicomWebEndpoint}
        </span>
      {/if}
    </div>
    {#if $activeStudyStore.currentFilePath}
      <div class="flex items-center gap-2 border-l border-gray-700 pl-4">
        <span class="text-sm text-gray-400">Loaded:</span>
        <span class="px-2 py-1 bg-purple-600 text-xs rounded max-w-md truncate" title={$activeStudyStore.currentFilePath}>
          {$activeStudyStore.patientName || 'Unknown'} - {$activeStudyStore.studyDate || 'N/A'}
        </span>
      </div>
    {/if}
  </div>

  <div class="flex items-center gap-3">
    <button
      on:click={handleOpenFile}
      class="px-4 py-2 bg-primary-600 hover:bg-primary-700 rounded text-sm transition"
    >
      Open File
    </button>
    <button
      on:click={handleOpenDirectory}
      class="px-4 py-2 bg-primary-600 hover:bg-primary-700 rounded text-sm transition"
    >
      Open Directory
    </button>
  </div>
</header>
