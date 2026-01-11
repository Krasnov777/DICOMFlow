# Architecture Overview

## High-Level Architecture

DICOMFlow is a monolithic Tauri application consisting of:

1. **Rust Backend**: Handles all DICOM operations, networking, and data persistence
2. **Svelte Frontend**: Provides the user interface
3. **SQLite Database**: Stores metadata, settings, and request history
4. **IPC Layer**: Tauri commands bridge frontend and backend

```
┌─────────────────────────────────────────────┐
│           Svelte Frontend (UI)              │
│  - Components, Routes, Stores               │
└─────────────────┬───────────────────────────┘
                  │ Tauri IPC
┌─────────────────▼───────────────────────────┐
│           Rust Backend (Logic)              │
│  ┌─────────────────────────────────────┐   │
│  │  Commands (IPC handlers)            │   │
│  └─────────────────────────────────────┘   │
│  ┌──────────┬──────────┬──────────────┐    │
│  │  DICOM   │  DIMSE   │  DICOMweb    │    │
│  │  Parser  │  SCP/SCU │  Client      │    │
│  └──────────┴──────────┴──────────────┘    │
│  ┌─────────────────────────────────────┐   │
│  │  Database Layer (SQLite)            │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

## Backend Modules

### DICOM Module (`src-tauri/src/dicom/`)
- **parser.rs**: DICOM file parsing and validation
- **pixeldata.rs**: Image decoding and rendering
- **tags.rs**: Tag extraction and manipulation
- **anonymizer.rs**: Anonymization templates and operations

### DIMSE Module (`src-tauri/src/dimse/`)
- **scp.rs**: Service Class Provider (receiving DICOM images)
- **scu.rs**: Service Class User (querying and retrieving)
- **config.rs**: DIMSE configuration management

### DICOMweb Module (`src-tauri/src/dicomweb/`)
- **client.rs**: HTTP client for DICOMweb
- **qido.rs**: QIDO-RS query operations
- **wado.rs**: WADO-RS retrieve operations
- **stow.rs**: STOW-RS store operations

### Commands Module (`src-tauri/src/commands/`)
IPC command handlers that expose backend functionality to the frontend:
- **file.rs**: File opening operations
- **viewer.rs**: Image viewing commands
- **tags.rs**: Tag manipulation commands
- **dimse.rs**: DIMSE operation commands
- **dicomweb.rs**: DICOMweb operation commands
- **export.rs**: Export commands

### Database Module (`src-tauri/src/database/`)
- **models.rs**: SQLite data models
- **schema.rs**: Database schema definitions
- **mod.rs**: Database initialization and connection pooling

## Frontend Structure

### Components (`src/components/`)
- **common/**: Reusable UI components (Sidebar, TopBar, StatusBar)
- **dashboard/**: Dashboard-specific components
- **viewer/**: Image viewer components
- **dicomweb/**: DICOMweb testing components
- **dimse/**: DIMSE operation components
- **tag-editor/**: Tag editing components
- **settings/**: Settings components

### Routes (`src/routes/`)
- **Dashboard.svelte**: Main dashboard
- **Viewer.svelte**: DICOM image viewer
- **DicomWeb.svelte**: DICOMweb testing panel
- **Dimse.svelte**: DIMSE operations
- **TagEditor.svelte**: Tag editing and anonymization
- **Settings.svelte**: Application settings

### Stores (`src/stores/`)
Svelte stores for state management:
- **activeStudyStore.js**: Currently viewed study data
- **tagEditorStore.js**: Tag editing state
- **connectionStore.js**: DIMSE/DICOMweb connections
- **requestHistoryStore.js**: DICOMweb request history
- **settingsStore.js**: User preferences

## Data Flow

### Opening a DICOM File

1. User clicks "Open File" in TopBar
2. Frontend calls `open_dicom_file` Tauri command
3. Backend parses DICOM file using `dicom-rs`
4. Metadata extracted and stored in SQLite
5. File info returned to frontend
6. Frontend updates `activeStudyStore`
7. Viewer displays image and metadata

### DICOMweb Request

1. User builds request in DicomWeb route
2. Frontend calls `qido_rs`/`wado_rs`/`stow_rs` command
3. Backend executes HTTP request via `reqwest`
4. Response stored in request history (SQLite)
5. Response returned to frontend
6. Frontend displays response and updates history

### Tag Anonymization

1. User selects anonymization template
2. Frontend calls `anonymize_study` command
3. Backend loads DICOM files
4. Applies anonymization rules
5. Saves modified files
6. Returns results to frontend

## Key Dependencies

### Rust
- **dicom-rs**: DICOM parsing, pixel data, networking
- **tauri**: Application framework
- **sqlx**: Database access
- **reqwest**: HTTP client
- **tokio**: Async runtime
- **image**: Image processing

### Frontend
- **svelte**: UI framework
- **vite**: Build tool
- **tailwindcss**: Styling
- **chart.js**: Visualizations
- **svelte-spa-router**: Routing

## Performance Considerations

### Image Rendering
- Lazy loading: Only decode visible images
- Thumbnail cache: Pre-generated previews
- Background decoding: Use tokio tasks

### Database
- Connection pooling (max 5 connections)
- Indexed queries for fast searching
- JSON blobs for flexible tag storage

### Memory Management
- Stream large DICOM files instead of loading entirely
- Configurable cache limits
- Auto-cleanup in ephemeral mode

## Security

### Sandboxing
- Tauri's IPC validates all commands
- No direct filesystem access from frontend
- CORS configured for web requests

### Data Privacy
- Ephemeral mode for sensitive data
- Anonymization follows DICOM PS3.15
- Optional workspace encryption (future)

## Extension Points

### Adding New DICOM Operations
1. Add function to appropriate module (dicom/dimse/dicomweb)
2. Create Tauri command in commands/
3. Register command in main.rs
4. Call from frontend

### Adding New UI Components
1. Create component in src/components/
2. Import in route or parent component
3. Update stores if needed

### Adding Database Tables
1. Create migration: `sqlx migrate add table_name`
2. Update models.rs
3. Add queries in appropriate module
