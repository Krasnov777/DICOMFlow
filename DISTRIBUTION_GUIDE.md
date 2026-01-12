# DICOMFlow - Distribution Guide

**Complete guide for building and distributing DICOMFlow on macOS and Windows**

---

## 🎨 Setting Up Your App Icon

### Required Icon Format
- **Format:** PNG with transparency
- **Recommended Resolution:** 1024x1024 pixels (or at least 512x512)
- **Color Space:** RGB
- **Transparency:** Yes (for rounded corners on macOS)

### Steps to Add Your Icon

1. **Place your icon:**
   ```bash
   # Save your high-resolution icon as:
   src-tauri/icons/icon.png

   # It should be 1024x1024 or 512x512 PNG
   ```

2. **Generate all required icon formats:**
   ```bash
   npm install --save-dev @tauri-apps/cli@latest
   npm run tauri icon src-tauri/icons/icon.png
   ```

   This will automatically generate:
   - **macOS:** `.icns` file (for .app bundle)
   - **Windows:** `.ico` file (for .exe)
   - **Linux:** Various PNG sizes
   - All sizes: 32x32, 128x128, 256x256, etc.

3. **Verify generated icons:**
   ```bash
   ls -la src-tauri/icons/
   ```

   You should see:
   - `icon.icns` (macOS)
   - `icon.ico` (Windows)
   - `32x32.png`, `128x128.png`, `128x128@2x.png`, `icon.png`
   - `Square*` files for Windows

### Icon Requirements by Platform

#### macOS
- **.icns** (Icon Set): Contains multiple resolutions (16x16 to 1024x1024)
- Auto-generated from your source PNG
- Used for: App icon, Dock, Finder

#### Windows
- **.ico** (Windows Icon): Contains 16x16, 32x32, 48x48, 64x64, 128x128, 256x256
- Auto-generated from your source PNG
- Used for: Taskbar, desktop, file explorer

#### Linux
- **PNG files**: Various sizes (32x32 up to 512x512)
- Auto-generated from your source PNG

---

## 📦 Building for Distribution

### macOS Distribution

#### 1. Development Build (for testing)
```bash
npm run tauri:dev
```

#### 2. Production Build (for distribution)
```bash
# Build macOS .app and .dmg
npm run tauri:build

# Output locations:
# - .app bundle: src-tauri/target/release/bundle/macos/DICOMFlow.app
# - .dmg installer: src-tauri/target/release/bundle/dmg/DICOMFlow_0.1.0_aarch64.dmg (Apple Silicon)
# - .dmg installer: src-tauri/target/release/bundle/dmg/DICOMFlow_0.1.0_x64.dmg (Intel)
```

#### 3. Code Signing (for distribution outside Mac App Store)

For distributing to other macOS users, you need to sign the app:

```bash
# Option 1: Sign manually
codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" \
  src-tauri/target/release/bundle/macos/DICOMFlow.app

# Option 2: Configure in tauri.conf.json (recommended)
# See configuration section below
```

**Note:** Without code signing, users will see "App from unidentified developer" warning.

#### 4. Notarization (for Gatekeeper approval)

To avoid Gatekeeper warnings:
```bash
# After building and signing
xcrun notarytool submit src-tauri/target/release/bundle/dmg/DICOMFlow_0.1.0_aarch64.dmg \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

#### 5. Universal Binary (Intel + Apple Silicon)

To support both architectures in one .dmg:
```bash
# Build for both architectures
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin

# Configure in tauri.conf.json (see below)
npm run tauri:build -- --target universal-apple-darwin
```

---

### Windows Distribution

#### 1. Development Build
```bash
npm run tauri:dev
```

#### 2. Production Build
```bash
# Build Windows installer (.msi) and portable .exe
npm run tauri:build

# Output locations:
# - Installer: src-tauri/target/release/bundle/msi/DICOMFlow_0.1.0_x64_en-US.msi
# - Portable: src-tauri/target/release/DICOMFlow.exe
# - NSIS installer: src-tauri/target/release/bundle/nsis/DICOMFlow_0.1.0_x64-setup.exe
```

#### 3. Code Signing (optional but recommended)

For Windows, you can sign with a certificate:
```bash
# Using signtool (requires Windows SDK)
signtool sign /f certificate.pfx /p password /t http://timestamp.digicert.com \
  src-tauri/target/release/DICOMFlow.exe
