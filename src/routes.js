import Dashboard from './routes/Dashboard.svelte';
import Viewer from './routes/Viewer.svelte';
import DicomWeb from './routes/DicomWeb.svelte';
import Dimse from './routes/Dimse.svelte';
import TagEditor from './routes/TagEditor.svelte';
import Settings from './routes/Settings.svelte';

export const routes = {
  '/': Dashboard,
  '/viewer': Viewer,
  '/dicomweb': DicomWeb,
  '/dimse': Dimse,
  '/tags': TagEditor,
  '/settings': Settings,
};
