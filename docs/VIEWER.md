# DicomFlow — Viewer

The Viewer mode: 2D slices, MPR, and GPU volume rendering (Metal). Open a DICOM
**folder** (series scan + rail) or a **single file** — Structured Reports render
as text, multi-frame files (US clips, enhanced CT/MR) become a full scrollable
stack, single images load standalone.

## Layouts
- **2D** — single plane, switchable **Axial / Coronal / Sagittal** (segmented
  picker or A/C/S keys). Slice scrubber + cine.
- **MPR** — Orthanc-style 2×2 (axial · coronal · sagittal · 3D), linked
  crosshair. Panes are color-coded: **Axial = blue, Coronal = green,
  Sagittal = amber** (a plane's border color is also the color of its crosshair
  line in the other panes); **3D = purple** (a deliberate non-plane accent). The
  3D quadrant carries a compact **render-mode switcher** (MIP · MinIP · X-Ray ·
  Volume · Surface) centered along its bottom edge, since the bottom bar has no
  3D controls in this layout.
- **3D** — arcball (default) or turntable rotation (Settings → Interaction);
  quaternion camera; **MIP · MinIP · X-Ray (DRR) · Volume (TF) · Iso-Surface**;
  per-axis clip planes; fixed world-space key light; transfer-function preset
  gallery; A/P/L/R/S/I view presets; recenter & fit.
- **Compare** — side-by-side of two series (axial). Left = the loaded volume;
  right loads a second series from the **same study** (menu) or an external
  **file/folder**. Each pane scrolls + right-drag-W/L on its own; the bottom-bar
  **Sync** toggle links slice scrolling. The right pane's ⋯ menu changes/removes
  its series. Opening a new study clears the compare pane.

## Tools (2D)
| Tool (key) | Action |
|---|---|
| Window/Level (1) | drag = C/W. **Right-drag = W/L with any tool** |
| Pan (2) | drag pans; ⌥-drag also pans in 3D |
| Probe (3) | hover HU readout |
| Measure (4) | drag a distance (mm) |
| ROI (5) | drag a rect → mean/σ/min/max HU, area, voxel count + **48-bin HU histogram** |
| Angle (6) | three clicks (point → vertex → point) → degrees, in physical mm space |

Finished measurements **commit as annotations** pinned to their plane + slice
(they survive rotate/flip and re-appear when you scroll back). The bottom-bar
**list button** (count badge) opens the measurements panel: value, plane/slice,
click-to-jump, delete, clear all. Loading a new volume clears them.

## Keyboard
| Key | Action |
|---|---|
| ← → ↑ ↓ | previous / next slice |
| Space | cine play/pause (follows the current plane) |
| 1–6 | select tool |
| A / C / S | axial / coronal / sagittal (2D layout) |
| I | invert grayscale |
| R | reset zoom/pan (2D/MPR) · reset camera (3D) |
| O | toggle corner info overlays |

Scroll = slice (trackpad-accumulated); **hold ⌘ or ⌃ while scrolling for fine
scrubbing** (4× the travel per slice — frame-accurate in a thick stack); pinch =
zoom; the input-device profile (Settings → Interaction) tunes scroll/zoom
behavior. The MPR crosshair follows the drag live (mouse and trackpad). A **⚙︎
Settings gear** sits at the top-right of the toolbar in both app modes.

Everything above is also in the menu bar: **File → Open (⌘O) / Open Recent**
(recent studies persist across launches; also shown under the empty state),
**Image →** slice/cine/invert/overlays/reset, and **Help → Keyboard & Gestures**
(⌘/) — a full reference of every key and gesture. `.dcm`/`.dicom` files open the
viewer from Finder (double-click / `open`).

A **status line** runs along the foot of the window: a green **Ready** dot when
idle, or three accent dots pulsing with **Loading… / Loading full-resolution
slices…** during a load/refine. It's the single, global load indicator (no
per-pane spinner); modality·dimensions live in the info strip above.