```

#### 4. Cross-compilation from macOS (experimental)

Building Windows .exe from macOS is possible but complex. Recommended approach:
- Use GitHub Actions CI/CD (see below)
- Or build on a Windows machine

---

## ⚙️ Configuration for Distribution

### Update `tauri.conf.json`

<function_calls>
<invoke name="Read">
<parameter name="file_path">/Users/krasnov/Documents/My_Projects/llm/Claude/docs/plans/dicom-toolkit/src-tauri/tauri.conf.json
```json
{
  "bundle": {
    "active": true,
    "targets": "all",  // or ["dmg", "msi", "nsis", "app"]
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/128x128@2x.png",
      "icons/icon.icns",
      "icons/icon.ico"
    ],
    "identifier": "com.dicomflow.app",
    "publisher": "Your Name or Company",
    "copyright": "Copyright © 2026 Your Name",
    "category": "MedicalSoftware",
    "shortDescription": "DICOM viewer and toolkit",
    "longDescription": "Professional DICOM image viewer with anonymization, tag editing, and PACS connectivity"
  }
}
```

### Code Signing Configuration (macOS)

Add to `tauri.conf.json`:
```json
{
  "bundle": {
    "macOS": {
      "signingIdentity": "Developer ID Application: Your Name (TEAM_ID)",
      "entitlements": null,
      "exceptionDomain": "",
      "frameworks": [],
      "providerShortName": null,
      "minimumSystemVersion": "10.15"
    }
  }
}
```

### Windows Installer Configuration

Add to `tauri.conf.json`:
```json
{
  "bundle": {
    "windows": {
      "certificateThumbprint": null,
      "digestAlgorithm": "sha256",
      "timestampUrl": "http://timestamp.digicert.com",
      "wix": {
        "language": "en-US",
        "template": null
      },
      "nsis": {
        "license": null,
        "installerIcon": "icons/icon.ico",
        "headerImage": null,
        "sidebarImage": null
      }
    }
  }
}
```

---

## 🚀 Quick Start: Building Your First Distribution

### Step 1: Prepare Your Icon
```bash
# 1. Save your 1024x1024 PNG icon as:
cp /path/to/your/icon.png src-tauri/icons/icon.png

# 2. Generate all required formats
npm run tauri icon src-tauri/icons/icon.png

# 3. Verify icons were generated
ls -la src-tauri/icons/
```

### Step 2: Update App Metadata
Edit `src-tauri/tauri.conf.json`:
- Update `version` to your release version (e.g., "1.0.0")
- Update `bundle.publisher` with your name/company
- Update `bundle.copyright` with your copyright notice

### Step 3: Build for Your Platform

**On macOS:**
```bash
# Build for macOS (creates .app and .dmg)
npm run tauri:build

# Find your app:
# .dmg: src-tauri/target/release/bundle/dmg/
# .app: src-tauri/target/release/bundle/macos/
```

**On Windows:**
```bash
# Build for Windows (creates .msi and .exe)
npm run tauri:build

