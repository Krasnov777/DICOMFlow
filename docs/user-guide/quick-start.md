# Quick Start Guide

## Installation

### Windows
1. Download the MSI installer from the releases page
2. Run the installer and follow the prompts
3. Launch DICOMFlow from the Start Menu

### macOS
1. Download the DMG file from the releases page
2. Open the DMG and drag the app to Applications
3. Launch DICOMFlow from Applications

## First-Time Setup

When you first launch DICOMFlow, you'll be greeted with a setup wizard:

1. **Configure SCP Listener** (optional)
   - Set your AE Title (default: DICOM_TOOLKIT)
   - Choose a port (default: 11112)
   - Select storage location

2. **Add PACS Endpoints** (optional)
   - Add remote PACS servers you want to query
   - Configure connection details

3. **Choose Operating Mode**
   - **Workspace Mode**: Saves studies and settings between sessions
   - **Ephemeral Mode**: Clears everything on exit (useful for quick testing)

## Opening DICOM Files

### Single File
1. Click "Open File" in the top bar
2. Select a DICOM file from your system
3. The file will open in the Viewer

### Directory
1. Click "Open Directory" in the top bar
2. Select a folder containing DICOM files
3. All DICOM files will be scanned and imported

### Drag and Drop
- Drag DICOM files or folders directly into the application window

## Basic Viewing

1. Navigate to the **Viewer** tab
2. Use the windowing controls at the bottom to adjust brightness/contrast
3. Use mouse wheel to zoom
4. Click and drag to pan
5. View DICOM tags in the right panel

## Testing DICOMweb APIs

1. Navigate to the **DICOMweb** tab
2. Select the operation type (QIDO-RS, WADO-RS, STOW-RS)
3. Enter the endpoint URL
4. Add query parameters and headers
5. Click "Send Request"
6. View the response in the response panel

## Receiving DICOM Images (SCP)

1. Navigate to the **DIMSE** tab
2. Click the "SCP (Receiving)" tab
3. Configure your AE Title and port
4. Click "Start Listener"
5. Send DICOM images from another system to this listener
6. Received images will appear in the incoming connections log

## Next Steps

- Read the [DICOMweb Testing Guide](dicomweb-testing.md)
- Learn about [Tag Editing and Anonymization](tag-editing.md)
- Explore [DIMSE Operations](dimse-operations.md)