## Windowing & handoff
- **W/L presets** are modality-aware — CT presets (Soft Tissue / Bone / Lung /
  Brain) only for CT; every modality also offers **Full range** (windows to the
  volume's actual value range). Right-drag adjusts W/L with any tool.
- **Send to PACS…** (viewer overflow menu) hands the current series to the
  Tester's C-STORE with the files pre-loaded — no re-picking the folder.

### 3D rotation (Settings → Interaction → 3D volume)
- **Arcball (free)** — *default*. Grab the surface and turn it freely; tumbles in
  all directions (can roll on diagonal drags). Best for free inspection.
- **Turntable (upright)** — horizontal yaws about the vertical (superior) axis via
  absolute azimuth/elevation angles (drift-free, deterministic), vertical tilts
  clamped off the poles, and it never rolls (stays upright). Locked-in feel.

Trackpad two-finger orbit ignores the inertial (momentum) tail, so the volume
stops when your fingers lift instead of drifting.

## Responsive chrome
The docked bottom control bar adapts to the window width in tiers: **full**
(≥1320pt, inline W/L + presets, 3D shows the TF gallery / iso slider / A-P-L-R-S-I
view buttons), **compact** (≥1060pt), and **min** (narrower). In the min tier the
wide groups fold into popovers — **W/L** becomes a `C… W…` chip, and the 3D
**view presets / transfer function / iso** collapse into a menu + palette/iso
popovers — so the whole toolbar fits a **split-screen half** (window minimum
820×600) without scrolling. If it still can't fit, the bar scrolls horizontally
rather than clipping.

## Overlays & export
- **Corner overlays** (toggle O): W/L + zoom top-right; plane, slice i/N and mm
  position bottom-left.
- **Export PNG** — offscreen 1024² render of the current plane/slice.
- **Export Movie** (🎬) — 2D: H.264 slice sweep along the current plane (12 fps);
  3D: 360° MIP turntable (24 fps).

## Data support
- Codecs: uncompressed / JPEG / JPEG-LS / RLE / **JPEG 2000** (fmjpeg2koj +
  OpenJPEG). 16-bit grayscale native; 8-bit grayscale widened.
- **Color images** (US color Doppler, RGB/YBR secondary capture) display **in
  color** in a dedicated 2D path — one RGB frame at a time, fit-to-window, with a
  frame scrubber + cine (Space / ← →) for multi-frame clips. Grayscale MPR/3D/W-L
  don't apply to them. (YBR_FULL is converted to RGB; compressed color arrives as
  RGB after decompression.)
- **Multi-frame** grayscale files expand into a stack (synthetic positions along
  the slice normal; per-frame functional-group positions not parsed yet).
- **Open from Finder:** `.dcm`/`.dicom` files are registered (UTI `org.nema.dicom`)
  — double-click or `open file.dcm` launches the viewer with the file loaded.
- **SR** (Structured Reports) render as text via DSRDocument — from the series
  rail, or by opening/dropping the SR file directly. Read with relaxed flags
  (accept-unknown-relationship, ignore-relationship-constraints,
  ignore-content-item-errors, skip-invalid-content-items) so strict real-world
  SRs (e.g. Philips X-Ray/CT Radiation Dose SR) render instead of being rejected.
  SR series show a report glyph (`doc.text.below.ecg`) in the rail and view.
- Multi-series folders: rail with middle-slice thumbnails; SCP/Q-R/DICOMweb
  handoffs can preselect a series.

## Performance notes
- Volume lives on the GPU as an `r16Snorm` 3D texture (int16 uploaded directly);
  the int16 copy is retained for exact CPU probing/ROI statistics.
- Progressive load: series ≥48 slices show a coarse every-Nth preview (~1 s),
  then the full resolution swaps in ("Loading…" indicator).
- Decode is deliberately serial — DCMTK serializes on its global dictionary
  lock (measured ~1.05× with 12 cores), so parallel decode is a no-op.
- Rendering is GPU-cheap (~2–3 ms/frame live); cine runs only while playing.
- ROI statistics are computed once (cached on the committed annotation; the
  active ROI computes in the drag gesture) — never re-scanned in a SwiftUI body,
  and the min/max + 48-bin histogram share a single voxel pass.
- The 3D ray-caster only redraws when a render-relevant input changes, so an MPR
  crosshair drag doesn't re-render the 3D quadrant.
- A new load cancels the previous in-flight decode `Task` (checked before apply)
  so a slow stale series can't overwrite a newer one.
