#!/bin/bash
# DicomFlow verification: build + unit tests + headless integration hooks.
#
#   bash scripts/verify.sh            # everything (skips hooks whose peer is absent)
#   bash scripts/verify.sh --fast     # unit tests only (no app build / hooks)
#
# Headless hooks run the app via `open -n --env …` from a fresh /tmp copy
# (App-Translocation workaround) and read their result from an output file.

set -uo pipefail
cd "$(dirname "$0")/.."

PROJ=(-project DicomFlow.xcodeproj -scheme DicomFlow -configuration Debug -derivedDataPath build)
APP=build/Build/Products/Debug/DicomFlow.app
PASS=0; FAIL=0; SKIP=0

say()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '\033[31m✗ %s\033[0m\n' "$*"; FAIL=$((FAIL+1)); }
skip() { printf '\033[33m– %s (skipped: %s)\033[0m\n' "$1" "$2"; SKIP=$((SKIP+1)); }

say "xcodegen + unit tests"
xcodegen generate >/dev/null || { bad "xcodegen"; exit 1; }
if xcodebuild "${PROJ[@]}" test >/tmp/dicomflow_test.log 2>&1; then
    ok "unit tests ($(grep -Eo 'Executed [0-9]+ tests' /tmp/dicomflow_test.log | tail -1))"
else
    bad "unit tests — see /tmp/dicomflow_test.log"
fi

[ "${1:-}" = "--fast" ] && { printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"; exit $((FAIL>0)); }

say "app build"
if xcodebuild "${PROJ[@]}" build >/tmp/dicomflow_build.log 2>&1; then
    ok "build"
else
    bad "build — see /tmp/dicomflow_build.log"; exit 1
fi

# run_hook <name> <out_file> <pass_pattern> <env KEY=VAL>…
run_hook() {
    local name=$1 out=$2 pattern=$3; shift 3
    local fresh="/tmp/DBverify_$name.app"
    rm -rf "$fresh" "$out"
    cp -R "$APP" "$fresh" && xattr -cr "$fresh"
    local envs=(); for kv in "$@"; do envs+=(--env "$kv"); done
    open -n "${envs[@]}" "$fresh"
    for _ in $(seq 1 40); do sleep 1; [ -f "$out" ] && break; done
    pkill -9 -f "DBverify_$name" 2>/dev/null
    rm -rf "$fresh"
    if [ -f "$out" ] && grep -q "$pattern" "$out"; then
        ok "$name"
    else
        bad "$name — $( [ -f "$out" ] && head -3 "$out" | tr '\n' ' ' || echo 'no output')"
    fi
}

say "headless hooks (self-contained)"
run_hook keychain /tmp/vk.txt  "deleted=true"        DICOMFLOW_KEYCHAIN=1 KEYCHAIN_OUT=/tmp/vk.txt
run_hook timeout  /tmp/vt.txt  "PASS (bounded)"      DICOMFLOW_TIMEOUT=1 TIMEOUT_S=5 TIMEOUT_OUT=/tmp/vt.txt
run_hook hl7      /tmp/vh.txt  "ACK is AA: true"     DICOMFLOW_HL7=1 HL7_OUT=/tmp/vh.txt
run_hook rotate   /tmp/vr.txt  "verdict=PASS"        DICOMFLOW_ROTATE=1 ROTATE_OUT=/tmp/vr.txt

say "headless hooks (need a peer / fixture)"
ORTHANC_HOST=${ORTHANC_HOST:-127.0.0.1}
if nc -z -G 2 "$ORTHANC_HOST" 4242 2>/dev/null; then
    run_hook mwl   /tmp/vm.txt "success=true"        DICOMFLOW_MWL=1 MWL_OUT=/tmp/vm.txt
    run_hook proto /tmp/vp.txt "A-ASSOCIATE"         DICOMFLOW_PROTO=1 PROTO_OUT=/tmp/vp.txt
    run_hook qr    /tmp/vq.txt "series success=true" DICOMFLOW_QR=1 QR_OUT=/tmp/vq.txt
    # DICOM TLS: local TLS-terminating proxy in front of Orthanc
    pkill -f tls-proxy.py 2>/dev/null
    python3 scripts/tls-proxy.py --listen 4243 --target "$ORTHANC_HOST:4242" >/tmp/vtlsproxy.log 2>&1 &
    TLSPID=$!; sleep 1
    run_hook tls /tmp/vtls.txt "verdict=PASS" DICOMFLOW_TLSTEST=1 TLS_HOST=127.0.0.1 \
        TLS_PORT=4243 TLS_CA=/tmp/dicom-tls/cert.pem TLS_OUT=/tmp/vtls.txt
    { kill "$TLSPID" && wait "$TLSPID"; } 2>/dev/null
else
    skip mwl "Orthanc $ORTHANC_HOST:4242 unreachable"
    skip proto "Orthanc $ORTHANC_HOST:4242 unreachable"
fi
FIXTURE=$(ls /tmp/orthanc_ct/*.dcm 2>/dev/null | head -1 || find /tmp/orthanc_ct -type f 2>/dev/null | head -1)
if [ -n "${FIXTURE:-}" ]; then
    run_hook validate /tmp/vv.txt "ok=true" "DICOMFLOW_VALIDATE=$FIXTURE" VALIDATE_OUT=/tmp/vv.txt
else
    skip validate "no fixture at /tmp/orthanc_ct"
fi

printf '\n\033[1m%d passed, %d failed, %d skipped\033[0m\n' "$PASS" "$FAIL" "$SKIP"
exit $((FAIL>0))
