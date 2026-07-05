# DicomFlow — Tester / Toolbench Tools

The Tester mode (`Sources/TesterUI/TesterRootView.swift`) is a sidebar of DICOM
tools grouped into **Networking** and **Files & Tags**. Each tool is a self-contained
SwiftUI view; networking clients live in `Sources/DicomEngine` (Swift, or via the
`DicomNative` Obj-C++ bridge for DIMSE), protocol/parse helpers in `Sources/AppCore`.

Every tool has a **headless hook** in `App/NativeTest.swift` (gated by an env var,
writes results to a file) so it can be verified without the GUI — see
[Headless verification](#headless-verification).

---

## Networking

### C-ECHO · C-STORE · Query/Retrieve
Classic DIMSE, via `DCMTKNet` (Obj-C++ → DCMTK `DcmSCU`) and `DicomEngine`
(`echo` / `store` / `query` / `retrieve`). Views: `EchoView`, `StoreView`,
`QueryRetrieveView`. Target (host/port/AE/calling-AE) comes from `TesterTarget` +
saved PACS profiles.
- **Series drill-down**: selecting a study auto-runs a SERIES-level C-FIND; a
  second table lists the series, and Retrieve fetches either the whole study or
  just the selected series (C-GET or C-MOVE to the built-in Test SCP).
- The bridge inserts **standard return keys per level** (STUDY/SERIES/IMAGE) —
  C-FIND only returns requested attributes, so empty-filter queries stay populated.
- **Timeouts** (Settings → Networking, default 15 s) bound TCP connect, ACSE, and
  each DIMSE message; a Cancel button unblocks the UI (generation guard — the
  in-flight call ends at the timeout and its result is discarded).
- Hook: `DICOMFLOW_QR=1 QR_HOST/QR_PORT/QR_AE QR_OUT=<file>` (study + series
  C-FIND). Note: Orthanc must know the calling AE — `DICOMBENCH` is registered in
  its `DicomModalities` (see vault `Orthanc.md`).

### Worklist (MWL C-FIND)
`WorklistView` → `DicomEngine.worklistQuery` → `DCMTKNet.worklistQueryHost`.
C-FIND on the **Modality Worklist Information Model**: the query carries top-level
return keys plus a **Scheduled Procedure Step Sequence** item (Modality, Station AE,
scheduled date/time, step description); `mwlItemToDict` flattens each response by
diving into that sequence. Filters: Patient, Modality, Station AE, scheduled date
(ranges OK). Table: patient · modality · date · time · step · station AE · accession.
- **Verified end-to-end** against Orthanc after enabling its `worklists`
  plugin (`Enable: true`, `DicomAlwaysAllowFindWorklist: true`, 3 sample `.wl`).
- Hook: `DICOMFLOW_MWL=1 MWL_HOST/MWL_PORT/MWL_AE MWL_OUT=<file>`.

### Negotiation Probe
`NegotiationView` → `DicomEngine.probeContexts` → `DCMTKNet.probeContextsHost`.
Proposes a matrix of **15 SOP classes × 8 transfer syntaxes** (Explicit/Implicit
LE, Deflated, JPEG Baseline, JPEG Lossless, JPEG 2000 lossless/lossy, RLE) — one
presentation context per pair, so each negotiates independently — then reports
which the peer accepts (`findPresentationContextID` per pair). Accepted-first list
with the transfer syntaxes per SOP class; CSV/TSV export. Honors the global
TLS/timeout settings. A fast "what does this PACS support?" capability map.
- **Verified live** against Orthanc: 114/120 accepted — all storage
  classes take all 8 syntaxes; Verification only the 2 uncompressed (correctly
  rejecting the 6 compressed).
- Test: `SCPTests.testLiveNegotiationProbe` (gated by `/tmp/dicomflow-live`).

### DICOMweb
`DicomWebView` → `DicomWebClient` (pure `URLSession`, no DCMTK).
QIDO-RS query → WADO-RS retrieve (multipart reassembly → viewer) → STOW-RS store.
DICOM-JSON parsing (8-hex tag keys, `{Value,vr}`, PN `[{Alphabetic}]`).
- Orthanc DICOMweb: `http://127.0.0.1:8042/dicom-web`, basic auth `admin` + keychain pw.
- Needs ATS `NSAllowsArbitraryLoads` (Info.plist) for plain-HTTP LAN.
- **Passwords are Keychain-backed per server** (`AppCore/Keychain.swift`, service
  `DicomBench.dicomweb`, account = base URL): loaded on appear/URL change, saved
  only after a successful operation. Requests honor the shared network timeout;
  Cancel genuinely aborts the URLSession call.
- Hook: `DICOMFLOW_DICOMWEB=1 DWB_URL/DWB_USER/DWB_PASS/DWB_OUT`.

### FHIR
`FHIRView` → `FHIRClient` (pure `URLSession`/JSON). `GET {base}/ImagingStudy?…`,
parses the Bundle into a table (patient, started, modality, series, instances,
description, StudyUID). Default base = public **HAPI R4** (`hapi.fhir.org/baseR4`).
- Verified: 100 ImagingStudy resources parsed from HAPI.
- Hook: `DICOMFLOW_FHIR=1 FHIR_URL FHIR_OUT=<file>`.

### HL7 (MLLP)
`HL7View` (Send | Listen) → `Sources/DicomEngine/HL7.swift`.
- **MLLP framing** (`<VT>…<FS><CR>`), MSH parsing, **ACK builder** (`MSA|AA` with
  swapped sending/receiving apps + echoed control id), ADT/ORM/ORU templates.
- **Send**: `HL7Client.send` (Network.framework `NWConnection`) → parses the ACK
  (AA/AE/AR pill).
- **Listen**: `HL7Listener` (`NWListener`) receives messages and auto-ACKs; network
  callbacks are `nonisolated` (hop to `@MainActor` only for `@Published`).
- Default MLLP port 2575. Verified via loopback (ADT^A01 → AA ACK).
- Hook: `DICOMFLOW_HL7=1 HL7_OUT=<file>` (starts a listener + sends to it).

### Test SCP
`LocalSCPView` → `DCMTKNet` `DcmStorageSCP` on a background thread (non-blocking
accept + 1 s poll so stop cleanly releases the socket → restartable on the same
port; reverse-DNS disabled). Receives C-STORE / C-MOVE, lists instances, opens a
received series in the Viewer.
- **Enforce Called AE** toggle (default on) → `setRespondWithCalledAETitle(OFFalse)`:
  refuses associations addressed to a different Called AE ("…Not Recognized").
- **TLS**: when global DIMSE-TLS is on, the SCP presents a self-signed server cert
  (OpenSSL) on a `NET_ACCEPTOR` layer, so TLS C-STORE / C-MOVE-to-self work.
- Verified by `SCPTests` (loopback receive · 3× restart · TLS · Called-AE
  enforcement) + a live Orthanc round trip (C-STORE→C-FIND→C-GET→C-MOVE-to-self).

### Protocol Inspector (+ .pcap import)
`ProtocolInspectorView` — a decoded, Wireshark-style timeline of DICOM traffic.
- **Live self-traffic**: `Sources/DicomNative/DCMTKLog.{h,mm}` is a **log4cplus
  appender** that forwards DCMTK's `dcmnet` log to Swift; `Sources/AppCore/ProtocolLog.swift`
  classifies each line (A-ASSOCIATE-RQ/AC/RJ, A-RELEASE, A-ABORT, C-ECHO/STORE/FIND/
  MOVE/GET, DIMSE) with colored badges. Verbose = `dcmtk.dcmnet` at DEBUG **only**
  (never the root logger — floods with dcmdata decode noise). Capture starts in
  `AppState.boot()`. Hook: `DICOMFLOW_PROTO=1 PROTO_OUT=<file>`.
- **.pcap / .pcapng import** (`Sources/AppCore/PcapParser.swift`): open a capture →
  parse **classic pcap + pcapng** → strip Ethernet / NULL-loopback / RAW / Linux-cooked
  link layers → IPv4/IPv6 + TCP → **reassemble directional streams by sequence** →
  **dissect DICOM upper-layer PDUs**: A-ASSOCIATE-RQ/AC/RJ (AE titles, presentation
  contexts with abstract/transfer syntaxes resolved to names, user info), P-DATA-TF,
  A-RELEASE, A-ABORT. **Command PDVs are decoded down to the DIMSE command**
  (Implicit VR LE command set): command name (all C-*/N-* RQ/RSP), MsgID /
  responded-to id, status (Success/Pending/Cancel), SOP class (named), move
  destination — and the timeline kind/color follows the command. Decoded PDUs feed
  the same timeline via `ProtocolLog.importPDUs`, chronologically.
  Hook: `DICOMFLOW_PCAP=<file> PCAP_OUT=<file>`.
  - **Export N/A**: we only have DCMTK's *text* log, not raw wire bytes, so a real
    `.pcap` can't be written. Text export of the timeline exists (`.log`/`.txt`).
  - Two gotchas that bit during implementation (now fixed): network header fields
    **and** DICOM PDU item-length fields are **big-endian** (`be16`/`be32`); and
    Swift's `dict[key, default: <class instance>]` subscript does **not** persist the
    entry when you only mutate a property — use explicit `if streams[key] == nil`.

---

## Files & Tags

### Tag Inspector
`TagInspectorView` → `DicomEngine.readTags` → `DCMTKBridge.readTags`. Searchable,
sortable table of every element (tag, name, VR, value, keyword), including flattened
sequences.

### Redact Pixels (burned-in text)
`RedactView` → `DicomEngine.renderDisplayImage`/`redact` → `DCMTKBridge.
renderDisplay8`/`redactFile`. De-identifies PHI burned into the *pixels* (ultrasound,
secondary capture, screenshots) — the companion to the tag Anonymizer.
- **DicomImage** renders a windowed 8-bit / RGB preview; **Vision**
  (`VNRecognizeTextRequest`) detects text regions, shown as toggleable red boxes +
  the recognized strings.
- Redact blacks out the enabled regions in the pixel data across **all frames**
  (mono 8/16 + color), decompressing first if needed, sets
  **`BurnedInAnnotation = NO`**, and saves uncompressed; the redacted result is
  re-rendered in place.
- Test: `GeneratorTests.testRedactionZeroesRegion`.

### Dump (raw dataset)
`DumpView` → `DicomEngine.dump` → `DCMTKBridge.dumpFile` (`DcmFileFormat.print`,
`PF_shortenLongTagValues`). The full `dcmdump`-style element tree — file-meta +
dataset, every tag with VR·length·value, sequences indented — the raw wire
structure complementing the Tag Inspector's decoded table. Monospaced + selectable,
with a **line filter**, copy, and export. Long values (Pixel Data) are shortened.

### Tag Editor
`TagEditorView` → `DCMTKBridge.editTags`. Edit/insert/delete elements and write back.

### Anonymizer
`AnonymizeView` → `DicomEngine.anonymize` → `DCMTKBridge.anonymize`. De-identifies a
folder into a new folder with a consistent UID remap, then optionally opens the
result in the Viewer.
- **PS3.15 Basic Application Level Confidentiality Profile** (curated core of Annex
  E Table E.1-1): removes (X) identity / physician / institution attributes, zeros
  (Z) AccessionNumber/StudyID/ReferringPhysicianName/PatientBirthDate, replaces
  PatientName/ID, and stamps `PatientIdentityRemoved=YES` +
  `DeidentificationMethod`.
- Standard **profile options** (toggles): Retain dates & times · Retain device
  identity · Retain patient characteristics · Clean descriptors. Plus independent
  Regenerate UIDs and Remove private tags.
- Test: `GeneratorTests.testBasicProfileAnonymization` (name replaced, StudyDate
  zeroed, descriptor cleaned, de-id flag/method set).

### Validator
`ValidatorView` → `DicomEngine.validate` → `DCMTKBridge.validateFile`.
Conformance report:
- Part-10 file-meta presence; required UIDs (SOP Class / SOP Instance / Study /
  Series) + **UID format**; SOP-class name lookup; meta-vs-dataset SOP consistency.
- **IOD module conformance** via DCMTK's `dcmiod` rule engine (`IODRules`): every
  unconditional type-1/2 attribute of the common composite-IOD modules (Patient,
  Patient Study, General Study/Series/Equipment, SOP Common) + General Image (when
  Pixel Data is present) is checked against its standard rule (present, non-empty
  for type-1, VM/VR). Shown as an "IOD module conformance — N/M present" section
  listing failures (type-1 red, type-2 orange). Frame of Reference is skipped
  (IOD-conditional — DCMTK bundles it with General Series; enforcing it universally
  would false-flag SC/SR/PDF). A type-1 violation flips the overall verdict.
- Per-element **VR verification** (`DcmElement::verify`, capped).
- Verified on a real CT (clean), a non-DICOM file (hard error), and a crafted broken
  file. `ValidatorTests.testIODModuleChecks` covers the rule engine. Hook:
  `DICOMFLOW_VALIDATE=<file> VALIDATE_OUT=<file>`.

### Generator (synthetic DICOM)
`GeneratorView` → `DicomEngine.generateDataset` → `DCMTKBridge.generateDatasetToDir`.
Builds a **stackable phantom series** on demand for testing the viewer / C-STORE /
validator without real patient data:
- **Modality**: CT (signed 16-bit HU, air…dense, slope/intercept + W/L), MR
  (unsigned 16-bit), Secondary Capture (8-bit single frame).
- **Pattern**: sphere (3D-renderable phantom), gradient, rings, checkerboard,
  noise, solid; plus size (px²) and slice count.
- Shared study/series/FoR UID + geometry (ImagePosition/Orientation, PixelSpacing,
  SliceThickness) so it loads as one uniform volume.
- Result actions: **Open in Viewer**, **Send to C-STORE**, **Save a Copy…**.
- `GeneratorTests`: output decodes at the requested dims, validates conformant,
  shares one SeriesInstanceUID across slices.

### DICOMDIR
`DicomDirView` → `DicomEngine.readDicomDir` → `DCMTKBridge.readDicomDir`. Open a
**folder** containing a DICOMDIR (DICOM exchange media — CD/DVD/USB export); its
**Patient → Study → Series** tree is listed and any series opens in the Viewer.
- Walks the `DcmDicomDir` record tree; resolves each instance's ReferencedFileID
  (0004,1500) — its backslash-separated path components — to absolute paths under
  the DICOMDIR's folder. The Viewer's recursive directory scan then loads the
  chosen series by UID (files may be nested in `DICOM/…` subfolders).
- Rejects non-DICOMDIRs up front by checking the Media Storage SOP Class
  (`DcmDicomDir` otherwise fabricates an empty directory).
- `AppState.retainAccess` holds the folder's security scope for the session so the
  Viewer can read the referenced files.
- `DicomDirTests` vs pydicom's dicomdirtests: 2 patients / 6 studies / 13 series /
  31 referenced files all resolve.

### Compare
`DiffView` → `DicomEngine.readTags` for two files, diffed by tag in Swift. Table:
Tag / Name / A / B / status (same · changed · only A · only B), "differences only" toggle.

---

## Headless verification

Hooks live in `App/NativeTest.swift` (each is `@MainActor static func`; a new hook
that constructs `DicomEngine()` must be `@MainActor` or it won't build). Because
`open` doesn't capture stdout, each hook **writes its result to a file** named by an
env var. Run pattern (avoids App-Translocation / stale LaunchServices):

```sh
NEW=/tmp/DBtest.app
cp -R build/Build/Products/Debug/DicomFlow.app "$NEW" && xattr -cr "$NEW"
open -n --env DICOMFLOW_<HOOK>=<arg> --env <OUT_VAR>=/tmp/out.txt "$NEW"
# wait for /tmp/out.txt, then read it
```

| Hook env | Out var | What it exercises |
|---|---|---|
| `DICOMFLOW_MWL=1` (`MWL_HOST/PORT/AE`) | `MWL_OUT` | Modality Worklist C-FIND |
| `DICOMFLOW_DICOMWEB=1` (`DWB_URL/USER/PASS`) | `DWB_OUT` | QIDO/WADO/STOW |
| `DICOMFLOW_FHIR=1` (`FHIR_URL`) | `FHIR_OUT` | FHIR ImagingStudy search |
| `DICOMFLOW_HL7=1` | `HL7_OUT` | HL7 MLLP send + listener ACK (loopback) |
| `DICOMFLOW_PROTO=1` | `PROTO_OUT` | Protocol log capture during a C-ECHO |
| `DICOMFLOW_PCAP=<file>` | `PCAP_OUT` | pcap/pcapng parse + PDU dissection |
| `DICOMFLOW_VALIDATE=<file>` | `VALIDATE_OUT` | conformance validator |
| `DICOMFLOW_QR=1` (`QR_HOST/PORT/AE`) | `QR_OUT` | study C-FIND + series drill-down |
| `DICOMFLOW_DECODE=<file\|dir>` | `DECODE_OUT` | pixel decode + range (all codecs incl. J2K) |
| `DICOMFLOW_KEYCHAIN=1` | `KEYCHAIN_OUT` | Keychain set/get/update/delete roundtrip |
| `DICOMFLOW_TIMEOUT=1` (`TIMEOUT_S/HOST`) | `TIMEOUT_OUT` | network timeout is bounded, not ∞ |

(Plus the pre-existing render/engine hooks: `DICOMFLOW_NATIVE_*`, `_SR`, `_SCAN`, `_PERF`.)

**`scripts/verify.sh`** runs everything — xcodegen, the XCTest bundle (22 logic
tests: PcapParser incl. out-of-order reassembly + DIMSE command decode, HL7
framing/ACK, DicomWebClient multipart/JSON), the app build, and the hooks above
(peer-dependent ones auto-skip when Orthanc/fixtures are absent). `--fast` = unit
tests only.

---

## Deferred / not testable against the author's test PACS
- **MPPS** (N-CREATE / N-SET) — `DcmSCU` supports it, but Orthanc provides no MPPS
  SCP to test against.
- **Storage Commitment** (N-ACTION + async N-EVENT-REPORT) — `DcmSCU` has **no**
  N-ACTION (would need low-level DIMSE), plus the async report flow needs our own SCP +
  Orthanc `AllowStorageCommitment` + a registered AE.
- **Live packet capture** (libpcap/BPF) — needs root; **not** allowed in the App
  Sandbox. The .pcap import + self-traffic inspector are the sandbox-safe alternatives.

See `docs/BACKLOG.md` for the full backlog.
