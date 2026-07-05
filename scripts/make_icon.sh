#!/bin/bash
# Generate the macOS AppIcon set from a 1024x1024 source PNG.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/../DF-Icon.png}"
OUT="$ROOT/App/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUT"

gen() { sips -z "$2" "$2" "$SRC" --out "$OUT/$1" >/dev/null; }
gen icon_16.png 16
gen icon_32.png 32
gen icon_64.png 64
gen icon_128.png 128
gen icon_256.png 256
gen icon_512.png 512
gen icon_1024.png 1024

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom":"mac", "scale":"1x", "size":"16x16",   "filename":"icon_16.png" },
    { "idiom":"mac", "scale":"2x", "size":"16x16",   "filename":"icon_32.png" },
    { "idiom":"mac", "scale":"1x", "size":"32x32",   "filename":"icon_32.png" },
    { "idiom":"mac", "scale":"2x", "size":"32x32",   "filename":"icon_64.png" },
    { "idiom":"mac", "scale":"1x", "size":"128x128", "filename":"icon_128.png" },
    { "idiom":"mac", "scale":"2x", "size":"128x128", "filename":"icon_256.png" },
    { "idiom":"mac", "scale":"1x", "size":"256x256", "filename":"icon_256.png" },
    { "idiom":"mac", "scale":"2x", "size":"256x256", "filename":"icon_512.png" },
    { "idiom":"mac", "scale":"1x", "size":"512x512", "filename":"icon_512.png" },
    { "idiom":"mac", "scale":"2x", "size":"512x512", "filename":"icon_1024.png" }
  ],
  "info" : { "author":"xcode", "version":1 }
}
JSON
echo "✅ AppIcon set written to $OUT"
