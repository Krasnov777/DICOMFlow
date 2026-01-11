# Development Guide

## Getting Started

This project is now set up with a complete structure for DICOMFlow built with Tauri + Svelte + Rust.

## Quick Start

1. **Install Dependencies**
   ```bash
   npm install
   ```

2. **Run in Development Mode**
   ```bash
   npm run tauri:dev
   ```

3. **Build for Production**
   ```bash
   npm run tauri:build
   ```

## Project Status

This is a **scaffold/template** project. The structure is complete, but most functionality contains TODO placeholders that need implementation.

### What's Complete

- ✅ Full project structure
- ✅ Configuration files (package.json, Cargo.toml, vite.config.js, etc.)
- ✅ Database schema and migrations
- ✅ Module organization (backend and frontend)
- ✅ UI components and routes
- ✅ State management stores
- ✅ IPC command structure
- ✅ Documentation

### What Needs Implementation

The following areas have placeholder code and need actual implementation:

#### Backend (Rust)
- [ ] DICOM parsing implementation in `dicom/parser.rs`
- [ ] Pixel data decoding in `dicom/pixeldata.rs`
- [ ] Tag manipulation in `dicom/tags.rs`
- [ ] Anonymization logic in `dicom/anonymizer.rs`
- [ ] DIMSE SCP/SCU operations in `dimse/`
- [ ] DICOMweb client implementation in `dicomweb/`
- [ ] All Tauri commands in `commands/`
- [ ] Database queries and operations
- [ ] Unit and integration tests

#### Frontend (Svelte)
- [ ] File open dialogs and drag-drop
- [ ] Image viewer with windowing controls
- [ ] Tag table display and editing
- [ ] DICOMweb request builder UI
- [ ] DIMSE operations UI
- [ ] Real-time updates and notifications
- [ ] Frontend tests

#### Infrastructure
- [ ] Add test DICOM files to `test-data/`
- [ ] Create GitHub Actions workflows
- [ ] Set up installers (MSI, DMG)
- [ ] Add application icons
- [ ] Write remaining documentation

## Implementation Phases

Follow the phases outlined in the design document:

### Phase 1: Foundation (Start Here)
1. Implement basic DICOM file loading
2. Set up database persistence
3. Create simple file viewer UI

### Phase 2: Core Viewing
4. Implement pixel data decoding
5. Add windowing controls
6. Build tag browser

### Phase 3: DIMSE
7. Implement SCP (C-STORE, C-ECHO)
8. Implement SCU (C-FIND, C-MOVE)
9. Build connection management

### Phase 4: DICOMweb
10. HTTP client for QIDO/WADO/STOW
11. Request builder UI
12. Response viewer

### Phase 5: Advanced Features
13. Tag editor
14. Anonymization
15. Export capabilities

### Phase 6: Polish
16. Error handling
17. Performance optimization
18. Documentation
19. Installers

## Key Files to Start With

### Backend
1. `src-tauri/src/dicom/parser.rs` - Start by implementing basic DICOM file reading
2. `src-tauri/src/commands/file.rs` - Implement the file opening commands
3. `src-tauri/src/database/mod.rs` - Verify database initialization works

### Frontend
1. `src/components/common/TopBar.svelte` - Implement file open dialogs
2. `src/routes/Viewer.svelte` - Connect to backend commands
3. `src/stores/activeStudyStore.js` - Manage loaded study state

## Testing

### Add Test Data
Place sample DICOM files in `test-data/samples/`. See `test-data/README.md` for sources.

### Run Tests
```bash
# Rust tests
cd src-tauri
cargo test

# Frontend tests
npm test
```

## Dependencies

All dependencies are specified in:
- `package.json` (frontend)
- `src-tauri/Cargo.toml` (backend)

Run `npm install` and `cargo fetch` to download them.

## Resources

- Design Document: See original design document for detailed specifications
- Documentation: `docs/` directory
- DICOM Standard: https://www.dicomstandard.org/

## Need Help?

Refer to:
- `docs/developer-guide/architecture.md` for system overview
- `docs/developer-guide/building.md` for build instructions
- `docs/educational/dicom-basics.md` for DICOM fundamentals

## Next Steps

1. Set up your development environment
2. Download sample DICOM files for testing
3. Start with Phase 1: Foundation
4. Implement basic file loading and viewing
5. Build incrementally following the phase plan
