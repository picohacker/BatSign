#!/bin/bash
# Builds libzstd (static) for iOS arm64 — used to unpack .deb tweaks whose
# data.tar is zstd-compressed (the dpkg default since Debian 11).
set -euo pipefail

ZSTD_VERSION="${ZSTD_VERSION:-1.5.6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/zstd"

if [ -f "$OUT/lib/libzstd.a" ]; then
  echo "[zstd] already built at $OUT — skipping"
  exit 0
fi

echo "[zstd] building zstd ${ZSTD_VERSION} for iOS arm64"

SDK="$(xcrun -sdk iphoneos --show-sdk-path)"
WORK="$(mktemp -d /tmp/batsign-zstd.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TARBALL="$WORK/zstd-${ZSTD_VERSION}.tar.gz"
URL="https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"
echo "[zstd] downloading ${URL}"
curl -sSL --retry 3 --retry-delay 5 -o "$TARBALL" "$URL"
tar -xzf "$TARBALL" -C "$WORK"
cd "$WORK/zstd-${ZSTD_VERSION}"

make -C lib lib-release -j"$(sysctl -n hw.ncpu)" \
  CC="$(xcrun -sdk iphoneos -f clang)" \
  CFLAGS="-arch arm64 -isysroot ${SDK} -miphoneos-version-min=17.0 -O2"

mkdir -p "$OUT/lib" "$OUT/include"
cp lib/libzstd.a "$OUT/lib/libzstd.a"
cp lib/zstd.h lib/zstd_errors.h lib/zdict.h "$OUT/include/"

echo "[zstd] done → $OUT/lib/libzstd.a ($(du -h "$OUT/lib/libzstd.a" | cut -f1))"
