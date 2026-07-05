# DicomFlow — Feature Backlog

Ideas for the **Tester / Toolbench** mode (and a few cross-cutting), captured
2026-07-01. Ordered roughly by value; not committed to yet.

## Done
- **DICOMweb** ✅ (`DicomWebClient` + `DicomWebView`) — QIDO-RS query, WADO-RS
  retrieve → viewer, STOW-RS store. Pure `URLSession`, no DCMTK. Verified against
  Orthanc's `/dicom-web` (auth `admin` + keychain pw). Next: series/instance-level
  QIDO, WADO metadata/rendered/frames, UPS-RS.
- **DIMSE protocol inspector** ✅ (`DCMTKLog` appender + `ProtocolLog` +
  `ProtocolInspectorView`) — decoded self-traffic timeline (A-ASSOCIATE-RQ/AC +
  presentation contexts/transfer syntaxes, DIMSE messages), captured from DCMTK's
  dcmnet log. Follow-ons still open: **.pcap import/export** (third-party traffic),
  per-association grouping, richer DIMSE parsing.

## Networking / protocol
- **HL7 v2 MLLP** ✅ (`HL7.swift` + `HL7View`) — send (ADT/ORM/ORU + ACK) + MLLP
  listener (auto-ACK). Verified loopback.
- **FHIR** ✅ (`FHIRClient` + `FHIRView`) — ImagingStudy search (R4). Verified vs
  public HAPI (100 studies). Next: retrieve via endpoint → viewer, more resources.
- **Validator** ✅ (`DCMTKBridge.validateFile` + `ValidatorView`) — Part-10 meta,
  required UIDs+format, SOP class, module type-1/2 (Patient/Study/Series/Equipment/
  Image), per-element VR. Verified. Next: full IOD via dcmiod.
- **Compare** ✅ (`DiffView`) — two-dataset tag diff. Verified.
- **.pcap / .pcapng import** ✅ (`PcapParser` + Protocol Inspector "Import" button) —
  parse capture → TCP reassembly → DICOM PDU dissection (associate/PDATA/release/
  abort) into the timeline. Verified (classic + pcapng). Export N/A (no raw bytes
  from our text log). Next: DIMSE command-dataset decode, per-association grouping.
- **MWL C-FIND** ✅ (`DCMTKNet.worklistQueryHost` + `WorklistView`) — Modality
  Worklist query (Scheduled Procedure Step Sequence). **Verified end-to-end**
  against Orthanc (worklist plugin enabled + 3 sample `.wl`): 3 items decoded.
- **DIMSE protocol inspector ("Wireshark for DICOM")** — render the app's own
  association traffic as an expandable timeline: A-ASSOCIATE-RQ/AC (presentation
  contexts + accepted transfer syntaxes), each DIMSE message (command + dataset
  PDVs), A-RELEASE / A-ABORT. Higher value than a raw sniffer because it's already
  decoded. Sandbox-safe (self-traffic). Follow-ons: **.pcap/.pcapng import** to
  dissect third-party traffic, and **.pcap export** for real Wireshark.
  NOTE: true live packet capture (libpcap/BPF) needs root and is **not** allowed in
  the App Store sandbox — do not attempt for the Store build.
- **Modality Worklist (MWL) C-FIND** — query a worklist SCP. Cheap, high demand.
- **MPPS** (N-CREATE / N-SET) and **Storage Commitment** (N-ACTION / N-EVENT-REPORT).
- **HL7 v2.x over MLLP** ✅ (`HL7.swift` + `HL7View`) — send (ADT/ORM/ORU templates,
  ACK parse) + MLLP listener (auto-ACK). Verified loopback. Next: message field
  inspector/tree, FHIR.
- **FHIR** — ImagingStudy / Endpoint / ImagingSelection (REST).
- **DICOM-TLS** — secure associations (DCMTK `dcmtls`).
- **Negotiation probe** ✅ (2026-07-03, `NegotiationView` + `DCMTKNet.
  probeContextsHost`) — proposes 15 SOP classes × 8 transfer syntaxes as one
  context per pair, reports accepted pairs via `findPresentationContextID`.
  Verified live vs Orthanc (114/120: storage takes all 8 TS; Verification only the
  2 uncompressed). Honors global TLS/timeouts; CSV/TSV export.

