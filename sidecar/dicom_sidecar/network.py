"""DICOM networking (SCU side): C-ECHO, C-STORE, C-FIND, C-MOVE, C-GET.

Ports the old Flask ``/check-connection`` and ``/send-dicom-files`` and adds
Query/Retrieve. Retrieved/received instances land in the built-in SCP's
received dir so the viewer can open them.
"""

import os

from fastapi import APIRouter
from pydantic import BaseModel
from pydicom import dcmread
from pydicom.dataset import Dataset
from pydicom.uid import ExplicitVRLittleEndian
from pynetdicom import (
    AE, evt, build_role,
    VerificationPresentationContexts, StoragePresentationContexts,
)
from pynetdicom.sop_class import (
    StudyRootQueryRetrieveInformationModelFind,
    StudyRootQueryRetrieveInformationModelMove,
    StudyRootQueryRetrieveInformationModelGet,
)

from .scp import SCP, RECEIVED_DIR

router = APIRouter()

DEFAULT_CALLING_AE = "DICOMBENCH"

# Return keys requested for universal matching, per query level.
RETURN_KEYS = {
    "STUDY": ["PatientName", "PatientID", "StudyDate", "StudyTime",
              "StudyDescription", "AccessionNumber", "StudyInstanceUID",
              "ModalitiesInStudy", "NumberOfStudyRelatedSeries"],
    "SERIES": ["Modality", "SeriesNumber", "SeriesDescription",
               "SeriesInstanceUID", "NumberOfSeriesRelatedInstances"],
    "IMAGE": ["InstanceNumber", "SOPInstanceUID"],
    "PATIENT": ["PatientName", "PatientID", "PatientBirthDate", "PatientSex"],
}


class EchoRequest(BaseModel):
    host: str
    port: int
    aeTitle: str
    callingAE: str = DEFAULT_CALLING_AE


class StoreRequest(BaseModel):
    host: str
    port: int
    aeTitle: str
    paths: list[str]
    callingAE: str = DEFAULT_CALLING_AE


class QueryRequest(BaseModel):
    host: str
    port: int
    aeTitle: str
    level: str = "STUDY"
    filters: dict[str, str] = {}
    callingAE: str = DEFAULT_CALLING_AE


class RetrieveRequest(BaseModel):
    host: str
    port: int
    aeTitle: str
    level: str = "STUDY"
    keys: dict[str, str] = {}
    method: str = "get"            # "get" or "move"
    moveDestination: str | None = None
    callingAE: str = DEFAULT_CALLING_AE


def _ds_to_dict(ds: Dataset) -> dict:
    out: dict[str, str] = {}
    for elem in ds:
        if elem.VR == "SQ" or isinstance(elem.value, (bytes, bytearray, memoryview)):
            continue
        kw = elem.keyword or f"{elem.tag.group:04X}{elem.tag.element:04X}"
        out[kw] = str(elem.value)
    return out


@router.post("/net/echo")
def net_echo(req: EchoRequest):
    ae = AE(ae_title=req.callingAE)
    ae.requested_contexts = VerificationPresentationContexts
    try:
        assoc = ae.associate(req.host, req.port, ae_title=req.aeTitle)
    except Exception as e:
        return {"success": False, "message": str(e)}
    if not assoc.is_established:
        return {"success": False, "message": "Association rejected/failed"}
    status = assoc.send_c_echo()
    sop = [cx.abstract_syntax.name for cx in assoc.accepted_contexts]
    assoc.release()
    return {
        "success": True,
        "echoStatus": int(getattr(status, "Status", -1)) if status else -1,
        "supportedSOPClasses": sop,
    }


@router.post("/net/store")
def net_store(req: StoreRequest):
    ae = AE(ae_title=req.callingAE)
    ae.requested_contexts = StoragePresentationContexts
    try:
        assoc = ae.associate(req.host, req.port, ae_title=req.aeTitle)
    except Exception as e:
        return {"success": False, "message": str(e)}
    if not assoc.is_established:
        return {"success": False, "message": "Association rejected/failed"}

    results, sent = [], 0
    for p in req.paths:
        if os.path.basename(p).lower() == "dicomdir":
            continue
        try:
            ds = dcmread(p)
            if ds.file_meta.TransferSyntaxUID != ExplicitVRLittleEndian:
                ds.decompress()
                ds.file_meta.TransferSyntaxUID = ExplicitVRLittleEndian
            status = assoc.send_c_store(ds)
            ok = bool(status) and status.Status == 0
            results.append({"file": os.path.basename(p),
                            "status": int(getattr(status, "Status", -1)) if status else -1,
                            "ok": ok})
            if ok:
                sent += 1
        except Exception as e:
            results.append({"file": os.path.basename(p), "ok": False, "error": str(e)})
    assoc.release()
    return {"success": True, "sent": sent, "total": len(results), "results": results}


