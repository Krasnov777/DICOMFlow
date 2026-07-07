# DicomFlow

A native macOS app for engineers to **test DICOM networking** and **view DICOM
images** — a developer's toolbench for PACS integration work, protocol debugging,
and poking at datasets. **Not a medical product**: no diagnosis, no clinical use.

Fully native — SwiftUI + Metal, with **DCMTK statically linked in-process** via an
Obj-C++ bridge. No Python, no subprocesses, no runtime dependencies.

## Two modes

### Tester / Toolbench
A sidebar of DICOM tools:

- **Networking** — C-ECHO, C-STORE, Query/Retrieve (C-FIND / C-MOVE / C-GET),
  **Modality Worklist** (MWL C-FIND), **DICOMweb** (QIDO / WADO / STOW), **FHIR**
  (ImagingStudy), **HL7 v2 over MLLP** (send + listener), a built-in **Test
  SCP** / mini-PACS, a **Negotiation Probe** (which presentation contexts does a
  peer accept?), and a **Protocol Inspector** — a decoded DICOM-traffic timeline
  that also **imports .pcap/.pcapng** captures and dissects their PDUs.
- **Files & tags** — tag **Inspector**, **Editor**, **Anonymizer** (PS3.15 Basic
  Profile), **Redact Pixels** (burned-in text detection via Vision OCR),
  a conformance **Validator** (full IOD validation), two-file **Compare** (tag
  diff), **DICOMDIR** reader, **Dataset Dump**, and a **Synthetic Generator**.
- **DICOM TLS** (BCP 195) on every outgoing connection; per-target toggle.

See **[docs/TESTER-TOOLS.md](docs/TESTER-TOOLS.md)** for the full tour.

### Viewer
2D slices (axial / coronal / sagittal, keyboard-driven, right-drag W/L),
Orthanc-style **2×2 MPR** with a linked crosshair, and **GPU volume rendering**
in Metal with five reconstruction modes (MIP, MinIP, X-Ray/DRR, Volume,
Iso-Surface) — arcball or turntable rotation, clip planes, transfer-function
gallery, view presets. Persistent measurements (distance / ROI + HU histogram /
angle), multi-frame stacks, Structured Reports rendered as text, PNG and movie
export. Codecs: uncompressed / JPEG / JPEG-LS / RLE / **JPEG 2000**.

See **[docs/VIEWER.md](docs/VIEWER.md)**.

### MCP server
`dicomflow-mcp` exposes the same native DICOM engine to AI agents as an
[MCP](https://modelcontextprotocol.io) stdio server — echo, query, retrieve,
inspect tags, render slices. It's a separate un-sandboxed command-line tool
(built from this repo, distributed outside the app sandbox).
See **[docs/MCP.md](docs/MCP.md)**.

## Build

Requires **macOS 26**, Xcode 26+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Apple Silicon only.

```bash
# One-time: build the DCMTK static framework (~2 min) and OpenJPEG (~1 min)
bash native/build-dcmtk.sh        # → native/DCMTKit.xcframework
bash native/build-openjpeg.sh     # → native/openjpeg-install

# Generate the Xcode project and build
xcodegen generate
xcodebuild -project DicomFlow.xcodeproj -scheme DicomFlow -configuration Debug \
  -derivedDataPath build build

# Run
open build/Build/Products/Debug/DicomFlow.app

# Verify (unit tests + build + headless integration hooks; network peers auto-skip)
bash scripts/verify.sh            # or --fast for unit tests only
```

Builds are **unsigned by default** so anyone can compile without certificates
(the App Sandbox stays on). Maintainers produce release DMGs with
`scripts/notarize.sh`, which signs, notarizes, and staples both the app and the
DMG container itself. OpenSSL static libs are vendored in `native/openssl/`.

Live-PACS tests are opt-in: `TEST_RUNNER_ORTHANC_HOST=<host> xcodebuild … test`
(xcodebuild forwards env vars to the test runner only with the `TEST_RUNNER_`
prefix; optional `TEST_RUNNER_ORTHANC_PORT` / `TEST_RUNNER_ORTHANC_AE`) runs
round-trip tests against a real Orthanc; unset, the suite is fully offline.

## Layout

```
App/         SwiftUI app target (DicomFlowApp, AppState, RootView, Settings)
Sources/     DicomNative (Obj-C++ ↔ DCMTK) · DicomEngine (+ DICOMweb/FHIR/HL7 clients)
             DicomModel · MetalRender · DesignSystem · AppCore · TesterUI · ViewerUI
mcp/         dicomflow-mcp — MCP stdio server target
native/      DCMTK + OpenJPEG build scripts (outputs git-ignored) · vendored
             fmjpeg2k codec + OpenSSL static libs (committed)
Tests/       XCTest logic tests (offline; live tests gated by ORTHANC_HOST)
project.yml  XcodeGen spec — the .xcodeproj is generated, never committed
scripts/     verify.sh · build-mcp.sh · notarize.sh · tls-proxy.py
docs/        ARCHITECTURE · TESTER-TOOLS · VIEWER · MCP · DECISIONS · PROGRESS · BACKLOG
```

## Docs

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — components, native engine, Metal pipeline
- [docs/TESTER-TOOLS.md](docs/TESTER-TOOLS.md) — every Tester tool, key files, headless hooks
- [docs/VIEWER.md](docs/VIEWER.md) — viewer layouts, tools, keyboard shortcuts, data support
- [docs/MCP.md](docs/MCP.md) — use DicomFlow as an AI-agent tool
- [docs/DECISIONS.md](docs/DECISIONS.md) — engineering decision log
- [docs/PROGRESS.md](docs/PROGRESS.md) / [docs/BACKLOG.md](docs/BACKLOG.md) — status & roadmap

## License

[MIT](LICENSE). Bundles DCMTK (BSD-3), OpenJPEG (BSD-2), fmjpeg2koj
(Apache-2.0), and OpenSSL (Apache-2.0) — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

DicomFlow is a testing and visualization tool for engineers. It is **not a
medical device** and must not be used for diagnosis or treatment.
