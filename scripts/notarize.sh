#!/bin/bash
# Build, sign, notarize, and package DicomFlow.app into a distributable DMG.
#
# The repo builds unsigned by default so anyone can compile it. Maintainers
# distributing binaries provide their own credentials via a gitignored
# scripts/signing.env (or the environment):
#
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID="TEAMID"
#   APPLE_ID="you@example.com"          # for notarytool
#   APP_PW="app-specific-password"      # appleid.apple.com app password
#
# Requires a "Developer ID Application" certificate (not App Store's
# "Apple Distribution") — that's the one Gatekeeper accepts outside the store.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -f scripts/signing.env ] && source scripts/signing.env
: "${SIGN_IDENTITY:?set SIGN_IDENTITY (see header)}"
: "${TEAM_ID:?set TEAM_ID}"
: "${APPLE_ID:?set APPLE_ID}"
: "${APP_PW:?set APP_PW}"

DIST="$ROOT/dist"
DD="$ROOT/build-rel"
APP="$DD/Build/Products/Release/DicomFlow.app"
DMG="$DIST/DicomFlow.dmg"
mkdir -p "$DIST"

echo "==> Regenerate project"
xcodegen generate

echo "==> Build (Release, unsigned)"
xcodebuild -project DicomFlow.xcodeproj -scheme DicomFlow \
    -configuration Release -derivedDataPath "$DD" build

echo "==> Sign (Developer ID, hardened runtime)"
codesign --force --deep --options runtime --timestamp \
    --entitlements App/DicomFlow.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Notarize"
ZIP="$DIST/DicomFlow-notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
    --password "$APP_PW" --wait
rm -f "$ZIP"

echo "==> Staple"
xcrun stapler staple "$APP"

echo "==> Package DMG"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DicomFlow" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "✅ $DMG — signed, notarized, stapled."
