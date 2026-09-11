#!/bin/bash
# Assembles the unsigned BatSign.ipa from the Xcode build products.
# The app ships unsigned — the user signs it on-device with their own
# certificate (that is the entire point of BatSign).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCTS="$ROOT/build/Build/Products/Release-iphoneos"
OUT_IPA="$ROOT/BatSign.ipa"

APP="$(find "$PRODUCTS" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [ -z "$APP" ]; then
  echo "error: no .app found in $PRODUCTS" >&2
  exit 1
fi
echo "[ipa] packaging $(basename "$APP")"

STAGE="$(mktemp -d /tmp/batsign-ipa.XXXXXX)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/$(basename "$APP")"

rm -f "$OUT_IPA"
cd "$STAGE"
zip -qry "$OUT_IPA" Payload
cd "$ROOT"

echo "[ipa] wrote $OUT_IPA ($(du -h "$OUT_IPA" | cut -f1))"
