# Third-Party Notices

DicomFlow statically links or bundles the following open-source components.
Each remains under its own license. Full license texts are in
[`THIRD-PARTY-LICENSES/`](THIRD-PARTY-LICENSES/) and at the linked upstream
projects.

**This software is based in part on the work of the Independent JPEG Group.**

DICOM® is the registered trademark of the National Electrical Manufacturers
Association (NEMA) for its Standards publications relating to digital
communications of medical information. DicomFlow is an independent tool and is
not certified, endorsed by, or affiliated with NEMA.

## DCMTK — DICOM Toolkit
- Version: 3.6.9 (built from source via `native/build-dcmtk.sh`)
- License: BSD 3-Clause (see `THIRD-PARTY-LICENSES/DCMTK-COPYRIGHT.txt`, which
  also covers the sub-packages below that DCMTK bundles)
- Copyright © 1994–2024, OFFIS e.V., Oldenburg, Germany
- https://github.com/DCMTK/dcmtk

### Bundled within DCMTK (statically linked into DicomFlow)
- **IJG JPEG codecs** (`dcmjpeg/libijg8|12|16`) — Independent JPEG Group
  license; Copyright © 1991–1998, Thomas G. Lane. https://ijg.org
- **CharLS** (`dcmjpls/libcharls`, JPEG-LS) — BSD 3-Clause;
  Copyright © 2007–2010, Jan de Vaan. https://github.com/team-charls/charls
- **log4cplus-derived logging** (`oflog`) — Apache-style two-clause license;
  Copyright © 1999–2009, Contributors to the log4cplus project.
  https://github.com/log4cplus/log4cplus

## OpenJPEG
- Version: 2.5.2 (built from source via `native/build-openjpeg.sh`)
- License: BSD 2-Clause (see `THIRD-PARTY-LICENSES/OpenJPEG-LICENSE.txt`)
- Copyright © 2002–2014, Université catholique de Louvain (UCL), Belgium;
  Professor Benoit Macq; and contributors
- https://github.com/uclouvain/openjpeg

## fmjpeg2koj — JPEG 2000 codec for DCMTK
- License: Apache License 2.0 (see `native/fmjpeg2k/LICENSE` /
  `THIRD-PARTY-LICENSES/Apache-2.0.txt`)
- Copyright © Ing-Long Eric Kuo
- https://github.com/DraconPern/fmjpeg2koj

This product includes software developed by Ing-Long Eric Kuo (fmjpeg2koj).

## OpenSSL
- Version: 3.6.3 (static libraries vendored in `native/openssl/`)
- License: Apache License 2.0 (see `THIRD-PARTY-LICENSES/Apache-2.0.txt`)
- Copyright © The OpenSSL Project Authors
- https://www.openssl.org

This product includes software developed by the OpenSSL Project for use in
the OpenSSL Toolkit (https://www.openssl.org/).

## zlib
- Linked from the macOS SDK (`-lz`; not redistributed by this project)
- License: zlib License
- Copyright © 1995–2024 Jean-loup Gailly and Mark Adler
