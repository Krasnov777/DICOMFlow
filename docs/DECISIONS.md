# DicomFlow — Decision Log

Key decisions and the reasoning behind them, newest last.

## 1. Greenfield native app, reuse the old idea (not the code)
The prior app (`../`) was Tauri + React + Flask that only did C-ECHO, C-STORE,
and read-only tags — no Q/R, no editing, no anonymizer, **no image rendering**.
We kept the *idea* and the Python DICOM logic, but built a new native app.

## 2. Initial stack (user choices)
- **UI/shell:** Native **SwiftUI + Metal** — best path to high-quality 2D/3D.
- **DICOM I/O (v1):** **Python sidecar** reusing pynetdicom/pydicom — lowest risk,
  robust compressed-codec decode.
- **Tester scope:** full toolkit (echo/store/find/move/get + built-in SCP +
  tag editor + anonymizer).
- **Viewer scope:** CT-first, MR/PET-aware.

## 3. Pixel decode in the sidecar (Option A), not Swift
The viewer needs decoded volumes. Decoding compressed transfer syntaxes
(JPEG2000/JPEG-LS) natively in Swift means vendoring C codecs into a notarized
app — the biggest risk for little gain. So the sidecar decodes and hands raw
int16 buffers to Swift via an mmap'd temp file. (This later conflicts with the
App Store — see #6.)

## 4. IPC = loopback HTTP + token (not stdio JSON-RPC)
Keeps the old Flask endpoint shapes, gives multipart upload and (future) SSE for
free, and is trivial to authenticate (ephemeral port + bearer token).

## 5. v1 packaging = Developer ID `.dmg`  *(SUPERSEDED by #9)*
PyInstaller bundled the sidecar into a standalone binary; `package.sh` signed
(inner→outer) and built a `.dmg`. Replaced by App Store packaging once we went
native — those scripts (`package.sh`, `build_sidecar.sh`, `make_dmg.sh`) have been
removed.

## 6. PIVOT (2026-06-28): target the **Mac App Store** → native DCMTK
The user decided to ship on the Mac App Store. The Python sidecar is
**incompatible with the App Sandbox**:
- sandboxed apps can't spawn a bundled interpreter subprocess (routinely rejected),
- it needed disallowed hardened-runtime entitlements
  (`disable-library-validation`, `allow-unsigned-executable-memory`),
- the child process couldn't inherit the app's user-selected-file grants.

The project started App-Store-first, which shaped the architecture. So for DicomFlow:

- **Replace the Python sidecar with DCMTK compiled in-process** (one sandboxed
  process), using a static **C++ xcframework pattern**. DCMTK is BSD-style licensed — App-Store-safe.
- Keep all Metal + SwiftUI work unchanged.
- Reuse the existing Apple Distribution cert; **no Developer ID needed**.
- Caveat: open-source DCMTK lacks **JPEG2000** → add **OpenJPEG** for JP2K.

Alternatives rejected: pure-Swift DICOM lib (weak codec/networking coverage);
embedding libpython in-process (fragile signing of codec `.so` plugins under
sandbox + library validation).

