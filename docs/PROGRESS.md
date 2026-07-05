# DicomFlow — Progress Log

Status snapshot of every milestone, what was built, and how it was verified.
Last updated: 2026-07-03.

## Summary

| Phase | Milestone | Status |
|------:|-----------|--------|
| M1 | Skeleton app + sidecar handshake | ✅ done |
| M2 | File load + tag viewer | ✅ done |
| M3 | 2D slice viewer + MPR | ✅ done |
| M4 | 3D volume rendering (MIP + transfer function) | ✅ done |
| M5 | Networking toolkit (echo/store/Q-R + test SCP) | ✅ done |
| M6 | Tag editor + anonymizer | ✅ done |
| M7 | Packaging (Developer ID / direct `.dmg`) | ✅ done (ad-hoc verified); ⛔ superseded by App Store path |
| N1 | DCMTK xcframework + bridge (native) | ✅ done |
| N2 | Native series decode → Metal volume | ✅ done |
| N3 | Native tag edit + anonymize | ✅ done |
| N4 | Native networking + SCP | ✅ done |
| N5 | Swap UI to native engine; remove Python | ✅ done |
| N6 | App Sandbox + App Store packaging | ✅ done (code); upload is a user step |

**The app is now fully native** (SwiftUI + Metal + DCMTK in-process) — no Python,
sandbox-clean, App-Store-eligible — with a modern macOS 26 Liquid Glass UI and an
expanded feature set (see UI phases below).

### UI + features (macOS 26 Liquid Glass)
| Phase | Result |
|------:|--------|
| A | ✅ min target macOS 26; `Sources/DesignSystem` (Theme + glass components) |
| B | ✅ glass toolbar + window subtitle; grouped tester sidebar; viewer canvas with floating glass control bars + `ContentUnavailableView` |
| C | ✅ all tester tools restyled (ToolHeader/Card/StatusPill/glass buttons) |
| D | ✅ viewer power tools: HU probe, zoom/pan, invert, cine, distance measure, export PNG |
| E | ✅ study/series browser: fast `scanSeries`, thumbnail rail, multi-series, metadata overlay |
| F | ✅ 3D: per-axis clip planes, gradient (Phong) lighting, TF preset gallery |
| G | ✅ saved PACS profiles, Settings (⌘,), drag-&-drop, DIMSE activity console, app icon, welcome screen |

### Post-G refinements (UX pass, 2026-06-30)
Driven by hands-on use; each item built, installed, and re-verified.
- **3D camera** — iterated center-axis turntable → **arcball** (grabbed surface
  follows the drag, direct-manipulation; horizontal flipped to match fingers);
  **upright anterior default**; **A/P/L/R/S/I** presets; **⌥-drag pan** (camera
  look-at target), pinch/scroll zoom; **Recenter & fit** button (refit distance +
  recenter target + reset to anterior).
- **3D lighting** — Volume/Surface use a **fixed world-space key light** (not a
  headlight) so rotation reads the same as MIP (highlights sweep across the form).
- **Render modes** — MIP · MinIP · X-Ray/DRR · Volume(TF) · Iso-Surface (iso slider).
- **2D/MPR** — mouse-wheel slice scroll, rotate-90 + flip H/V, Orthanc-style 2×2
  with color-coded zones + linked crosshair.
- **Input device** — Settings → Interaction: Auto/Mouse/Trackpad + natural-scroll;
  trackpad two-finger drag orbits (precise-scroll slice accumulation in 2D).
- **Chrome** — visible window-toolbar stripe (canvas no longer floats under it);
  removed the DCMTK status pill; **docked bottom bar** that always fits via
  `ViewThatFits` density tiers (secondary tools → "…" overflow, then compact
  sliders, then compact slice index) — never clips/scrolls; **patient/series info
  strip below the toolbar** (was the toolbar subtitle).
