#!/bin/bash
# Builds libzstd (static) for iOS device and simulator — used to unpack .deb
# tweaks whose data.tar is zstd-compressed (dpkg default since Debian 11).
#
# Usage: build-zstd.sh [iphoneos|iphonesimulator|all]
set -euo pipefail

ZSTD_VERSION="${ZSTD_VERSION:-1.5.6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/zstd"
PLATFORM="${1:-all}"

build_one() {
  local sdk="$1" outdir="$2" minos_flag="$3"
  local out="$VENDOR/$outdir"
  if [ -f "$out/libzstd.a" ]; then
    echo "[zstd] $outdir already built — skipping"
    return
  fi
  echo "[zstd] building zstd ${ZSTD_VERSION} for $sdk"

  local sdkpath
  sdkpath="$(xcrun -sdk "$sdk" --show-sdk-path)"

  local work
  work="$(mktemp -d /tmp/batsign-zstd.XXXXXX)"
  trap 'rm -rf "$work"' RETURN

  curl -sSL --retry 3 --retry-delay 5 -o "$work/zstd.tar.gz" \
    "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz"
  tar -xzf "$work/zstd.tar.gz" -C "$work"
  cd "$work/zstd-${ZSTD_VERSION}"

  make -C lib lib-release -j"$(sysctl -n hw.ncpu)" \
    CC="$(xcrun -sdk "$sdk" -f clang)" \
    CFLAGS="-arch arm64 -isysroot ${sdkpath} ${minos_flag} -O2"

  mkdir -p "$out/include"
  cp lib/libzstd.a "$out/libzstd.a"
  cp lib/zstd.h lib/zstd_errors.h lib/zdict.h "$out/include/"
  echo "[zstd] done → $out/libzstd.a ($(du -h "$out/libzstd.a" | cut -f1))"
}

case "$PLATFORM" in
  iphoneos)
    build_one iphoneos iphoneos "-miphoneos-version-min=16.0"
    ;;
  iphonesimulator)
    build_one iphonesimulator iphonesimulator "-miphonesimulator-version-min=16.0"
    ;;
  all)
    build_one iphoneos iphoneos "-miphoneos-version-min=16.0"
    build_one iphonesimulator iphonesimulator "-miphonesimulator-version-min=16.0"
    ;;
  *)
    echo "unknown platform: $PLATFORM" >&2
    exit 1
    ;;
esac
