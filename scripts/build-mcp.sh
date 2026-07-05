#!/usr/bin/env bash
# Build the DicomFlow MCP server (Release) and stage it at bin/dicomflow-mcp,
# then print the Claude Desktop / Claude Code config to point at it.
set -euo pipefail
cd "$(dirname "$0")/.."   # repo root (DicomFlow/)

echo "→ xcodegen"
xcodegen generate >/dev/null

echo "→ building dicomflow-mcp (Release)…"
DD="build-mcp"
LOG="/tmp/dicomflow-mcp-build.log"
if ! xcodebuild -project DicomFlow.xcodeproj -scheme dicomflow-mcp \
        -configuration Release -derivedDataPath "$DD" build >"$LOG" 2>&1; then
    echo "✗ build failed — last lines:"; tail -25 "$LOG"; exit 1
fi

mkdir -p bin
cp -f "$DD/Build/Products/Release/dicomflow-mcp" bin/dicomflow-mcp
BIN="$(cd bin && pwd)/dicomflow-mcp"
echo "✓ built: $BIN"

# Warn if the openssl@3 runtime dep is missing (only non-system dylib).
if ! otool -L "$BIN" | grep -q 'libssl'; then :; fi
if [[ ! -e /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib ]]; then
    echo "⚠ openssl@3 not found — run: brew install openssl@3"
fi

cat <<EOF

Add this to Claude Desktop
  (~/Library/Application Support/Claude/claude_desktop_config.json)
or Claude Code (claude mcp add), then restart the client:

{
  "mcpServers": {
    "dicomflow": {
      "command": "$BIN"
    }
  }
}

Add "args": ["--allow-write"] to enable the mutating tools (store/anonymize/…),
once those ship. Read-only + query/echo/render need no flag.
EOF
