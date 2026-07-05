"""Generate a synthetic multi-slice CT series for viewer development.

Produces a stack of CT Image Storage instances with *known* geometry so the
rendering pipeline can be verified exactly:

  - 128 x 128 in-plane, ``nz`` slices (default 96)
  - PixelSpacing 1.5 x 1.5 mm, SliceThickness/spacing 2.0 mm  (anisotropic on z)
  - Axial, ImageOrientationPatient = [1,0,0, 0,1,0], z increasing
  - Signed 16-bit stored values + RescaleIntercept -1024  → HU
  - Content: air background (~-1000 HU), a soft-tissue sphere (~40 HU) and a
    denser bone cube (~700 HU) offset from center, so MPR planes and 3D
    rendering show recognisable, asymmetric structure.

Usage:  python -m tools.make_fixture /path/to/output_dir [nz]
"""

import os
import sys

import numpy as np
from pydicom.dataset import Dataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, CTImageStorage, generate_uid


def main() -> None:
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/dicombench_fixture"
    nz = int(sys.argv[2]) if len(sys.argv) > 2 else 96
    nx = ny = 128
    px, py, pz = 1.5, 1.5, 2.0
    os.makedirs(out, exist_ok=True)

    study_uid = generate_uid()
    series_uid = generate_uid()

    # Build the whole volume in HU first.
    zz, yy, xx = np.mgrid[0:nz, 0:ny, 0:nx].astype(np.float32)
    cx, cy, cz = nx / 2, ny / 2, nz / 2
    vol = np.full((nz, ny, nx), -1000.0, dtype=np.float32)  # air

    # Soft-tissue sphere, centered.
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2 + (zz - cz) ** 2)
    vol[r < min(nx, ny, nz) * 0.32] = 40.0

    # Denser bone cube, offset toward +x/+y/+z so orientation is unambiguous.
    bx, by, bz = int(cx + nx * 0.18), int(cy + ny * 0.18), int(cz + nz * 0.18)
    half = 12
    vol[bz - half:bz + half, by - half:by + half, bx - half:bx + half] = 700.0

    stored = (vol + 1024.0).astype(np.int16)  # undo intercept for stored pixels

    for k in range(nz):
        ds = Dataset()
        fm = FileMetaDataset()
        fm.MediaStorageSOPClassUID = CTImageStorage
        fm.MediaStorageSOPInstanceUID = generate_uid()
        fm.TransferSyntaxUID = ExplicitVRLittleEndian
        ds.file_meta = fm

        ds.SOPClassUID = CTImageStorage
        ds.SOPInstanceUID = fm.MediaStorageSOPInstanceUID
        ds.StudyInstanceUID = study_uid
        ds.SeriesInstanceUID = series_uid
        ds.Modality = "CT"
        ds.PatientName = "DICOMBench^Phantom"
        ds.PatientID = "PHANTOM001"
        ds.SeriesNumber = 1
        ds.InstanceNumber = k + 1

        ds.Rows = ny
        ds.Columns = nx
        ds.PixelSpacing = [py, px]            # [row(y), col(x)]
        ds.SliceThickness = pz
        ds.ImageOrientationPatient = [1, 0, 0, 0, 1, 0]
        ds.ImagePositionPatient = [0.0, 0.0, float(k) * pz]
        ds.SamplesPerPixel = 1
        ds.PhotometricInterpretation = "MONOCHROME2"
        ds.BitsAllocated = 16
        ds.BitsStored = 16
        ds.HighBit = 15
        ds.PixelRepresentation = 1            # signed
        ds.RescaleIntercept = -1024.0
        ds.RescaleSlope = 1.0
        ds.WindowCenter = 40.0
        ds.WindowWidth = 400.0
        ds.PixelData = stored[k].tobytes()

        ds.save_as(os.path.join(out, f"slice_{k:03d}.dcm"), enforce_file_format=True)

    print(f"wrote {nz} slices to {out}  ({nx}x{ny}x{nz}, spacing {px}x{py}x{pz} mm)")


if __name__ == "__main__":
    main()
