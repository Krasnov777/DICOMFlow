# PyInstaller spec for the DICOMBench sidecar (arm64, onedir).
# Build: pyinstaller --noconfirm build_sidecar.spec
from PyInstaller.utils.hooks import collect_all, collect_submodules

datas, binaries, hiddenimports = [], [], []

# Packages that load plugins / data files dynamically and need full collection.
for pkg in [
    "pydicom", "pynetdicom",
    "pylibjpeg", "pylibjpeg_libjpeg", "pylibjpeg_openjpeg", "gdcm",
    "uvicorn", "fastapi", "starlette", "anyio",
]:
    try:
        d, b, h = collect_all(pkg)
        datas += d
        binaries += b
        hiddenimports += h
    except Exception:
        pass

hiddenimports += collect_submodules("encodings")

a = Analysis(
    ["entry.py"],
    pathex=["."],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    runtime_hooks=[],
    excludes=["tkinter", "matplotlib", "PIL"],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="dicom-sidecar",
    console=True,
    target_arch="arm64",
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe, a.binaries, a.datas,
    strip=False, upx=False, name="dicom-sidecar",
)