- **Tester** — responsive form fields (TargetForm + Q/R filters fill width);
  tool detail centered. **DICOMweb** tool added (QIDO-RS query, WADO-RS retrieve →
  viewer, STOW-RS store; pure URLSession). Backlog of further tester features in
  `docs/BACKLOG.md` (protocol inspector, MWL, HL7, MPPS/StgCmt, validator, …).
- **Other** — viewer state (series, layout) persists across Tester↔Viewer
  switches; **SR (Structured Reports)** open as rendered text (DSRDocument).
- **Performance** — volume GPU texture `r32Float`→**`r16Snorm`** (half the GPU +
  transfer memory, no float-conversion temp; shaders decode `sample*32767`, output
  pixel-identical); **cached** the 3D transfer-function LUT (was re-allocated per
  SwiftUI update); **progressive load** (coarse every-Nth-slice preview → full res)
  cuts time-to-first-image ~5 s → ~1 s, with an inline "Loading…" status next to
  the slice readout (and a corner spinner in MPR/3D) while the full-res volume
  decodes. A headless **`DICOMFLOW_PERF`** hook reports the numbers: live
  rendering is GPU-cheap (~2–3 ms; the ~35 ms offscreen figures are PNG readback),
  so the only heavy step is the one-time DCMTK decode (~5 s/123 slices).
  **Parallel decode was tried and rejected**: a clean in-process A/B measured
  **~1.05× on 12 cores** — DCMTK is built with threads (`DCMTK_WITH_THREADS=ON`)
  but serializes on its global data-dictionary lock per parsed element, so a
  "parallel decode" setting would be a no-op; decode stays serial and progressive
  load handles the perceived wait.

Verified: real CT renders (2D/MPR/lit 3D, all 5 modes), edit/anon, loopback echo/store/SCP,
multi-series scan, SR text extraction, and the Release/App-Store build all pass. The M1–M7 Python-sidecar work was the v1 path;
it has been replaced by the native DICOM engine (`Sources/DicomEngine` +
`Sources/DicomNative`).

### Native verification (N2–N6)
- **N2** — native decode→Metal: geometry identical to the old path; MIP render
  pixel-identical. Codecs: uncompressed + JPEG + JPEG-LS + RLE decode (verified on
  pydicom samples). JPEG2000 not supported (OpenJPEG pending).
- **N3** — edit changed PatientName, blocked `Rows`; anonymize remapped 98 UIDs
  consistently (series stable + changed-from-orig, SOPClassUID preserved).
- **N4** — C-ECHO/C-STORE verified cross-process (native↔Python both directions)
  and loopback (echo 0, store 96/96, SCP received 96). Fixed: assoc-config profile,
  blocking SCP, and `dcmDisableGethostbyaddr` (reverse-DNS hang). C-FIND/MOVE/GET
  use the same DcmSCU (live-PACS check pending Orthanc creds).
- **N5** — no sidecar bundled, no Python child process; native volume decode works
  through the new `DicomEngine` wiring.
- **N6** — App Sandbox entitlements; **builtin DICOM dictionary verified** (names
  resolve with no external file); security-scoped file access; Release
  builds unsigned by default (distribution signing moved to scripts/notarize.sh); Release compiles.

### Tester feature expansion (2026-07-01)
Each tool was built, installed, and **verified via a headless hook** (see
`docs/TESTER-TOOLS.md`) — not just compiled.

| Tool | Files | Verified |
|------|-------|----------|
| **DICOMweb** | `DicomWebClient`, `DicomWebView` | QIDO 2 studies, WADO 96 instances (Orthanc) |
| **Protocol Inspector** | `DCMTKLog`, `ProtocolLog`, `ProtocolInspectorView` | Full A-ASSOCIATE/DIMSE dump on a C-ECHO |
| **MWL C-FIND** | `DCMTKNet.worklistQueryHost`, `WorklistView` | 3 worklist items decoded end-to-end (Orthanc worklist enabled) |
| **HL7 (MLLP)** | `HL7.swift`, `HL7View` | ADT^A01 send → listener auto-ACK (AA), loopback |
| **Validator** | `DCMTKBridge.validateFile`, `ValidatorView` | Clean CT / non-DICOM error / broken file (8 errors) |
| **Compare** | `DiffView` | Tag diff (same/changed/only-A/only-B) |
| **FHIR** | `FHIRClient`, `FHIRView` | 100 ImagingStudy resources (public HAPI R4) |
| **.pcap/.pcapng import** | `PcapParser`, Protocol Inspector | 6 PDUs dissected from synthetic pcap **and** pcapng |

