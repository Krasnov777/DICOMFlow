# DicomFlow — MCP server

`dicomflow-mcp` exposes DicomFlow's native DICOM engine as **agent tools** over
the [Model Context Protocol](https://modelcontextprotocol.io) (stdio, JSON-RPC
2.0). An LLM agent (Claude Desktop, Claude Code, or any MCP client) can query a
PACS, inspect files, and **render slices to images it can actually look at**.

It's a standalone command-line binary that reuses the same DCMTK bridge as the
app (`Sources/DicomNative`) with none of the SwiftUI/Metal layers — so it is
**not sandboxed** and has free network + file access. It is distributed
separately from the App Store build.

## Build

```sh
./scripts/build-mcp.sh
```

This builds Release, stages the binary at `bin/dicomflow-mcp`, and prints the
client config. Requirements: the DCMTK xcframework + OpenJPEG must already be
built (they are, if the app builds), and **Homebrew `openssl@3`** must be present
(`brew install openssl@3`) — it's the only non-system runtime dependency (DCMTK
and OpenJPEG are statically linked). The DICOM data dictionary is built into the
binary; no external dict file is needed.

## Connect

**Claude Desktop** — edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "dicomflow": {
      "command": "/absolute/path/to/DicomFlow/bin/dicomflow-mcp"
    }
  }
}
```

Restart Claude Desktop; the tools appear under the 🔌 menu.

**Claude Code**:

```sh
claude mcp add dicomflow /absolute/path/to/DicomFlow/bin/dicomflow-mcp
```

`build-mcp.sh` prints the exact block with your absolute path filled in.

## Tools

**Read-only / network-read** — always available, nothing mutates data or the PACS:

| Tool | Arguments | Returns |
|---|---|---|
| `dicom_current_study` | — | the study currently open in the DicomFlow app (kind, patient, modality, series UID/description, file paths + age) — the app publishes a manifest on every viewer load; feed its `files` into the other tools |
| `dicom_read_tags` | `path` | every data element (tag, name, VR, value, keyword) + transfer syntax |
| `dicom_validate` | `path` | Part-10 conformance: `ok`, `errors`, `warnings`, `info` |
| `dicom_read_report` | `path` | a Structured Report (SR) rendered as text (e.g. Radiation Dose) |
| `dicom_series_info` | `directory` | files grouped into series (modality, description, count, files) |
| `dicom_render_slice` | `path` **or** `directory` (+ `seriesUID?`, `plane?`, `index?`/`position?`, `angle?`, `frame?`, `window?`, `level?`, `maxSize?`) | a **PNG image** of the slice + info text |
| `dicom_echo` | `host`, `port`, `calledAE`, `callingAE?` | C-ECHO result |
| `dicom_query` | `host`, `port`, `calledAE`, `level` (STUDY/SERIES/IMAGE), `filters?`, `callingAE?` | C-FIND matches |
| `dicom_web_query` | `baseURL`, `level` (studies/series/instances), `studyUID?`, `seriesUID?`, `filters?`, `username?`, `password?` | DICOMweb QIDO-RS matches |

`dicom_render_slice` defaults to the middle **axial** slice of the largest series
when given a `directory`. Set `plane` to `coronal`, `sagittal`, or `oblique` and
it stacks the whole series into a volume and reslices it (trilinear, with correct
physical aspect): `position` (0…1) picks the slice; `oblique` also takes `angle`
(degrees) to rotate a vertical plane in the axial plane. `window`/`level`
override the WC/WW; `maxSize` caps the longest side (default 512 px). Reslicing
decodes every file in the series, so it takes a few seconds for a large series.

**Write / retrieve — only present with `--allow-write`** (call `dicom_store`
without the flag and it refuses):

| Tool | Arguments | Effect |
|---|---|---|
| `dicom_store` | `host`, `port`, `calledAE`, `callingAE?`, `paths` **or** `directory` | C-STORE local files to a PACS |
| `dicom_retrieve` | `host`, `port`, `calledAE`, `level`, `keys`, `method` (GET/MOVE), `moveDest?`, `outputDir` | C-GET/C-MOVE into a local folder |
| `dicom_anonymize` | `paths` **or** `directory`, `outputDir`, `replacePatientName?`, `replacePatientID?`, `clearDates?`, `clearIdentifiers?`, `removePrivateTags?`, `regenerateUIDs?` | de-identify to a new folder (source untouched) |

To enable them, add `"args": ["--allow-write"]` to the `command` entry.

## Try it

Ask the agent, e.g.:

- *"Echo the PACS at 127.0.0.1:4242 (called AE ORTHANC), then find studies for
  PatientID 620548472."*
- *"Render the middle slice of `/path/to/ct-series` with a bone window (W 2000,
  L 400) and describe what you see."*
- *"Read the SR at `…/SR000001.dcm` and summarize the radiation dose."*
- *"What study is open in DicomFlow right now? Render its middle slice and
  tell me what you see."* (uses `dicom_current_study`)

## Guardrails & roadmap

- **Read-only by default.** The mutating/retrieving tools (`store`, `retrieve`,
  `anonymize`) are only listed and callable when the server is launched with
  `--allow-write` — without it they don't appear, and a direct call is refused.
- Logs go to **stderr**; stdout is a clean JSON-RPC stream.
- **Distribution:** for sharing beyond your own Mac, the binary should be
  Developer-ID-signed + notarized and the `openssl@3` dylibs statically linked or
  bundled with a fixed rpath (currently they resolve from Homebrew). Tracked as a
  follow-up.
- **Next:** oblique (coronal/sagittal) reslice in `render_slice`; per-tool audit
  logging; optional live "control the open app" channel.
