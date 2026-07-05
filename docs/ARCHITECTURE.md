# DicomFlow — Architecture

A native macOS app for engineers to **test DICOM networking** and **view DICOM
images for fun**. Not a medical product; no regulatory constraints. Two modes:
**Tester/Toolbench** and **Viewer**.

It is a **single, sandboxed, fully native process**: SwiftUI + Metal with DCMTK
linked in-process. No Python, no subprocess, no IPC → Mac-App-Store-eligible.

## Component map

```
DicomFlow/
├── App/                  SwiftUI app target
│   ├── DicomFlowApp.swift     @main; owns AppState; Settings scene; test hooks
│   ├── AppState.swift          mode, DicomEngine, ViewerState (persists across
│   │                           modes), openInViewer()
│   ├── RootView.swift          top mode switch + toolbar stripe
│   ├── SettingsView.swift      ⌘, — PACS defaults + Interaction (input device)
│   ├── WelcomeView.swift       first-run overview
│   ├── Mode.swift              AppMode enum
│   ├── Info.plist · DicomFlow.entitlements · DicomFlow-Bridging-Header.h
│   └── NativeTest.swift        headless self-tests + perf hook
│                               (DICOMFLOW_NATIVE_*/_SR/_SCAN/_PERF)
├── Sources/
│   ├── DicomNative/      DCMTKBridge (tags/decode/edit/anon/scan/SR/validate) +
│   │                     DCMTKNet (SCU/SCP/worklist) + DCMTKLog (log4cplus appender
│   │                     → Swift) — the only C++ seam
│   ├── DicomEngine/      DicomEngine (Swift API; decode, scanSeries, readReport,
│   │                     worklistQuery, validate) + SliceDecode (sort/stack/resample)
│   │                     + DicomWebClient (QIDO/WADO/STOW) + FHIRClient (ImagingStudy)
│   │                     + HL7 (MLLP frame/ACK, HL7Client/HL7Listener)
│   ├── DicomModel/       Volume (Data → MTLTexture, geometry, CPU HU probe)
│   ├── MetalRender/      MetalContext, MPR (zoom/pan/invert, rotate/flip) + raycast
│   │                     renderers (5 modes, clip planes, fixed world light,
│   │                     arcball camera w/ pan target + presets), shaders, TF
│   ├── DesignSystem/     macOS 26 Liquid Glass theme + components (glassBar,
│   │                     ToolHeader, Card, StatusPill, EmptyState)
│   ├── AppCore/          PacsProfileStore + Defaults + InputDevice (persistence),
│   │                     LogStore, ProtocolLog (DICOM traffic timeline),
│   │                     PcapParser (pcap/pcapng → DICOM PDU dissection)
│   ├── ViewerUI/         ViewerState (+ PlaneOrientation, plane2D, annotations),
│   │                     2D/MPR/3D views, docked bottom bar (ViewThatFits tiers),
│   │                     info strip, series sidebar, SRReportView, ExportImage +
│   │                     ExportMovie (H.264 sweep/turntable), keyboard shortcuts.
│   │                     See docs/VIEWER.md
│   ├── TesterUI/         sidebar + tools + TargetForm (profiles) + DIMSE log console.
│   │                     Networking: Echo/Store/QueryRetrieve/Worklist/DicomWeb/FHIR/
│   │                     HL7/LocalSCP/ProtocolInspector; Files&Tags: TagInspector/
│   │                     TagEditor/Anonymize/Validator/Diff. See docs/TESTER-TOOLS.md
│   └── SidecarKit/       shared Codable DTOs / data models (TagItem, VolumeMeta,
│                         network + edit result types). [Legacy name; no networking.]
├── native/              DCMTK build → DCMTKit.xcframework (build-dcmtk.sh; git-ignored)
│                        + build-openjpeg.sh → openjpeg-install (git-ignored)
│                        + fmjpeg2k/ — vendored JPEG 2000 codec sources (committed)
├── Tests/               XCTest logic tests (PcapParser, HL7, DicomWebClient) —
│                        standalone bundle, run via scripts/verify.sh or xcodebuild test
├── scripts/             notarize.sh — Developer-ID sign + notarize + DMG (maintainers)
│                        + verify.sh — one-command build + tests + headless hooks
├── sidecar/             LEGACY Python sidecar (v1) — unused at runtime; retains
│                        tools/make_fixture.py for generating synthetic test data
├── docs/                this folder
└── project.yml          XcodeGen spec (the .xcodeproj is generated, not committed)
```

## DICOM engine — native DCMTK, in-process

```
DicomFlow.app (single sandboxed process)
  SwiftUI / Metal ── DicomEngine (Swift) ──┬── DCMTKBridge (Obj-C++) ── DCMTK ── parse / decode
                                           │                                      tag edit / anonymize
                                           └── DCMTKNet  (Obj-C++) ──── DCMTK ── DcmSCU / DcmStorageSCP
```

- **`Sources/DicomNative/`** is the only place that includes DCMTK C++ headers.
  `DCMTKBridge` (parsing, pixel decode, tag edit, anonymize) and `DCMTKNet`
  (DIMSE networking + storage SCP) expose Foundation-typed methods to Swift via
  the bridging header.
