#!/bin/bash
# Builds libcrypto (OpenSSL) static libraries for iOS device and simulator —
# required by the vendored zsign engine. Each platform lives in its own
# directory so Xcode can pick the right slice via $(PLATFORM_NAME).
#
# Usage: build-openssl.sh [iphoneos|iphonesimulator|all]
# Env:
#   OPENSSL_VERSION   pinned OpenSSL release (default 3.5.2, LTS)
#   OPENSSL_NO_ASM=1  fall back to a pure-C build if assembly ever breaks
set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Vendor/openssl"
PLATFORM="${1:-all}"

build_one() {
  local sdk="$1" outdir="$2" configure_target="$3" extra_flags="$4"
  local out="$VENDOR/$outdir"
  if [ -f "$out/libcrypto.a" ]; then
    echo "[openssl] $outdir already built — skipping"
    return
  fi
  echo "[openssl] building OpenSSL ${OPENSSL_VERSION} for $sdk"

  local sdkpath
  sdkpath="$(xcrun -sdk "$sdk" --show-sdk-path)"
  export CROSS_TOP="$(dirname "$(dirname "$sdkpath")")"
  export CROSS_SDK="$(basename "$sdkpath")"
  export CC="$(xcrun -sdk "$sdk" -f clang)"
  export CFLAGS="-arch arm64 $extra_flags"

  local work
  work="$(mktemp -d /tmp/batsign-openssl.XXXXXX)"
  trap 'rm -rf "$work"' RETURN

  curl -sSL --retry 3 --retry-delay 5 -o "$work/openssl.tar.gz" \
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
  tar -xzf "$work/openssl.tar.gz" -C "$work"
  cd "$work/openssl-${OPENSSL_VERSION}"

  local noasm_flag=""
  if [ "${OPENSSL_NO_ASM:-0}" = "1" ]; then
    noasm_flag="no-asm"
  fi

  ./Configure "$configure_target" $noasm_flag \
    no-shared no-tests no-docs no-ui-console no-external-tests \
    --prefix="$out"

  make -j "$(sysctl -n hw.ncpu)" build_libs

  mkdir -p "$out/include"
  cp libcrypto.a "$out/libcrypto.a"
  cp -R include/openssl "$out/include/openssl"
  echo "[openssl] done → $out/libcrypto.a ($(du -h "$out/libcrypto.a" | cut -f1))"
}

case "$PLATFORM" in
  iphoneos)
    build_one iphoneos iphoneos ios64-cross "-mios-version-min=16.0"
    ;;
  iphonesimulator)
    build_one iphonesimulator iphonesimulator ios64-cross "-target arm64-apple-ios16.0-simulator"
    ;;
  all)
    build_one iphoneos iphoneos ios64-cross "-mios-version-min=16.0"
    build_one iphonesimulator iphonesimulator ios64-cross "-target arm64-apple-ios16.0-simulator"
    ;;
  *)
    echo "unknown platform: $PLATFORM" >&2
    exit 1
    ;;
esac
