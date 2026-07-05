#!/bin/bash
# Build DCMTK as a static arm64 library and package DCMTKit.xcframework.
# Static xcframework pattern. ~10–20 min first run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$HERE/build"
SRC="$WORK/dcmtk-src"
BUILD="$WORK/dcmtk-build"
INSTALL="$WORK/dcmtk-install"
TAG="${DCMTK_TAG:-DCMTK-3.6.9}"
DEPLOY="14.0"

mkdir -p "$WORK"

if [ ! -d "$SRC" ]; then
    echo "==> Cloning DCMTK $TAG"
    git clone --depth 1 --branch "$TAG" https://github.com/DCMTK/dcmtk.git "$SRC"
fi

echo "==> Configuring (static, arm64, builtin dictionary, libs only)"
rm -rf "$BUILD" "$INSTALL"
cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_APPS=OFF \
    -DDCMTK_DEFAULT_DICT=builtin \
    -DDCMTK_USE_DCMDICTPATH=OFF \
    -DDCMTK_ENABLE_PRIVATE_TAGS=ON \
    -DDCMTK_WITH_ZLIB=ON \
    -DDCMTK_WITH_OPENSSL=ON \
    -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DDCMTK_WITH_PNG=OFF \
    -DDCMTK_WITH_TIFF=OFF \
    -DDCMTK_WITH_XML=OFF \
    -DDCMTK_WITH_ICU=OFF \
    -DDCMTK_WITH_ICONV=OFF \
    -DDCMTK_WITH_SNDFILE=OFF

echo "==> Building"
cmake --build "$BUILD" --config Release -j"$(sysctl -n hw.ncpu)"
cmake --install "$BUILD" --config Release

echo "==> Combining static libs"
COMBINED="$WORK/libDCMTKit.a"
rm -f "$COMBINED"
libtool -static -o "$COMBINED" "$INSTALL"/lib/*.a

echo "==> Creating xcframework"
XCF="$HERE/DCMTKit.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework \
    -library "$COMBINED" -headers "$INSTALL/include" \
    -output "$XCF"

echo "✅ DCMTKit.xcframework ready at $XCF"
echo "   (combined lib: $(du -sh "$COMBINED" | cut -f1))"