- **`DicomEngine`** wraps the bridge in an `async` Swift API the UI consumes
  (`readTags`, `decodeVolume`, `editTags`, `anonymize`, `echo`, `store`, `query`,
  `retrieve`, `worklistQuery`, `validate`, `scpStart/stop/status/received`). Heavy
  work runs off the main actor. **Web/messaging clients** (`DicomWebClient`,
  `FHIRClient`, `HL7`) are pure Swift (URLSession / Network.framework), no DCMTK.
- **`native/DCMTKit.xcframework`** — DCMTK 3.6.9 static lib (arm64), built with a
  **builtin DICOM dictionary** (`DCMTK_DEFAULT_DICT=builtin`,
  `DCMTK_USE_DCMDICTPATH=OFF`) so tag names resolve with no external file under the
  sandbox. Built by `native/build-dcmtk.sh`, kept out of git (rebuilt locally via the script). Linked statically — nothing to embed/sign separately.
- **Codecs:** uncompressed + JPEG + JPEG-LS + RLE (DCMTK bundled) + **JPEG 2000**
  (vendored `native/fmjpeg2k` codec — fmjpeg2koj, Apache-2.0 — backed by OpenJPEG,
  built statically by `native/build-openjpeg.sh`). Decode-only; verified pixel-exact
  against pydicom on its J2K test corpus. The decode path handles 16-bit and 8-bit
  pixels (8-bit grayscale is widened; color is converted to Rec.601 luma).
- **Network timeouts:** every outgoing SCU gets TCP-connect / ACSE / per-message
  DIMSE timeouts (`DCMTKNet.setNetworkTimeout`, Settings → "Networking", default
  15 s) — DCMTK's default is to block forever on a dead host.
- **Networking notes:** `DcmStorageSCP` runs on a background `std::thread` in
  blocking mode, configured via a generated association-config profile; reverse-DNS
  is disabled (`dcmDisableGethostbyaddr`) to avoid per-association hangs. Retrieve
  supports C-MOVE (to the built-in SCP) and C-GET (into the app's container).

### Decode → volume pipeline
1. `DicomEngine.decodeVolume(directory:)` enumerates files, calls
   `DCMTKBridge.decodeFile` per instance (decompresses if needed) → 16-bit pixels +
   geometry.
2. `SliceDecode` groups by series, sorts by `ImagePositionPatient`·normal, stacks,
   and resamples to uniform z when spacing is irregular.
3. `Volume` converts int16 → float (Accelerate `vDSP_vflt16`) and uploads an
   `r32Float` 3D `MTLTexture`.

## Metal rendering

- **Volume:** stored values in an `r32Float` 3D texture; shaders apply
  `slope`/`intercept` for HU.
- **MPR (`MPR.metal`):** full-screen quad; each fragment maps to a plane
  (origin + 2 axes) in normalized texture space, single trilinear sample, HU
  window/level. Aspect letterboxed to physical size (handles anisotropic z).
- **Ray-cast (`VolumeRaycast.metal`):** single-pass fragment; ray-box intersect,
  front-to-back march. **MIP** (max HU) and **TF** (1D RGBA LUT, opacity-corrected
  compositing, early-ray termination). Arcball camera, scroll-zoom.

## Sandbox & file access

App Sandbox is on (`App/DicomFlow.entitlements`): `app-sandbox`,
`network.client` (SCU), `network.server` (test SCP), `files.user-selected.read-write`.
File/folder picks call `startAccessingSecurityScopedResource()` so the async engine
can read user-chosen paths. Received/anonymized/decoded data lives under the app
container's temp dir (writable without extra entitlements).

## Headless self-tests

`App/NativeTest.swift`, gated by env vars, exercise the engine without the GUI:
`DICOMFLOW_NATIVE_TAGS`, `DICOMFLOW_NATIVE_VOLUME` (renders MPR/MIP/volume PNGs),
`DICOMFLOW_NATIVE_EDITANON`, `DICOMFLOW_NATIVE_NET` (loopback SCP), and the
cross-process `DICOMFLOW_NATIVE_SCU` / `DICOMFLOW_NATIVE_SCPONLY`. Tester-tool
hooks (each writes to a `*_OUT` file): `DICOMFLOW_MWL`, `_DICOMWEB`, `_FHIR`,
`_HL7`, `_PROTO`, `_PCAP`, `_VALIDATE`, `_QR`, `_DECODE`, `_KEYCHAIN`, `_TIMEOUT`.
See `docs/TESTER-TOOLS.md`. **`scripts/verify.sh`** runs xcodegen + the XCTest
bundle (`Tests/`, 22 logic tests) + the app build + all hooks in one command
(peers auto-skipped when unreachable); `--fast` = unit tests only.

## Conventions

- **XcodeGen** (`project.yml` → generated `.xcodeproj`, not committed).
- **Apple Silicon only** (arm64), **macOS 26+** (Liquid Glass UI; the native libs
  are built with a 14.0 floor but the app target requires 26).
- Distribution: signed+notarized DMG via `scripts/notarize.sh`; unsigned local
  builds work out of the box (App Sandbox stays on).

## History — the v1 Python sidecar

v1 (milestones M1–M7) used a bundled Python sidecar (FastAPI + pydicom +
pynetdicom) over loopback HTTP, with pixel volumes passed via an mmap'd temp file.
It worked and produced an ad-hoc `.dmg`, but the App Sandbox forbids spawning a
bundled interpreter subprocess, so it was replaced by the in-process DCMTK engine
(N1–N6). The `sidecar/` directory remains for reference only and is not built or
shipped. See `docs/DECISIONS.md`.