# Find your app:
# .msi installer: src-tauri/target/release/bundle/msi/
# .exe portable: src-tauri/target/release/
```

### Step 4: Test the Build
```bash
# macOS: Open the .dmg and drag to Applications
open src-tauri/target/release/bundle/dmg/*.dmg

# Windows: Run the .msi installer
# Double-click the .msi file in File Explorer
```

---

## 🔄 CI/CD: Building for All Platforms

### GitHub Actions Workflow

Create `.github/workflows/build.yml`:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:

jobs:
  build:
    strategy:
      fail-fast: false
      matrix:
        platform:
          - os: macos-latest
            target: aarch64-apple-darwin
          - os: macos-latest
            target: x86_64-apple-darwin
          - os: windows-latest
            target: x86_64-pc-windows-msvc

    runs-on: ${{ matrix.platform.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: ${{ matrix.platform.target }}

      - name: Install dependencies (macOS)
        if: matrix.platform.os == 'macos-latest'
        run: |
          rustup target add ${{ matrix.platform.target }}

      - name: Install frontend dependencies
        run: npm install

      - name: Build Tauri app
        run: npm run tauri:build -- --target ${{ matrix.platform.target }}
        env:
          TAURI_PRIVATE_KEY: ${{ secrets.TAURI_PRIVATE_KEY }}
          TAURI_KEY_PASSWORD: ${{ secrets.TAURI_KEY_PASSWORD }}

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dicomflow-${{ matrix.platform.os }}-${{ matrix.platform.target }}
          path: |
            src-tauri/target/${{ matrix.platform.target }}/release/bundle/dmg/*.dmg
            src-tauri/target/${{ matrix.platform.target }}/release/bundle/msi/*.msi
            src-tauri/target/${{ matrix.platform.target }}/release/bundle/nsis/*.exe
```

---

## 📋 Distribution Checklist

### Before Building
- [ ] Update version in `tauri.conf.json` and `package.json`
- [ ] Add your custom icon (1024x1024 PNG)
- [ ] Run `npm run tauri icon` to generate all formats
- [ ] Update copyright and publisher info
- [ ] Test the app in development mode

### macOS Specific
- [ ] Code sign with Developer ID (optional but recommended)
- [ ] Notarize for Gatekeeper approval (optional)
- [ ] Test on both Intel and Apple Silicon Macs (if possible)
- [ ] Verify .dmg opens and installs correctly

### Windows Specific
- [ ] Test .msi installer
- [ ] Test portable .exe
- [ ] Verify icon appears in taskbar and desktop
- [ ] Test on Windows 10 and 11

### Both Platforms
- [ ] Test all features work in production build
- [ ] Verify file dialogs work (permissions)
- [ ] Test DICOM file loading
- [ ] Test image viewing and windowing
- [ ] Create release notes

---

## 📦 Distribution Methods

### Option 1: Direct Download
- Upload .dmg (macOS) and .msi (Windows) to your website
- Users download and install manually
- **Pros:** Simple, full control
- **Cons:** Manual updates, no auto-update

### Option 2: GitHub Releases
```bash
# Tag a release
git tag v1.0.0
git push origin v1.0.0

# Upload artifacts to GitHub Release
# Use GitHub Actions or manually upload .dmg and .msi
```

### Option 3: Tauri Auto-Updater
Configure in `tauri.conf.json`:
```json
{
  "updater": {
    "active": true,
    "endpoints": [
      "https://yourdomain.com/releases/{{target}}/{{current_version}}"
    ],
    "dialog": true,
    "pubkey": "YOUR_PUBLIC_KEY"
  }
}
```

### Option 4: Mac App Store / Microsoft Store
- Requires developer accounts ($99/year for Apple)
- Additional build configurations needed
- See Tauri documentation for details

---

## 🔧 Troubleshooting

### "Unable to find icon" Error
```bash
# Make sure you ran the icon generator
npm run tauri icon src-tauri/icons/icon.png

# Verify icons exist
ls src-tauri/icons/*.icns
ls src-tauri/icons/*.ico
```

### Code Signing Errors (macOS)
```bash
# List available signing identities
security find-identity -v -p codesigning

# If you don't have one, create a Developer ID at:
# https://developer.apple.com/account/
```

### Build Fails on Windows
```bash
# Make sure you have required tools
# Install Visual Studio with C++ development tools
# Or install Build Tools for Visual Studio 2022
```

### App Won't Open on macOS
```bash
# If users see "damaged" or "unidentified developer":
# You need to code sign and notarize the app

# Quick workaround for testing:
# Right-click the app → Open (instead of double-click)
```

---

## 📊 File Size Expectations

### macOS
- **.app bundle:** ~15-25 MB
- **.dmg installer:** ~10-20 MB (compressed)

### Windows
- **.exe (portable):** ~12-20 MB
- **.msi installer:** ~15-25 MB
- **NSIS installer:** ~10-20 MB

**Note:** Size varies based on:
- Dependencies included
- Compression settings
- Icon sizes

---

## 🎯 Next Steps

1. **Add your icon** (1024x1024 PNG)
2. **Generate icon formats** with `npm run tauri icon`
3. **Update version and metadata** in `tauri.conf.json`
4. **Build** with `npm run tauri:build`
5. **Test** the built app
6. **Distribute** via your preferred method

---

## 📚 Additional Resources

- [Tauri v2 Building Documentation](https://v2.tauri.app/guides/building/)
- [Tauri Icon Documentation](https://v2.tauri.app/reference/cli/#icon)
- [macOS Code Signing Guide](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution)
- [Windows Code Signing Guide](https://docs.microsoft.com/en-us/windows/win32/seccrypto/cryptography-tools)

---

**Ready to distribute? Start by adding your icon and running your first build!**