@router.post("/net/query")
def net_query(req: QueryRequest):
    ae = AE(ae_title=req.callingAE)
    ae.add_requested_context(StudyRootQueryRetrieveInformationModelFind)
    try:
        assoc = ae.associate(req.host, req.port, ae_title=req.aeTitle)
    except Exception as e:
        return {"success": False, "message": str(e)}
    if not assoc.is_established:
        return {"success": False, "message": "Association rejected/failed"}

    ds = Dataset()
    ds.QueryRetrieveLevel = req.level
    for k in RETURN_KEYS.get(req.level, []):
        setattr(ds, k, "")
    for k, v in req.filters.items():
        setattr(ds, k, v)

    results = []
    for status, identifier in assoc.send_c_find(
            ds, StudyRootQueryRetrieveInformationModelFind):
        if status and status.Status in (0xFF00, 0xFF01) and identifier:
            results.append(_ds_to_dict(identifier))
    assoc.release()
    return {"success": True, "count": len(results), "results": results}


@router.post("/net/retrieve")
def net_retrieve(req: RetrieveRequest):
    if req.method == "move":
        return _retrieve_move(req)
    return _retrieve_get(req)


def _build_identifier(req: RetrieveRequest) -> Dataset:
    ds = Dataset()
    ds.QueryRetrieveLevel = req.level
    for k, v in req.keys.items():
        setattr(ds, k, v)
    return ds


def _retrieve_get(req: RetrieveRequest):
    ae = AE(ae_title=req.callingAE)
    ae.add_requested_context(StudyRootQueryRetrieveInformationModelGet)
    roles = []
    for cx in StoragePresentationContexts:
        ae.add_requested_context(cx.abstract_syntax)
        roles.append(build_role(cx.abstract_syntax, scp_role=True))

    os.makedirs(RECEIVED_DIR, exist_ok=True)
    saved: list[str] = []

    def handle_store(event):
        ds = event.dataset
        ds.file_meta = event.file_meta
        path = os.path.join(RECEIVED_DIR, f"{getattr(ds, 'SOPInstanceUID', 'x')}.dcm")
        ds.save_as(path, enforce_file_format=True)
        saved.append(path)
        return 0x0000

    try:
        assoc = ae.associate(req.host, req.port, ae_title=req.aeTitle,
                             ext_neg=roles,
                             evt_handlers=[(evt.EVT_C_STORE, handle_store)])
    except Exception as e:
        return {"success": False, "message": str(e)}
    if not assoc.is_established:
        return {"success": False, "message": "Association rejected/failed"}

    summary = {"completed": 0, "failed": 0, "warning": 0}
    for status, _ in assoc.send_c_get(_build_identifier(req),
                                      StudyRootQueryRetrieveInformationModelGet):
        if status:
            summary["completed"] = int(getattr(status, "NumberOfCompletedSuboperations", summary["completed"]) or summary["completed"])
            summary["failed"] = int(getattr(status, "NumberOfFailedSuboperations", summary["failed"]) or summary["failed"])
    assoc.release()
    return {"success": True, "method": "get", "received": len(saved),
            "receivedDir": RECEIVED_DIR, "summary": summary}


def _retrieve_move(req: RetrieveRequest):
    dest = req.moveDestination or SCP.ae_title
    if not SCP.running:
        return {"success": False,
                "message": "Start the built-in SCP first (C-MOVE destination)."}
    ae = AE(ae_title=req.callingAE)
    ae.add_requested_context(StudyRootQueryRetrieveInformationModelMove)
    try:
        assoc = ae.associate(req.host, req.port, ae_title=req.aeTitle)
    except Exception as e:
        return {"success": False, "message": str(e)}
    if not assoc.is_established:
        return {"success": False, "message": "Association rejected/failed"}

    before = len(SCP.received)
    summary = {"completed": 0, "failed": 0}
    for status, _ in assoc.send_c_move(_build_identifier(req), dest,
                                       StudyRootQueryRetrieveInformationModelMove):
        if status:
            summary["completed"] = int(getattr(status, "NumberOfCompletedSuboperations", 0) or 0)
            summary["failed"] = int(getattr(status, "NumberOfFailedSuboperations", 0) or 0)
    assoc.release()
    return {"success": True, "method": "move", "destination": dest,
            "received": len(SCP.received) - before,
            "receivedDir": RECEIVED_DIR, "summary": summary}