**Outcome (done, N1–N6):** the native DCMTK engine fully replaced the Python
sidecar. `Sources/DicomNative` (DCMTKBridge + DCMTKNet) is the only C++ seam;
`Sources/DicomEngine` is the Swift API the UI uses. v1's Developer-ID `.dmg`
packaging (decision #5) is superseded by App Store packaging (#9). The `sidecar/`
Python tree is retained for reference only and is not built or shipped.

## 7. Target hardware / OS
Apple Silicon only (arm64), macOS 14+. Matches the user's other macOS apps; halves
packaging effort vs a universal binary.

## 8. DCMTK build & runtime gotchas (learned during N1–N6)
- **Use DCMTK-3.6.9, not 3.6.8** — 3.6.8's `OFrvalue`/`ofutil.h` fails to compile
  with Xcode 26's clang/C++ standard.
- **Builtin dictionary is mandatory for the sandbox.** `DCMTK_ENABLE_BUILTIN_DICTIONARY`
  is ignored; the real options are `-DDCMTK_DEFAULT_DICT=builtin -DDCMTK_USE_DCMDICTPATH=OFF`.
  Without them, DCMTK loads the dictionary from a build-path file that doesn't exist
  on other machines / under the sandbox, and tag names degrade to "Unknown".
- **Storage SCP gotchas:** configure accepted contexts via a generated
  association-config profile (`loadAssociationCfgFile` + `setAndCheckAssociationProfile`),
  run `listen()` in **blocking** mode on a background thread, and set
  **`dcmDisableGethostbyaddr`** — otherwise each incoming association blocks on a
  reverse-DNS lookup and the server appears to hang.
- **Same-process SCU+SCP** works once reverse-DNS is disabled (the loopback test SCP).

## 9. Packaging
App Sandbox on; only `network.client` / `network.server` / `files.user-selected.read-write`
entitlements (no JIT / library-validation exceptions — nothing to load at runtime).
Static-linked DCMTK means a single signed binary. Distribution builds are
maintainer-signed via `scripts/notarize.sh` (Developer ID + notarization);
the repo itself builds unsigned so anyone can compile it.

## 10. JPEG2000 deferred  *(RESOLVED by #12)*
Open-source DCMTK can't decode JPEG2000. Shipping v1 with uncompressed/JPEG/JPEG-LS/RLE
(covers the large majority); OpenJPEG integration is a tracked follow-up, not a
publish blocker.

## 11. Tester expansion — verify-before-ship; import-only pcap; MPPS/StgCmt deferred
(2026-07-01) Built out the Tester suite: DICOMweb, Protocol Inspector, MWL, HL7
(MLLP), Validator (+ module IOD checks), Compare, FHIR, and .pcap/.pcapng import.
Guiding rules from this batch:
- **Ship only what we can verify.** Each tool has a headless hook and was tested
  against a real peer (Orthanc, HAPI) or a crafted fixture before committing. When a
  feature couldn't be verified against the author's test PACS it was **deferred, not shipped blind**.
- **MPPS / Storage Commitment deferred.** MPPS is implementable (`DcmSCU` has
  N-CREATE/N-SET) but Orthanc offers no MPPS SCP to test against. Storage Commitment
  additionally lacks a `DcmSCU` N-ACTION (would need low-level DIMSE) and an async
  N-EVENT-REPORT receiver. Both stay in the backlog with the blocker recorded.
- **.pcap import, not export.** The Protocol Inspector captures DCMTK's *text* log,
  not raw wire bytes, so a real `.pcap` can't be written. Import + PDU dissection is
  the valuable, feasible direction; live BPF capture is sandbox-blocked anyway.
- **Web/messaging clients are pure Swift** (URLSession / Network.framework), kept out
  of the DCMTK bridge — smaller C++ seam, easier to reason about, no DIMSE coupling.

## 12. Hardening pass (2026-07-02) — timeouts, Keychain, tests, J2K
- **Timeouts are not optional.** DCMTK's default is to block forever; every outgoing
  SCU now gets connect/ACSE/DIMSE timeouts from one Settings knob (default 15 s).
  DIMSE calls run in `Task.detached` and can't be interrupted mid-call, so UI cancel
  uses a generation guard (unblock + discard result) while web ops cancel for real.
- **Credentials live in the Keychain**, keyed per server (account = base URL), and
  are saved only after a successful operation so wrong passwords never persist.
- **Logic tests are a standalone bundle** (no TEST_HOST — the Debug app is unsigned)
  that compiles the pure sources directly. Both the app and the test bundle build
  unsigned in Debug: codesign rejects the FileProvider xattrs iCloud puts on fresh
  dirs under `~/Documents`. `scripts/verify.sh` is the one-command gate.
- **JPEG 2000 = vendored fmjpeg2koj + static OpenJPEG** (resolves #10). Sources are
  committed (`native/fmjpeg2k/`, Apache-2.0); OpenJPEG builds like DCMTK via
  `native/build-openjpeg.sh` (gitignored install). Decoder-only registration.
  Verified pixel-exact against pydicom. The decode path now also handles 8-bit
  pixels (grayscale widened, color → Rec.601 luma).
- **Orthanc now knows our AE** (`DICOMBENCH` in `DicomModalities`, user-authorized)
  — the proper alternative to `DicomAlwaysAllowFind`; first live C-FIND verified.
- **SRs read with relaxed DSR flags.** `DSRDocument::read`'s default strict
  content/relationship validation rejected real vendor SRs (a Philips X-Ray
  Radiation Dose SR failed with "Invalid Value"). We read with
  `RF_acceptUnknownRelationshipType | RF_ignoreRelationshipConstraints |
  RF_ignoreContentItemErrors | RF_skipInvalidContentItems` — a viewer should
  render what's there, not enforce IOD conformance (the Validator tool is for
  conformance). Verified the dose SR renders its full content tree.
- **One codebase review pass (2026-07-03)** ran 4 parallel Code-Reviewer agents
  over the whole tree; findings landed as 6 fix batches (bridge correctness, Swift
  correctness, viewer perf, hygiene/dead-code, consistency). Deferred (noted, not
  done): built-in Storage SCP has no TLS so C-MOVE-to-self can't deliver under
  DIMSE-TLS; KeyedRow/LabeledField extraction; MPR crosshair↔volume plane-math
  consolidation; FHIRClient.flatten + ArcballCamera unit tests.
- **UI/UX reevaluation (2026-07-03)** — 3 review agents (UX / accessibility /
  visual) → 4 fix batches: menu-bar commands (⌘O + Open Recent, Image menu,
  ⌘/ Keyboard & Gestures) so the hidden shortcuts/gestures are discoverable;
  accessibility (VoiceOver on the canvases, real Buttons, slider values, AA
  contrast via luminance-picked chip text, Reduce Motion); visual density
  (de-duped status line, decluttered bottom bar, dead-glass-helper removal);
  workflow (viewer→C-STORE handoff, Tester drag-drop, modality-aware presets,
  honest "Dismiss"). Not done: `.navigationSubtitle` for the info strip (would
  reintroduce the toolbar lurch we removed `.navigationTitle` to fix); on-device
  VoiceOver announce/focus pass (needs a human running VoiceOver).
- **Test SCP restart fix + TLS (resolved).** The built-in Storage SCP couldn't be
  restarted on the same port ("Address already in use"): `listen()` ran in
  *blocking* mode sitting in `accept()`, and `stopSCP` detached the thread and
  leaked the bound socket (the `StoppableStorageSCP` subclass merely *called*
  `stopAfterCurrentAssociation()` instead of overriding it). Fix: subclass
  overrides `stopAfterCurrentAssociation()`+`stopAfterConnectionTimeout()` to
  return an atomic flag; `startSCP` uses `DUL_NOBLOCK` + a 1 s connection timeout
  so `listen()` wakes and honors the flag; `stopSCP` joins the thread and frees
  the socket. The SCP's config was *fine all along* — the earlier "config broken"
  reading was a harness artifact (the SwiftUI `.task` fired several times in the
  headless `open -n`, double-loading the association config → "two profiles
  defined"). With the SCP starting reliably, the **server-side TLS** was
  re-added: a self-signed cert (`generateSelfSignedCert`, OpenSSL) on a
  `NET_ACCEPTOR` `DcmTLSTransportLayer` attached via `getConfig().setTransportLayer`
  when global TLS is on — so TLS C-STORE/C-MOVE-to-self work. All verified by
  `SCPTests` (receive, 3× restart, TLS loopback + plaintext-refused) run headlessly
  via `xcodebuild test` — the correct rig, since it's one process with no `.task`
  multi-fire. (C-GET also remains a fine TLS retrieve path — no SCP needed.)
- **OpenSSL statically linked + vendored (2026-07-05) — shipping prerequisite.**
  The app/mcp/tests dynamically loaded Homebrew's `libssl.3.dylib`/`libcrypto.3.dylib`,
  so a shipped build wouldn't launch on any Mac without Homebrew OpenSSL at that
  path (a hard blocker for the App Store *and* any distribution). Fixed by linking
  the static archives (`libssl.a` before `libcrypto.a`) and **vendoring** them into
  `native/openssl/{lib,include}` (matching the already-vendored OpenJPEG/DCMTK/
  fmjpeg2k), so a fresh clone builds without Homebrew. `otool -L` confirms zero
  external openssl/homebrew dylibs; TLS still verified. Remaining App-Store work:
  medical-tool (non-diagnostic) positioning, `ITSAppUsesNonExemptEncryption`
  export-compliance, OpenSSL (Apache-2.0) license acknowledgement, and the App
  Store Connect record + archive/upload under the Apple Distribution cert.
