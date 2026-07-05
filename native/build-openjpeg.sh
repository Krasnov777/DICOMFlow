#!/bin/bash
# Build OpenJPEG as a static arm64 library for the JPEG2000 codec
# (native/fmjpeg2k, vendored from fmjpeg2koj). ~1 min.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/build"
SRC="$WORK/openjpeg-src"
BUILD="$WORK/openjpeg-build"
INSTALL="$HERE/openjpeg-install"
TAG="${OPENJPEG_TAG:-v2.5.2}"
DEPLOY="14.0"

mkdir -p "$WORK"

if [ ! -d "$SRC" ]; then
    echo "==> Cloning OpenJPEG $TAG"
    git clone --depth 1 --branch "$TAG" https://github.com/uclouvain/openjpeg.git "$SRC"
fi

echo "==> Configuring (static, arm64)"
rm -rf "$BUILD" "$INSTALL"
cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_CODEC=OFF \
    -DBUILD_TESTING=OFF >/dev/null

echo "==> Building"
cmake --build "$BUILD" -j "$(sysctl -n hw.ncpu)" >/dev/null
cmake --install "$BUILD" >/dev/null

echo "==> Done: $INSTALL"
ls "$INSTALL/lib" "$INSTALL/include"
