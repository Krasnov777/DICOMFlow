"""Built-in Storage SCP (mini-PACS) for receiving DICOM locally.

Ports the old ``mock_dicom_server.py`` to a controllable, queryable service:
start/stop on demand, accept C-ECHO + all storage SOP classes, save incoming
instances to a received dir, and expose the list of what arrived.
"""

import os
import tempfile
import threading

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pynetdicom import AE, evt, AllStoragePresentationContexts
from pynetdicom.sop_class import Verification

router = APIRouter()

RECEIVED_DIR = os.path.join(tempfile.gettempdir(), "dicombench_received")


class _SCP:
    """Singleton wrapper around a non-blocking pynetdicom storage server."""

    def __init__(self) -> None:
        self.server = None
        self.ae_title = "DICOMBENCH"
        self.port = 11112
        self.received: list[dict] = []
        self._lock = threading.Lock()

    @property
    def running(self) -> bool:
        return self.server is not None

    def _on_echo(self, event):
        return 0x0000

    def _on_store(self, event):
        ds = event.dataset
        ds.file_meta = event.file_meta
        os.makedirs(RECEIVED_DIR, exist_ok=True)
        sop = str(getattr(ds, "SOPInstanceUID", "unknown"))
        path = os.path.join(RECEIVED_DIR, f"{sop}.dcm")
        ds.save_as(path, enforce_file_format=True)
        with self._lock:
            self.received.append({
                "path": path,
                "patient": str(getattr(ds, "PatientName", "")),
                "studyUID": str(getattr(ds, "StudyInstanceUID", "")),
                "seriesUID": str(getattr(ds, "SeriesInstanceUID", "")),
                "sopUID": sop,
                "modality": str(getattr(ds, "Modality", "")),
            })
        return 0x0000

    def start(self, ae_title: str, port: int) -> None:
        if self.running:
            raise HTTPException(status_code=400, detail="SCP already running")
        ae = AE(ae_title=ae_title)
        ae.supported_contexts = AllStoragePresentationContexts
        ae.add_supported_context(Verification)
        handlers = [(evt.EVT_C_STORE, self._on_store), (evt.EVT_C_ECHO, self._on_echo)]
        try:
            self.server = ae.start_server(("0.0.0.0", port), block=False,
                                          evt_handlers=handlers)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"could not start SCP: {e}")
        self.ae_title = ae_title
        self.port = port

    def stop(self) -> None:
        if self.server is not None:
            self.server.shutdown()
            self.server = None


SCP = _SCP()


class StartSCPRequest(BaseModel):
    aeTitle: str = "DICOMBENCH"
    port: int = 11112


@router.post("/scp/start")
def scp_start(req: StartSCPRequest):
    SCP.start(req.aeTitle, req.port)
    return scp_status()


@router.post("/scp/stop")
def scp_stop():
    SCP.stop()
    return scp_status()


@router.get("/scp/status")
def scp_status():
    return {
        "running": SCP.running,
        "aeTitle": SCP.ae_title,
        "port": SCP.port,
        "receivedCount": len(SCP.received),
        "receivedDir": RECEIVED_DIR,
    }


@router.get("/scp/received")
def scp_received():
    with SCP._lock:
        return {"receivedDir": RECEIVED_DIR, "items": list(SCP.received)}


@router.post("/scp/clear")
def scp_clear():
    with SCP._lock:
        SCP.received.clear()
    return {"status": "cleared"}
