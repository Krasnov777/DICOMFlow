# DICOMFlow

A professional DICOM medical imaging toolkit built with Rust, Tauri v2, and Svelte.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey.svg)

## Features

### Core Functionality
- **DICOM Viewing** - Fast image rendering with window/level adjustment (40-60ms decode time)
- **Tag Editor** - View, edit, and delete DICOM tags with validation
- **Anonymization** - HIPAA-compliant de-identification (Basic, Full, Research templates)
- **Multi-Series Navigation** - Browse studies with multiple series and instances
- **Export** - PNG images with custom windowing, JSON/XML tag export

### Network Features
- **DICOMweb Client** - QIDO-RS, WADO-RS for modern PACS connectivity
- **DIMSE Operations** - C-ECHO for connectivity testing (C-FIND/C-MOVE framework ready)
- **SCP Server** - Receives DICOM connections

### Performance
- **Parallel Directory Scanning** - 10-30x faster (1-2s for 1,105 files)
- **Optimized Image Loading** - ~50ms per image end-to-end
- **Minimal Memory Footprint** - On-demand pixel data loading

## Tech Stack

**Backend (Rust)**
- Tauri v2 - Desktop framework
- dicom-rs ecosystem - DICOM parsing and processing
- tokio - Async runtime
- rayon - Parallel processing
- SQLite - Study database

**Frontend**
- Svelte - Reactive UI framework
- TailwindCSS - Styling
- svelte-spa-router - Client-side routing

## Quick Start

### Prerequisites
- Node.js 20+
- Rust (via rustup)
- macOS or Windows

### Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run tauri:dev
```

### Production Build

```bash
# Build for your platform
npm run tauri:build

# Output locations:
# macOS: src-tauri/target/release/bundle/dmg/
# Windows: src-tauri/target/release/bundle/msi/
```

## Project Structure

```
dicom-toolkit/
├── src/                          # Frontend (Svelte)
│   ├── components/common/        # Reusable UI components
│   ├── routes/                   # Page components
│   └── stores/                   # Svelte stores (state management)
│
├── src-tauri/                    # Backend (Rust)
│   ├── src/
│   │   ├── commands/            # Tauri commands (IPC)
│   │   ├── dicom/               # DICOM processing
│   │   ├── dimse/               # DIMSE implementation
│   │   └── database/            # SQLite database
│   └── icons/                   # App icons (all platforms)
│
├── .github/workflows/           # CI/CD for automated builds
├── test-data/                   # Test DICOM files
└── docs/                        # Documentation
```

## Documentation

- **[PROJECT_STATUS.md](PROJECT_STATUS.md)** - Complete feature status, performance metrics, known issues
- **[DISTRIBUTION_GUIDE.md](DISTRIBUTION_GUIDE.md)** - Building and distributing for macOS/Windows
- **[DIMSE_IMPLEMENTATION.md](DIMSE_IMPLEMENTATION.md)** - DIMSE architecture and implementation status
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development setup and guidelines

## Distribution

### Automated Builds (GitHub Actions)

Every tagged release automatically builds for:
- macOS Apple Silicon (.dmg)
- macOS Intel (.dmg)
- Windows x64 (.msi + .exe)

**Create a release:**
```bash
git tag v0.2.0
git push origin v0.2.0
```

Installers will be attached to the GitHub Release.

### Manual Builds

See [DISTRIBUTION_GUIDE.md](DISTRIBUTION_GUIDE.md) for detailed instructions on:
- Icon customization
- Code signing (macOS/Windows)
- Notarization (macOS)
- CI/CD setup

## Current Status

✅ **Fully Functional:**
- All core features implemented (Phases 1-9)
- Production-ready for viewing, editing, anonymization, and export
- DICOMweb client operational
- DIMSE C-ECHO working

⚠️ **In Progress:**
- DIMSE C-FIND/C-MOVE/C-GET (query datasets built, protocol layer needs completion)
- STOW-RS multipart encoding

See [PROJECT_STATUS.md](PROJECT_STATUS.md) for detailed status.

## Development

### Adding Features

1. **Backend (Rust)** - Add commands in `src-tauri/src/commands/`
2. **Frontend (Svelte)** - Add components in `src/components/` or routes in `src/routes/`
3. **State Management** - Use Svelte stores in `src/stores/`

### Running Tests

```bash
# Rust tests
cd src-tauri
cargo test

# Frontend tests (when implemented)
npm test
```

### Building for Multiple Platforms

The GitHub Actions workflow automatically builds for all platforms. See `.github/workflows/build.yml`.

## Performance Metrics

- **Directory Scan:** 1-2s for 1,105 DICOM files (parallel processing)
- **Image Decode:** 40-60ms (pixel decode + PNG encode + base64)
- **File Load:** <5ms (metadata extraction)

## License

MIT License - See LICENSE file for details

## Acknowledgments

Built with:
- [dicom-rs](https://github.com/Enet4/dicom-rs) - DICOM parsing
- [Tauri](https://tauri.app/) - Desktop framework
- [Svelte](https://svelte.dev/) - UI framework

---

**Version:** 0.1.0
**Status:** Production Ready
**Platforms:** macOS (Intel + Apple Silicon), Windows (x64)