## Conformance / validation
- **DICOM file validator** ✅ (`DCMTKBridge.validateFile` + `ValidatorView`) —
  Part-10 meta, required UIDs + format, SOP class, image-attribute completeness,
  per-element VR checks. Verified (clean / non-DICOM / broken). Next: full IOD
  validation via `dcmiod` (type-1/2 per SOP class).
- **Two-dataset diff** — tag-level diff of DICOM objects.

## Deferred (not testable against the author's test PACS)
- **MPPS** (N-CREATE/N-SET) — DcmSCU supports it, but Orthanc has no MPPS SCP to
  test against; needs a modality-facing MPPS manager.
- **Storage Commitment** (N-ACTION + async N-EVENT-REPORT) — DcmSCU has **no**
  N-ACTION (would need low-level DIMSE), and the async report flow needs our SCP +
  Orthanc `AllowStorageCommitment` + a registered AE.

## Data / test fixtures
- ~~Synthetic DICOM generator~~ ✅ (2026-07-05, `GeneratorView` + `DCMTKBridge.
  generateDatasetToDir`) — build a stackable phantom series on demand (CT 16-bit
  HU / MR 16-bit / SC 8-bit; sphere/gradient/rings/checkerboard/noise/solid;
  size + slice count) → Open in Viewer / Send to C-STORE / Save a Copy. Output
  decodes + validates conformant (`GeneratorTests`).
- ~~DICOMDIR reader~~ ✅ (2026-07-05, `DicomDirView` + `DCMTKBridge.readDicomDir`) —
  open a folder with a DICOMDIR, browse its Patient→Study→Series tree, open any
  series in the Viewer (ReferencedFileID paths resolved; media SOP-class checked).
  Verified vs pydicom's dicomdirtests (`DicomDirTests`).
- ~~hex/raw dataset viewer~~ ✅ (2026-07-05, `DumpView` + `DCMTKBridge.dumpFile`) —
  dcmdump-style nested element tree (tag·VR·length·value, sequences indented) with
  a line filter + copy/export; long values shortened.
- ~~PS3.15 de-id profile presets~~ ✅ (2026-07-05) — Anonymizer applies the PS3.15
  Basic Application Level Confidentiality Profile (curated Table E.1-1) with the
  standard retain/clean options (dates, device identity, patient characteristics,
  clean descriptors) + PatientIdentityRemoved/DeidentificationMethod stamp.
- ~~pixel/burned-in-text anonymization~~ ✅ (2026-07-05, `RedactView` +
  `DCMTKBridge.renderDisplay8`/`redactFile`) — Vision OCR detects burned-in text,
  review/toggle the regions, then black them out of the pixel data (all frames,
  mono/color) + set BurnedInAnnotation=NO. Verified (`GeneratorTests`).

## Automation
- **Scripted test scenarios** — chain echo→store→query→verify with pass/fail.
- **Throughput/latency benchmark** — store N objects, measure.
- ~~Unit tests + one-command verify~~ ✅ (`Tests/` 22 XCTests + `scripts/verify.sh`).

## Done — hardening pass (2026-07-02)
- **DIMSE timeouts** ✅ (connect/ACSE/DIMSE on every SCU, Settings knob) +
  **cancel** ✅ (web ops abort; DIMSE unblocks via generation guard).
- **Keychain credentials** ✅ (DICOMweb per-server, saved on success only).
- **Q/R series drill-down** ✅ (per-level return keys; series table + series
  retrieve; first live C-FIND vs Orthanc — AE registered).
- **pcap DIMSE command decode** ✅ (command name/MsgID/status/SOP class).
- **JPEG 2000** ✅ (vendored fmjpeg2koj + static OpenJPEG; pixel-exact vs pydicom).

## Improvement backlog (2026-07-02 analysis, rough value order)
- ~~8-bit pixel decode~~ ✅ (grayscale widen + color→luma; J2K corpus 13/14).
- ~~DICOMweb series drill-down~~ ✅ (series QIDO + series WADO → viewer). Still
  open: instance-level QIDO, WADO-RS `/metadata` + `/rendered`, frames.
