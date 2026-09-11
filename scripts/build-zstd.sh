#!/bin/bash
# Builds libzstd (static) for iOS — used to unpack .deb tweaks whose data.tar
# is zstd-compressed (the dpkg default since Debian 11).
#
# Layout:
#   Vendor/zstd/include/*.h                 shared by all platforms
#   Vendor/zstd/iphoneos/libzstd.a
#   Vendor/zstd/iphonesimulator/libzstd.a
#
# Xcode selects the library slice via $(PLATFORM_NAME).
# Usage: build-zstd.sh [iphoneos|iphonesimulator|all]
set -euo pipefail

ZSTD_VERSION="${ZSTD_VERSION:-1.5.6}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/zstd"

build_one() {
  local sdk="$1" outdir="$2" minflag="$3"
  local libdir="$VENDOR/$outdir"
  if [ -f "$libdir/libzstd.a" ]; then
    echo "[zstd] $outdir already built — skipping"
    return 0
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
    CFLAGS="-arch arm64 -isysroot ${sdkpath} ${minflag} -O2"

  mkdir -p "$libdir"
  cp lib/libzstd.a "$libdir/libzstd.a"

  if [ ! -f "$VENDOR/include/zstd.h" ]; then
    mkdir -p "$VENDOR/include"
    cp lib/zstd.h lib/zstd_errors.h lib/zdict.h "$VENDOR/include/"
  fi

  echo "[zstd] done → $libdir/libzstd.a ($(du -h "$libdir/libzstd.a" | cut -f1))"
}

case "${1:-all}" in
  iphoneos)          build_one iphoneos iphoneos "-miphoneos-version-min=16.0" ;;
  iphonesimulator)   build_one iphonesimulator iphonesimulator "-miphonesimulator-version-min=16.0" ;;
  all)               build_one iphoneos iphoneos "-miphoneos-version-min=16.0"
                     build_one iphonesimulator iphonesimulator "-miphonesimulator-version-min=16.0" ;;
  *) echo "unknown platform: $1 (expected iphoneos|iphonesimulator|all)" >&2; exit 1 ;;
esac
