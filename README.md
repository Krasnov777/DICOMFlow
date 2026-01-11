# DICOMFlow

A cross-platform desktop application for DICOM viewing, testing, and development. Built with Tauri + Svelte + Rust.

## Overview

This toolkit combines DICOM viewing capabilities with comprehensive DICOMweb testing functionality and traditional DIMSE protocol support. Designed for developers who need to test DICOM implementations, debug medical imaging workflows, and learn DICOM protocols.

## Features

- **DICOM Viewer**: View medical images with windowing controls and metadata inspection
- **DICOMweb Testing**: Interactive HTTP-based DICOM operations (QIDO-RS, WADO-RS, STOW-RS)
- **DIMSE Support**: Both SCP (receive) and SCU (query/retrieve) via traditional DICOM networking
- **Tag Manipulation**: Advanced tag editing, anonymization, bulk operations
- **Export Capabilities**: Tags as JSON/XML/CSV, images as PNG

## Technology Stack

**Backend (Rust):**
- dicom-rs ecosystem
- Tauri framework
- SQLite + sqlx
- tokio async runtime

**Frontend (Svelte):**
- Svelte + Vite
- TailwindCSS
- Chart.js for visualizations

## Project Structure

```
dicomflow/
├── src-tauri/          # Rust backend
│   ├── src/
│   │   ├── dicom/      # DICOM parsing and pixel data
│   │   ├── dimse/      # DIMSE SCP/SCU operations
│   │   ├── dicomweb/   # DICOMweb client
│   │   ├── database/   # SQLite persistence
│   │   ├── commands/   # Tauri IPC commands
│   │   └── utils/      # Utilities
│   └── tests/          # Backend tests
├── src/                # Svelte frontend
│   ├── components/     # UI components
│   ├── routes/         # Application routes
│   ├── stores/         # State management
│   └── utils/          # Frontend utilities
├── docs/               # Documentation
└── test-data/          # Sample DICOM files
```

## Getting Started

See [docs/developer-guide/building.md](docs/developer-guide/building.md) for build instructions.

## Documentation

- [User Guide](docs/user-guide/)
- [Developer Guide](docs/developer-guide/)
- [Educational Content](docs/educational/)

## License

MIT
