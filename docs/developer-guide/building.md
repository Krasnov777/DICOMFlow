# Building from Source

## Prerequisites

### Rust
Install Rust using rustup:
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Node.js
Install Node.js (v18 or later):
- Download from [nodejs.org](https://nodejs.org)
- Or use a version manager like `nvm`

### Platform-Specific Requirements

#### Windows
- Visual Studio Build Tools
- WebView2 Runtime (usually pre-installed on Windows 10+)

#### macOS
- Xcode Command Line Tools:
  ```bash
  xcode-select --install
  ```

## Clone the Repository

```bash
git clone https://github.com/your-org/dicomflow.git
cd dicomflow
```

## Install Dependencies

### Frontend Dependencies
```bash
npm install
```

### Rust Dependencies
```bash
cd src-tauri
cargo fetch
cd ..
```

## Development Build

### Run in Development Mode
```bash
npm run tauri:dev
```

This will:
1. Start the Vite dev server for the frontend
2. Build the Rust backend
3. Launch the application with hot-reload enabled

### Build Frontend Only
```bash
npm run dev
```

### Build Backend Only
```bash
cd src-tauri
cargo build
```

## Production Build

### Build for Current Platform
```bash
npm run tauri:build
```

The built application will be in `src-tauri/target/release/bundle/`

### Build Options

#### Debug Build (faster, larger)
```bash
cd src-tauri
cargo build
```

#### Release Build (optimized)
```bash
cd src-tauri
cargo build --release
```

## Running Tests

### Rust Tests
```bash
cd src-tauri
cargo test
```

### Frontend Tests
```bash
npm test
```

### Integration Tests
```bash
cd src-tauri
cargo test --test integration_tests
```

## Database Migrations

The SQLite database schema is managed with sqlx migrations.

### Create a New Migration
```bash
cd src-tauri
sqlx migrate add migration_name
```

### Run Migrations
Migrations run automatically on application startup.

## Troubleshooting

### Build Fails with "missing dicom-rs"
```bash
cd src-tauri
cargo clean
cargo update
cargo build
```

### Frontend Build Errors
```bash
rm -rf node_modules
npm install
npm run build
```

### Database Issues
Delete the database file and restart:
```bash
rm ~/Library/Application\ Support/dicomflow/dicomflow.db  # macOS
rm %LOCALAPPDATA%\dicomflow\dicomflow.db  # Windows
```

## Code Formatting

### Rust
```bash
cd src-tauri
cargo fmt
```

### JavaScript/Svelte
```bash
npm run format
```

## Linting

### Rust
```bash
cd src-tauri
cargo clippy
```

### JavaScript/Svelte
```bash
npm run lint
```