Deferred (no test peer against the author's test PACS): **MPPS** (Orthanc has no MPPS SCP) and
**Storage Commitment** (`DcmSCU` lacks N-ACTION + needs async N-EVENT-REPORT).
Orthanc `worklists` plugin enabled + 3 sample `.wl` +
`DicomAlwaysAllowFindWorklist` (recorded in the vault `Orthanc.md`).

### Hardening pass (2026-07-02)
From a project-wide improvement analysis; each item built, verified, committed.

| Item | Result |
|------|--------|
| **DIMSE timeouts** | every SCU gets connect/ACSE/DIMSE timeouts (Settings, default 15 s). Dead host: echo returns in exactly 5 s (was ∞). MWL regression OK. |
| **Cancellation** | Cancel buttons — DICOMweb (aborts URLSession), Q/R (generation guard). `Task.checkCancellation` in WADO/STOW loops. |
| **Keychain credentials** | DICOMweb passwords per-server in the Keychain, saved only after a successful op. Roundtrip hook passes. |
| **Unit tests + verify.sh** | `DicomFlowTests` (22 logic tests: PcapParser/HL7/DicomWebClient) + one-command `scripts/verify.sh` (8/8 incl. live Orthanc). |
| **Q/R series drill-down** | per-level return keys in the bridge; series table + series-level retrieve. First live DIMSE C-FIND vs Orthanc (AE registered, user-authorized): 2 studies, series "#1 CT · 96 inst". |
| **pcap DIMSE decode** | command PDVs decoded (command name, MsgID, status, SOP class); timeline colored by command. |
| **JPEG 2000** | vendored fmjpeg2koj + OpenJPEG static; 10/10 16-bit pydicom J2K files decode **pixel-exact vs pydicom** (8-bit = pre-existing engine limit). |

### Improvement batches 2–3 + TLS + viewer expansion (2026-07-02)

| Item | Result |
|------|--------|
| **8-bit decode** | grayscale widened, color→luma; J2K corpus 13/14; crafted fixtures exact (luma 76) |
| **DICOMweb depth** | series drill-down + instance QIDO + /metadata + /rendered (all live vs Orthanc; Orthanc rejects multi-value Accept) |
| **HL7 field inspector** | HL7.parse → named segment/field tree; Fields\|Raw toggle; 25 unit tests |
| **Protocol Inspector grouping** | association sections + →/← arrows; grouping O(n²)→O(n) |
| **All-modes consistency** | Return-to-run, TableExport everywhere, Cancel everywhere, FHIR auth+Keychain, cine timer only-while-playing |
| **ROI + angle** | exact voxel stats (phantom 40.0/−1000.0), mm-space angle |
| **DICOM TLS** | OpenSSL DCMTK rebuild; BCP 195 on all SCU paths; verified incl. cert verification via local TLS proxy (10/10 suite) |
| **Viewer batch 1** | A/C/S plane picker (ROI exact on all 3 planes), keyboard shortcuts, right-drag W/L, corner overlays |
| **Viewer batch 2** | multi-frame → full stack (emri 10-frame → nz=10); movie export validated via AVFoundation |
| **Viewer batch 3** | persistent annotations + list popover; ROI HU histogram |
| **SR open fix** | single-file open/drop; SRs render directly (were rail-only) |
| **Viewer UX polish** | Settings gear in toolbar (both modes); MPR crosshair live-drag; 3D orbit momentum removed; **3D rotation mode** setting (Arcball / Turntable, verified roll=0.0000); mode-switch toolbar reflow fixed (content-scoped cross-fade, toolbar snaps) |
| **Codebase review pass** | 4-reviewer audit → 6 fix batches: bridge (DCMTK response leaks freed, storeFiles success honest, pid==0 guards, gSCP/DCMTKLog races locked); Swift (HL7 port crash, security-scoped leaks, error surfacing, viewer load-task cancellation); perf (ROI stats cached + single voxel pass, 3D redraw gated, BGRA fast-path); hygiene (deleted sidecar-era DTOs + dead Volume mmap init, doc drift); consistency (shared basic-auth, W/L helper, Tag Inspector copy/export) |
| **SR strict-read fix** | real-world SRs (Philips X-Ray/CT Radiation Dose SR) were rejected by DSRDocument's default validation ("Invalid Value") → read with relaxed flags; verified the CT-sinus dose SR now renders the full content tree (DLP, irradiation events, CTDIvol). SR icon → `doc.text.below.ecg` in view + rail |
| **Viewer status line** | one persistent foot-of-window status line (green "Ready" ↔ animated three-dot "Loading…", modality+dims on the right) replacing the floating/inline refine spinners |
| **MPR 3D render-mode chips** | compact MIP/MinIP/X-Ray/Volume/Surface switcher along the bottom-centre of the MPR 3D quadrant (the bottom bar has no 3D controls in MPR) |
| **MCP server (agent tool)** | standalone `dicomflow-mcp` (stdio JSON-RPC) reusing the DCMTK bridge; read/network-read tools incl. **`dicom_render_slice`** (CPU-windowed PNG + oblique/coronal/sagittal reslice, color-aware) + `dicom_web_query` (QIDO); **3 write-gated tools** (`store`/`retrieve`/`anonymize`, only with `--allow-write`); `scripts/build-mcp.sh` + `docs/MCP.md` for Claude Desktop/Code. Verified end-to-end incl. live Orthanc echo/C-FIND/QIDO, rendered CT reslices, and an anonymize round-trip |
| **Multi-modality + color + open** | tested MR (LE/RLE/JPEG-LS), multi-frame MR, ultrasound (uncompressed + J2K), RGB/YBR — all decode; **color images now display in color** (US Doppler, RGB/YBR) via a dedicated 2D path (frame scrubber + cine); `.dcm`/`.dicom` registered so Finder double-click / `open` launches the viewer |
| **Responsive/split-screen toolbar** | bottom bar tiers by window width (full/compact/min) with W/L + 3D view/TF/iso folding into popovers; scrolls rather than clips; window min lowered to 820×600 so it fits a split-screen half |
| **UI/UX review + menus batch** | 3-agent review (UX/accessibility/visual); implemented batch 1 — menu-bar commands (File: ⌘O Open + persisted Open Recent; Image: slice/cine/invert/overlay/reset; Help: ⌘/ Keyboard & Gestures cheat-sheet + re-openable Welcome); shortcuts moved off the global key monitor to focus-respecting menu commands |
| **Accessibility batch** | VoiceOver on the 2D/MPR canvases (plane/modality label, "Slice N of M" value, adjustable slice); series cards + TF swatches → Buttons w/ .isSelected; W/L slider labels+values; MPR/RenderMode chip text picks black/white by luminance (AA contrast); Reduce-Motion honored (loading dots); help()→hint() on icon buttons. On-device VoiceOver pass still needed to confirm announcements |
| **Visual polish batch** | status line no longer duplicates modality·dims (info strip owns it) + aligned + generic "Loading…"; wide bottom bar decluttered (rotate/flip → overflow menu at all widths); dead glassBar/glassCircle helpers deleted; annotation badge black-on-teal (AA); Save button → .glassProminent |
| **Workflow batch** | viewer "Send to PACS…" hands the current series to the Tester's C-STORE (currentFiles → pendingStorePaths); drag-drop added to Tag Inspector + C-STORE; W/L presets modality-aware (CT only) + "Full range" for any modality; DIMSE "Cancel" → honest "Dismiss" ("keeps running in the background") |
| **DS chip radius token** | `Theme.Radius.chip = 6` replaces the 10 scattered raw `cornerRadius: 6` literals |
| **Test SCP restart fix + TLS** | fixed the socket leak (blocking `accept()` + `stopSCP` detach) → DUL_NOBLOCK + stop hooks + join, so it restarts on the same port; re-added server-side TLS (self-signed cert). Verified by `SCPTests` (receive · 3× restart · TLS loopback + plaintext-refused) via `xcodebuild test`. The earlier "config broken" was a `.task` multi-fire harness artifact — the config was fine |

## What was verified (not just compiled)

Verification was done headlessly (terminal screen-capture is blocked in this
environment), by inspecting real outputs:

- **M1** — App launches the bundled sidecar as a child, loopback handshake
  (`{port, token}`), `/health` returns 401 without token / 200 with; parent-death
  watchdog kills the sidecar when the app quits.
- **M2** — `/tags/read` returned 262 tags w/ VR on `CT_small.dcm`; 400 on bad path.
- **M3** — Rendered axial/coronal/sagittal PNGs of a synthetic phantom: correct
  geometry, HU windowing (40 HU → 0.5 gray), aspect-correct anisotropy
  (2 mm z vs 1.5 mm in-plane elongates the sphere as it physically should).
- **M4** — Rendered 3D MIP and transfer-function PNGs: soft-tissue sphere + bright
  bone cube, correct perspective; JPEG2000 MR decoded via pylibjpeg.
- **M5** — Built-in SCP start → C-ECHO `0x0000` → C-STORE 96/96 → SCP received 96.
  (C-FIND/MOVE/GET implemented; need a real PACS like Orthanc to verify.)
- **M6** — Edit changed PatientName, blocked `Rows` (pixel geometry). Anonymize:
  98 UIDs consistently remapped (study/series stable + changed-from-original,
  SOPClassUID preserved, SOP instances distinct).
- **M7** — PyInstaller sidecar runs standalone (health + uncompressed + JPEG2000
  decode, no venv). Packaged `.app` launches the bundled sidecar from inside the
  bundle; ad-hoc `.dmg` produced and signed (valid, satisfies Designated Req.).
- **N1** — DCMTK 3.6.9 built as `DCMTKit.xcframework`; linked into the app;
  `DCMTKBridge.readTags` returned 262 tags on `CT_small` (matches pydicom) and
  correct values on the synthetic CT — all native, no Python.

## How to re-verify (native)

```bash
cd DicomFlow

# One-time: build the DCMTK framework (builtin dictionary)
bash native/build-dcmtk.sh

# Synthetic test volume (dev-only Python script)
python3 sidecar/tools/make_fixture.py /tmp/dicomflow_fixture 96

# Build + run
xcodegen generate
xcodebuild -project DicomFlow.xcodeproj -scheme DicomFlow -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/DicomFlow.app

APP=build/Build/Products/Debug/DicomFlow.app/Contents/MacOS/DicomFlow
DICOMFLOW_NATIVE_TAGS=/tmp/dicomflow_fixture/slice_000.dcm "$APP"     # native tag read
DICOMFLOW_NATIVE_VOLUME=/tmp/dicomflow_fixture "$APP"                  # MPR/MIP/volume PNGs
DICOMFLOW_NATIVE_EDITANON=/tmp/dicomflow_fixture "$APP"               # edit + anonymize
DICOMFLOW_NATIVE_NET=/tmp/dicomflow_fixture "$APP"                     # loopback SCP echo/store
```

## Outstanding

- **Publish** — sign + notarize + DMG via `scripts/notarize.sh` (needs a Developer
  ID Application certificate).
- **8-bit pixel decode** — the decode path is 16-bit-only (8-bit US/SC files are
  rejected across all codecs); see `docs/BACKLOG.md` for the rest of the
  improvement backlog.

Resolved earlier entries: ~~JPEG2000 input~~ (fmjpeg2koj + OpenJPEG, 2026-07-02,
pixel-exact) · ~~Orthanc Q/R live test~~ (AE registered, C-FIND verified 2026-07-02).
