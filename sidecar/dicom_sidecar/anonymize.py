"""Anonymizer (M6) — pragmatic PS3.15-style de-identification.

Non-medical tool, so this is a sensible default profile rather than a certified
one: replace patient identity, optionally clear dates, drop private tags, and
**consistently** remap instance UIDs across a whole series so the set stays
internally valid.
"""

import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pydicom import dcmread
from pydicom.multival import MultiValue
from pydicom.uid import generate_uid

router = APIRouter()

# UIDs that identify *types*, not instances — never remap these.
PRESERVE_UID_KEYWORDS = {
    "SOPClassUID", "MediaStorageSOPClassUID",
    "TransferSyntaxUID", "ImplementationClassUID",
}

# Identity elements removed when clearIdentifiers is on.
IDENTITY_KEYWORDS = [
    "InstitutionName", "InstitutionAddress", "ReferringPhysicianName",
    "PerformingPhysicianName", "OperatorsName", "PatientAddress",
    "PatientTelephoneNumbers", "OtherPatientIDs", "OtherPatientNames",
    "PatientBirthName", "StationName",
]

DATE_TIME_KEYWORDS = [
    "StudyDate", "SeriesDate", "AcquisitionDate", "ContentDate", "PatientBirthDate",
    "StudyTime", "SeriesTime", "AcquisitionTime", "ContentTime",
]


class AnonProfile(BaseModel):
    replacePatientName: str | None = "ANON"
    replacePatientID: str | None = "ANON-ID"
    clearDates: bool = True
    clearIdentifiers: bool = True
    removePrivateTags: bool = True
    regenerateUIDs: bool = True


class AnonRequest(BaseModel):
    directory: str | None = None
    paths: list[str] | None = None
    outputDir: str
    profile: AnonProfile = AnonProfile()


class AnonResponse(BaseModel):
    success: bool
    processed: int
    outputDir: str
    uidsRemapped: int
    warnings: list[str]


def _map_uid(uid: str, uid_map: dict[str, str]) -> str:
    if uid not in uid_map:
        uid_map[uid] = generate_uid()
    return uid_map[uid]


def _remap_uids(dataset, uid_map: dict[str, str]) -> None:
    for elem in dataset:
        if elem.VR == "SQ":
            for item in elem.value:
                _remap_uids(item, uid_map)
        elif elem.VR == "UI" and elem.keyword not in PRESERVE_UID_KEYWORDS:
            val = elem.value
            if isinstance(val, (list, MultiValue)):
                elem.value = [_map_uid(str(v), uid_map) for v in val]
            elif val:
                elem.value = _map_uid(str(val), uid_map)


def _gather(req: AnonRequest) -> list[str]:
    files: list[str] = []
    if req.paths:
        files.extend(req.paths)
    if req.directory:
        for root, _d, names in os.walk(req.directory):
            for n in names:
                if n.lower() != "dicomdir":
                    files.append(os.path.join(root, n))
    return files


@router.post("/anonymize", response_model=AnonResponse)
def anonymize(req: AnonRequest) -> AnonResponse:
    files = _gather(req)
    if not files:
        raise HTTPException(status_code=400, detail="no files provided")
    os.makedirs(req.outputDir, exist_ok=True)

    p = req.profile
    uid_map: dict[str, str] = {}   # shared across the series for consistency
    warnings: list[str] = []
    processed = 0

    for path in files:
        try:
            ds = dcmread(path, force=True)
        except Exception:
            continue

        if p.regenerateUIDs:
            _remap_uids(ds, uid_map)
            if hasattr(ds, "file_meta") and "MediaStorageSOPInstanceUID" in ds.file_meta:
                ds.file_meta.MediaStorageSOPInstanceUID = _map_uid(
                    str(ds.file_meta.MediaStorageSOPInstanceUID), uid_map)

        if p.replacePatientName is not None:
            ds.PatientName = p.replacePatientName
        if p.replacePatientID is not None:
            ds.PatientID = p.replacePatientID
        if p.clearDates:
            for kw in DATE_TIME_KEYWORDS:
                if kw in ds:
                    setattr(ds, kw, "")
        if p.clearIdentifiers:
            for kw in IDENTITY_KEYWORDS:
                if kw in ds:
                    delattr(ds, kw)
        if p.removePrivateTags:
            ds.remove_private_tags()

        out = os.path.join(req.outputDir, f"anon_{processed:05d}.dcm")
        try:
            ds.save_as(out, enforce_file_format=True)
            processed += 1
        except Exception as e:
            warnings.append(f"{os.path.basename(path)}: {e}")

    if processed == 0:
        raise HTTPException(status_code=400, detail="no DICOM files could be anonymized")

    return AnonResponse(success=True, processed=processed, outputDir=req.outputDir,
                        uidsRemapped=len(uid_map), warnings=warnings)
