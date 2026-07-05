"""Series decode (M3) — turn a stack of DICOM files into a raw 3D volume.

The app passes a folder (or explicit file list). We:
  1. read every readable instance, keep those with pixel data,
  2. group by SeriesInstanceUID and pick the largest series,
  3. sort slices by ImagePositionPatient projected on the slice normal,
  4. stack into an int16 volume, resampling to uniform z-spacing if needed,
  5. write the contiguous buffer to a temp file (mmap on the Swift side),
  6. return only geometry + windowing metadata as JSON.

Bulk pixels never travel as JSON — just the temp-file path.
"""

import os
import tempfile
import uuid

import numpy as np
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from pydicom import dcmread

router = APIRouter()

_VOLUME_DIR = os.path.join(tempfile.gettempdir(), "dicombench_volumes")


class DecodeSeriesRequest(BaseModel):
    paths: list[str] | None = None
    directory: str | None = None


class VolumeMeta(BaseModel):
    volumePath: str
    dtype: str
    dims: list[int]            # [nx, ny, nz]  (columns, rows, slices)
    spacing: list[float]       # [sx, sy, sz]  mm
    origin: list[float]        # ImagePositionPatient of first slice
    orientation: list[float]   # 6 direction cosines (row, then col)
    slope: float
    intercept: float
    defaultWindowCenter: float
    defaultWindowWidth: float
    valueMin: int              # stored-value range (apply slope/intercept for HU)
    valueMax: int
    modality: str
    seriesCount: int
    warnings: list[str]


class ReleaseRequest(BaseModel):
    volumePath: str


def _gather_files(req: DecodeSeriesRequest) -> list[str]:
    files: list[str] = []
    if req.paths:
        files.extend(req.paths)
    if req.directory:
        for root, _dirs, names in os.walk(req.directory):
            for n in names:
                if n.lower() == "dicomdir":
                    continue
                files.append(os.path.join(root, n))
    return files


def _first_number(value, default: float) -> float:
    """DICOM WindowCenter/Width may be a single value or a MultiValue."""
    try:
        if isinstance(value, (list, tuple)) or hasattr(value, "__iter__"):
            return float(list(value)[0])
        return float(value)
    except Exception:
        return default


def _resample_z(vol: np.ndarray, zpos: np.ndarray):
    """Return (volume, z_spacing_mm, resampled?) on a uniform z grid."""
    diffs = np.diff(zpos)
    if len(diffs) == 0:
        return vol, 1.0, False
    step = float(np.median(diffs))
    if step <= 0:
        step = 1.0
    if np.abs(diffs - step).max() <= 0.01 * step:
        return vol, step, False  # already uniform

    z0, z1 = float(zpos[0]), float(zpos[-1])
    n_t = max(2, int(round((z1 - z0) / step)) + 1)
    targets = z0 + step * np.arange(n_t)
    src = vol.astype(np.float32)
    out = np.empty((n_t, vol.shape[1], vol.shape[2]), dtype=np.float32)
    for i, zt in enumerate(targets):
        j = int(np.searchsorted(zpos, zt))
        if j <= 0:
            out[i] = src[0]
        elif j >= len(zpos):
            out[i] = src[-1]
        else:
            z_lo, z_hi = float(zpos[j - 1]), float(zpos[j])
            t = 0.0 if z_hi == z_lo else (zt - z_lo) / (z_hi - z_lo)
            out[i] = src[j - 1] * (1.0 - t) + src[j] * t
    return out, step, True


@router.post("/viewer/decode-series", response_model=VolumeMeta)
def decode_series(req: DecodeSeriesRequest) -> VolumeMeta:
    warnings: list[str] = []
    files = _gather_files(req)
    if not files:
        raise HTTPException(status_code=400, detail="no files provided")

    # Read instances that have pixel data; bucket by series.
    series: dict[str, list] = {}
    for path in files:
        try:
            ds = dcmread(path, force=True)
        except Exception:
            continue
        if "PixelData" not in ds:
            continue
        uid = str(getattr(ds, "SeriesInstanceUID", "unknown"))
        series.setdefault(uid, []).append((path, ds))

    if not series:
        raise HTTPException(status_code=400, detail="no DICOM image instances found")

    if len(series) > 1:
        warnings.append(f"{len(series)} series found; showing the largest")
    chosen = max(series.values(), key=len)

    # Orientation is constant across the series; read it from any slice to
    # build the slice normal used for sorting.
    iop = [float(x) for x in getattr(chosen[0][1], "ImageOrientationPatient", [1, 0, 0, 0, 1, 0])]
    row_cos = np.array(iop[0:3])
    col_cos = np.array(iop[3:6])
    normal = np.cross(row_cos, col_cos)

    def proj(ds) -> float:
        ipp = [float(x) for x in getattr(ds, "ImagePositionPatient", [0, 0, 0])]
        return float(np.dot(np.array(ipp), normal))

    chosen.sort(key=lambda pe: proj(pe[1]))

    # Now chosen[0] is the lowest slice — read per-volume metadata from it.
    first = chosen[0][1]
    rows = int(first.Rows)
    cols = int(first.Columns)
    modality = str(getattr(first, "Modality", ""))

    # Stack stored pixel values.
    try:
        planes = []
        for _p, ds in chosen:
            arr = ds.pixel_array
            if arr.shape != (rows, cols):
                raise ValueError("inconsistent slice dimensions")
            planes.append(arr.astype(np.int16, copy=False))
        vol = np.stack(planes, axis=0)  # [z, y, x]
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"pixel decode failed: {e}")

    zpos = np.array([proj(ds) for _p, ds in chosen], dtype=np.float64)
    vol, sz, resampled = _resample_z(vol, zpos)
    if resampled:
        warnings.append("non-uniform slice spacing; resampled to uniform z")
    vol = vol.astype(np.int16, copy=False)
    nz = vol.shape[0]

    py, px = [float(x) for x in getattr(first, "PixelSpacing", [1.0, 1.0])]
    slope = float(getattr(first, "RescaleSlope", 1.0))
    intercept = float(getattr(first, "RescaleIntercept", 0.0))
    wc = _first_number(getattr(first, "WindowCenter", None), 40.0)
    ww = _first_number(getattr(first, "WindowWidth", None), 400.0)
    origin = [float(x) for x in getattr(first, "ImagePositionPatient", [0, 0, 0])]

    # Write the contiguous little-endian int16 buffer for mmap on the app side.
    os.makedirs(_VOLUME_DIR, exist_ok=True)
    vol_path = os.path.join(_VOLUME_DIR, f"vol_{uuid.uuid4().hex}.raw")
    np.ascontiguousarray(vol, dtype="<i2").tofile(vol_path)

    return VolumeMeta(
        volumePath=vol_path,
        dtype="int16",
        dims=[cols, rows, nz],
        spacing=[px, py, sz],
        origin=origin,
        orientation=iop,
        slope=slope,
        intercept=intercept,
        defaultWindowCenter=wc,
        defaultWindowWidth=ww,
        valueMin=int(vol.min()),
        valueMax=int(vol.max()),
        modality=modality,
        seriesCount=len(series),
        warnings=warnings,
    )


@router.post("/viewer/release")
def release_volume(req: ReleaseRequest):
    # Only allow deleting files we created, under our temp dir.
    p = os.path.abspath(req.volumePath)
    if os.path.commonpath([p, _VOLUME_DIR]) == _VOLUME_DIR and os.path.exists(p):
        os.remove(p)
        return {"status": "released"}
    raise HTTPException(status_code=400, detail="invalid volume path")
