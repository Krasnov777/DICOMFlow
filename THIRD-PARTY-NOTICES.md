# Third-Party Notices

DicomFlow statically links or bundles the following open-source components.
Each remains under its own license; full texts are available at the linked
upstream projects (and, where vendored, alongside the sources in this repo).

## DCMTK — DICOM Toolkit
- Version: 3.6.9 (built from source via `native/build-dcmtk.sh`)
- License: BSD 3-Clause
- Copyright © 1994–2024, OFFIS e.V., Oldenburg, Germany
- https://github.com/DCMTK/dcmtk

## OpenJPEG
- Version: 2.5.2 (built from source via `native/build-openjpeg.sh`)
- License: BSD 2-Clause
- Copyright © 2002–2014, Université catholique de Louvain (UCL), Belgium;
  Professor Benoit Macq; and contributors
- https://github.com/uclouvain/openjpeg

## fmjpeg2koj — JPEG 2000 codec for DCMTK
- License: Apache License 2.0 (see `native/fmjpeg2k/LICENSE`)
- Copyright © Ing-Long Eric Kuo
- https://github.com/DraconPern/fmjpeg2koj

This product includes software developed by Ing-Long Eric Kuo (fmjpeg2koj).

## OpenSSL
- Version: 3.6.3 (static libraries vendored in `native/openssl/`)
- License: Apache License 2.0
- Copyright © The OpenSSL Project Authors
- https://www.openssl.org

This product includes software developed by the OpenSSL Project for use in
the OpenSSL Toolkit (https://www.openssl.org/).

## zlib
- Linked from the macOS SDK (`-lz`)
- License: zlib License
- Copyright © 1995–2024 Jean-loup Gailly and Mark Adler
