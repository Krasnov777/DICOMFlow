"""Tag reading (M2) — and later editing/anonymizing.

Both processes run on the same machine, so the app hands us a file *path*
(chosen via the native open panel) instead of uploading bytes. This ports the
old Flask ``/check-dicom-tags`` (``ds.iterall()``) and adds the VR and a
human-readable element name.
"""

import os

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pydicom import dcmread

router = APIRouter()

# Editing these would corrupt the pixel buffer — block them.
PIXEL_GEOMETRY_TAGS = {
    "Rows", "Columns", "BitsAllocated", "BitsStored", "HighBit",
    "PixelRepresentation", "SamplesPerPixel", "PhotometricInterpretation",
    "PixelData", "NumberOfFrames",
}


class ReadTagsRequest(BaseModel):
    path: str


class TagItem(BaseModel):
    tag: str       # "(0010,0010)"
    keyword: str   # "PatientName" ("" for private/unknown)
    name: str      # "Patient's Name"
    vr: str        # "PN"
    value: str


class ReadTagsResponse(BaseModel):
    path: str
    transferSyntax: str | None
    count: int
    tags: list[TagItem]


def _format_value(elem) -> str:
    """Render an element value as a compact, table-friendly string."""
    vr = elem.VR
    val = elem.value
    if vr == "SQ":
        try:
            n = len(val)
        except Exception:
            n = 0
        return f"<Sequence: {n} item(s)>"
    if isinstance(val, (bytes, bytearray, memoryview)):
        return f"<Binary: {len(val)} bytes>"
    try:
        s = str(val)
    except Exception:
        return "<unprintable>"
    return s if len(s) <= 1024 else s[:1024] + "…"


@router.post("/tags/read", response_model=ReadTagsResponse)
def read_tags(req: ReadTagsRequest) -> ReadTagsResponse:
    try:
        ds = dcmread(req.path, force=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"failed to read DICOM: {e}")

    tags: list[TagItem] = []
    for elem in ds.iterall():
        t = elem.tag
        tags.append(
            TagItem(
                tag=f"({t.group:04X},{t.element:04X})",
                keyword=elem.keyword or "",
                name=elem.name or "Unknown",
                vr=str(elem.VR or ""),
                value=_format_value(elem),
            )
        )

    transfer_syntax = None
    try:
        transfer_syntax = str(ds.file_meta.TransferSyntaxUID.name)
    except Exception:
        pass

    return ReadTagsResponse(
        path=req.path,
        transferSyntax=transfer_syntax,
        count=len(tags),
        tags=tags,
    )


class EditOp(BaseModel):
    keyword: str
    value: str | None = None   # None deletes the element


class EditTagsRequest(BaseModel):
    path: str
    edits: list[EditOp]
    outputPath: str | None = None


class EditTagsResponse(BaseModel):
    success: bool
    outputPath: str
    applied: list[dict]
    skipped: list[dict]


@router.post("/tags/edit", response_model=EditTagsResponse)
def edit_tags(req: EditTagsRequest) -> EditTagsResponse:
    try:
        ds = dcmread(req.path, force=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"failed to read DICOM: {e}")

    applied, skipped = [], []
    for op in req.edits:
        if op.keyword in PIXEL_GEOMETRY_TAGS:
            skipped.append({"keyword": op.keyword, "reason": "pixel-geometry tag (blocked)"})
            continue
        try:
            if op.value is None:
                if op.keyword in ds:
                    delattr(ds, op.keyword)
                    applied.append({"keyword": op.keyword, "value": "<deleted>"})
            else:
                setattr(ds, op.keyword, op.value)   # pydicom coerces by VR
                applied.append({"keyword": op.keyword, "value": op.value})
        except Exception as e:
            skipped.append({"keyword": op.keyword, "reason": str(e)})

    # Never overwrite the source: write a sibling "*_edited.dcm" by default.
    out = req.outputPath
    if not out:
        base, ext = os.path.splitext(req.path)
        out = f"{base}_edited{ext or '.dcm'}"
    try:
        ds.save_as(out, enforce_file_format=True)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"failed to save: {e}")

    return EditTagsResponse(success=True, outputPath=out, applied=applied, skipped=skipped)
