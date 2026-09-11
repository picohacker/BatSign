#!/bin/bash
# Builds libcrypto (OpenSSL) for iOS arm64 device — required by the vendored
# zsign engine. Result is checked into the cache; safe to re-run.
#
# Env:
#   OPENSSL_VERSION   pinned OpenSSL release (default 3.5.2, LTS)
#   OPENSSL_NO_ASM=1  fall back to a pure-C build if assembly ever breaks
set -euo pipefail

OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/openssl"

if [ -f "$OUT/lib/libcrypto.a" ]; then
  echo "[openssl] already built at $OUT — skipping"
  exit 0
fi

echo "[openssl] building OpenSSL ${OPENSSL_VERSION} for iOS arm64"

SDK="$(xcrun -sdk iphoneos --show-sdk-path)"
# OpenSSL's ios64-cross expects CROSS_TOP/<CROSS_SDK layout under CROSS_TOP/SDKs.
export CROSS_TOP="$(dirname "$(dirname "$SDK")")"
export CROSS_SDK="$(basename "$SDK")"
export CC="$(xcrun -sdk iphoneos -f clang)"
export CFLAGS="-arch arm64 -fembed-bitcode-marker"

WORK="$(mktemp -d /tmp/batsign-openssl.XXXXXX)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TARBALL="$WORK/openssl-${OPENSSL_VERSION}.tar.gz"
URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
echo "[openssl] downloading ${URL}"
curl -sSL --retry 3 --retry-delay 5 -o "$TARBALL" "$URL"
tar -xzf "$TARBALL" -C "$WORK"
cd "$WORK/openssl-${OPENSSL_VERSION}"

NOASM_FLAG=""
if [ "${OPENSSL_NO_ASM:-0}" = "1" ]; then
  echo "[openssl] assembly disabled (OPENSSL_NO_ASM=1)"
  NOASM_FLAG="no-asm"
fi

./Configure ios64-cross $NOASM_FLAG \
  no-shared no-tests no-docs no-ui-console no-external-tests \
  --prefix="$OUT"

make -j "$(sysctl -n hw.ncpu)" build_libs

mkdir -p "$OUT/lib" "$OUT/include"
cp libcrypto.a "$OUT/lib/libcrypto.a"
cp -R include/openssl "$OUT/include/openssl"

echo "[openssl] done → $OUT/lib/libcrypto.a ($(du -h "$OUT/lib/libcrypto.a" | cut -f1))"
