# BatSign — Design

## Goal

A native on-device iOS IPA signer matching the capability set of the best
self-hosted signers (RyukSign / SignOs / Ksign) but running entirely on the
iPhone, with a native iOS 26 Liquid Glass interface, real background upkeep,
and instant persisted notifications.

## Non-goals

- No web service, no uploads, no accounts, no telemetry.
- No on-device SpringBoard installation (requires pairing-based installers;
  BatSign exports signed IPAs for them).
- No audio/location background hacks — sanctioned iOS background execution only.

## Signing engine

Vendored [zsign](https://github.com/zhlynn/zsign) (MIT) compiled for arm64 iOS
against a locally built OpenSSL 3.5 `libcrypto` (`scripts/build-openssl.sh`).
A thin C bridge (`Vendor/zsign/bridge`) replaces the CLI's `main()`:

- `batsign_sign_ipa(...)` replicates the CLI zip path: extract → apply
  metadata/injection/stripping via `ZBundle::SignFolder` → re-archive.
- `batsign_set_log_callback(...)` + a two-line hook in the vendored
  `log.cpp` stream every engine log line into Swift (job console + stages).

Swift never touches OpenSSL: p12 inspection uses the public
`SecPKCS12Import` + `SecCertificateCopyValues` APIs; provisioning profiles are
parsed by plist byte-range scan + `PropertyListSerialization`.

## Core subsystems

- **ZipReader** — dependency-free central-directory reader (ZIP64, deflate via
  the system `Compression` framework) for metadata/icon/icon/Mach-O probing.
  Heavy archive work is left to the engine.
- **JobQueue** — persistent serial queue (`Documents/Jobs/<id>/` snapshots the
  input so library edits can't break a queued job). Engine runs on a private
  serial DispatchQueue; all `@Published` mutations hop to main. Interrupted
  jobs are recovered on launch and re-runnable.
- **NotificationHub** — persisted, key-deduplicated notification store mirrored
  into `UNUserNotificationCenter` (identifiers = dedupe keys so replacements
  are instant, no polling). Foreground banners via delegate. Certificate expiry
  thresholds: 14/7/3/1/0 days.
- **BackgroundKeeper** — `BGAppRefreshTask` + `BGProcessingTask` chain
  maintenance; signing holds `beginActivity(.userInitiatedAllowingIdleSystemSleep)`.

## UI system

- `GlassSurface` modifier: native `.glassEffect(.regular[, .interactive()])` on
  iOS 26, `ultraThinMaterial` + stroke + shadow fallback on iOS 17–18.
- `AuroraBackground`: animated 3×3 `MeshGradient` (iOS 18+) with a drifting
  amber radial glow — the light source behind every glass surface.
- TabView with 5 tabs; iOS 26 renders the system Liquid Glass tab bar; the
  Activity tab carries the unread badge.

## Error handling

- Import validation happens before queueing (plist syntax check for custom
  entitlements; dylibs validated by the engine's Mach-O init).
- Engine failures map to human-readable causes by result code, with the full
  zsign log retained per job for diagnosis.
- Wrong p12 passwords, invalid profiles, corrupted archives all produce
  explicit, honest errors.

## Testing strategy

CI compiles on `macos-26` with Xcode 26 and verifies the produced IPA
structure (Payload/app, arm64 Mach-O, Info.plist). On-device behavior
(signing with real Apple certificates, notifications, background tasks) is
exercised manually per release; the engine itself is upstream-tested zsign.
