"""DICOMBench sidecar — local DICOM service for the native macOS app.

Exposes a loopback-only HTTP API (FastAPI) bound to an ephemeral port, guarded
by a bearer token printed on stdout during startup. The Swift app launches this
process, reads the handshake line, and drives all DICOM I/O through it.
"""

__version__ = "0.1.0"
