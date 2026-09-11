# Vendored code notes

## zsign (`Vendor/zsign`)

- Source: https://github.com/zhlynn/zsign (MIT, see `Vendor/zsign/LICENSE`).
- Vendored at the `src/` tree; `src/zsign.cpp` (CLI `main`) is excluded from
  the build — `bridge/BatSignBridge.cpp` replaces it.
- **Patch applied** to `src/common/log.cpp`: at the top of `ZLog::_Print`,
  the logger calls `batsign_get_log_hook()` (declared extern "C") so the app
  receives every engine log line. Nothing else was modified.
- Windows-only minizip files (`iowin32.c`, `mztools.c`) are excluded.

## OpenSSL

Not vendored. `scripts/build-openssl.sh` fetches a pinned release tarball
(3.5.2 LTS) and cross-compiles `libcrypto.a` for iOS arm64 with the
`ios64-cross` target. CI caches the result.