- ~~HL7 field inspector~~ ✅ (HL7.parse + HL7FieldTree, Fields|Raw toggle).
- ~~Protocol Inspector grouping~~ ✅ (association sections + direction arrows).
- ~~All-modes consistency pass~~ ✅ (2026-07-02): Return-to-run on all query
  forms; TableExport (copy TSV / export CSV) on every result table + Validator
  report + HL7 received; Cancel on Worklist/Store/FHIR; FHIR Basic-auth +
  Keychain. Perf: cine timer only ticks while playing (was permanent 12.5 Hz);
  Protocol Inspector grouping O(n²)→O(n).
- ~~DICOMweb instance drill-down~~ ✅ (2026-07-02): instance QIDO + /metadata +
  /rendered (Instances… sheet: table + rendered preview + full metadata).
  Gotcha: Orthanc 400s on multi-value Accept — /rendered wants one type.
- ~~SCP open-selected-series~~ ✅ · ~~accessibility labels~~ ✅ (hint() =
  tooltip + VoiceOver label on all 22 icon-only controls + viewer tool segments).
- ~~DICOM TLS (outgoing SCU)~~ ✅ (2026-07-02): DCMTK rebuilt with OpenSSL;
  BCP 195 TLS on all five SCU paths; TLS checkbox in the target form + verify/CA
  in Settings; scripts/tls-proxy.py for testing without touching the shared
  Orthanc. Verified incl. certificate verification.
- ~~TLS for the built-in Test SCP~~ ✅ (2026-07-03): server-side self-signed cert
  (OpenSSL) on a NET_ACCEPTOR layer, attached when global TLS is on. Also fixed a
  latent socket-leak that stopped the SCP restarting on the same port. Verified by
  `SCPTests` (loopback receive · 3× restart · TLS) + a live Orthanc round trip
  (C-STORE→C-FIND→C-GET→C-MOVE-to-self).
- ~~Called-AE enforcement~~ ✅ (2026-07-03): "Enforce Called AE" toggle on the Test
  SCP (default on) → `setRespondWithCalledAETitle(OFFalse)`, refusing associations
  addressed to a different Called AE. Verified by `SCPTests.testSCPEnforcesCalledAE`
  (wrong AE refused, correct accepted).
- ~~Full IOD validation via `dcmiod`~~ ✅ (2026-07-04): the Validator now checks
  every unconditional type-1/2 attribute of the common composite-IOD modules
  (Patient, Patient Study, General Study/Series/Equipment, SOP Common) + General
  Image via DCMTK's own `IODRules` engine, instead of a hand-rolled subset. FoR
  skipped (IOD-conditional). Verified by `ValidatorTests`.
- ~~Viewer ROI stats + angle measurement~~ ✅ (2026-07-02): ROI rect →
  mean/σ/min/max HU + area (exact voxel iteration, phantom-verified); 3-click
  angle in mm space. Ellipse ROI still open if ever needed.
- ~~Viewer batch 1 — interaction~~ ✅ (2026-07-02): 2D plane picker (A/C/S,
  full-screen coronal/sagittal; plane-generic probe/measure/ROI/export/cine),
  keyboard shortcuts (arrows/space/1-6/I/R/O/A/C/S), right-drag = W/L in 2D +
  MPR, corner info overlays (W/L · zoom · plane · slice · mm).
- ~~Viewer batch 2 — data~~ ✅ (2026-07-02): multi-frame DICOM decodes as a full
  stack (US clips, enhanced CT/MR; was frame-0-only); movie export — 2D slice
  sweep + 3D MIP turntable (H.264 .mov, AVFoundation-validated).
- ~~Viewer batch 3 — measurements~~ ✅ (2026-07-02): persistent annotations
  (commit on completion, per plane+slice, survive rotate/flip) with a list
  popover (jump/delete/clear); ROI HU histogram (48 bins). Still open: ellipse
  ROI, per-frame functional-group positions for enhanced multi-frame.
- **Accessibility labels** (currently zero) · **localization** (hardcoded English).
