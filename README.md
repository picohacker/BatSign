# BatSign 🦇

**A native, on-device IPA signer for iOS — Liquid Glass UI, powered by the zsign engine.**

BatSign signs `.ipa` files directly on your iPhone. No servers, no uploads, no accounts:
your certificates and your apps never leave your device.

> **Status: v1.0.0** — the latest build is compiled automatically by GitHub Actions.
> Grab the unsigned IPA from [Releases](../../releases) or the *Actions → artifacts* tab.

---

## Features

| | |
|---|---|
| 🦇 **On-device signing** | Real code signatures via a vendored [zsign](https://github.com/zhlynn/zsign) engine + OpenSSL 3.5, compiled for arm64 iOS |
| 🪪 **Certificate manager** | Import `.p12` + `.mobileprovision` pairs; live validity, team, kind (Development / App Store / Enterprise), device list, entitlements |
| 🧪 **Signing options** | Override display name, bundle ID, version, minimum iOS; strip app extensions / watch apps / embedded profiles / device limits; custom entitlements plist |
| 📦 **Tweak injection** | Add `.dylib` files to load at launch (weak or normal injection handled by the engine) |
| 📚 **App library** | Every import is parsed (icon, version, architectures, size, extensions) and re-signable in one tap |
| 🗞 **Live jobs** | Persistent signing queue with per-job engine log console, stages, durations, re-run on failure |
| 🔔 **Instant notifications** | Job results and certificate-expiry warnings delivered as local notifications (shown even in-app) and synced to an in-app notification center — deduplicated, never lost across relaunches |
| ♻️ **Background upkeep** | `BGTaskScheduler` refresh/processing tasks keep certificate checks running while BatSign is away; signing holds a system activity token so your device doesn't sleep mid-job |
| 🫧 **Liquid Glass** | Built against the iOS 26 SDK: native `glassEffect` surfaces, animated mesh-gradient aurora, spring animations; graceful material fallback on iOS 17–18 |

## Install BatSign itself

BatSign ships **unsigned** — sign it with the same certificate you use for anything else:

1. Download `BatSign.ipa` from CI artifacts/releases.
2. Sign + install with **SideStore / Feather / AltStore / eSign / Xcode / Sideloadly** — pick your favorite.
3. Open BatSign, import your `.p12` + profile, and sign away.

## Using BatSign

1. **Certs tab → +** — import a `.p12`, its `.mobileprovision`, and the p12 password.
   BatSign parses validity, team, devices, and entitlements with public APIs only.
2. **Sign tab** — import an `.ipa` (Files app, AirDrop…), pick a certificate, adjust options, hit **Sign & Pack**.
3. **Activity tab** — watch the engine log live; when a job lands, share the signed IPA from the job card.
4. The signed IPA installs through your installer of choice (SideStore, Feather, eSign…).

### Honesty section — what BatSign can and cannot do

- ✅ Signing, metadata overrides, extension stripping, dylib injection, profile swapping — all real, all on-device.
- ✅ Notifications are instant and persisted; background refresh is the sanctioned iOS mechanism.
- ⚠️ iOS suspends background apps aggressively. The keep-alive layer uses `BGTaskScheduler` +
  activity tokens (no audio/location hacks). A sign job continues if the system grants time
  (most likely when charging); otherwise it's marked *Interrupted* and re-runs in one tap.
- ⚠️ BatSign signs; it does not install to SpringBoard — on-device installation of the *result*
  requires an installer with device pairing (SideStore/Feather/AltStore) or a jailbroken install path.
- ⚠️ Ad-hoc output (no certificate) is for testing — it will not install on a stock device.

## Building from source

Requirements: macOS with Xcode 26, [Homebrew](https://brew.sh), network access.

```bash
brew install xcodegen
./scripts/build-openssl.sh      # libcrypto for iOS arm64 (~5 min, cached afterwards)
swift scripts/make-icon.swift   # regenerate the icon asset
xcodegen generate
open BatSign.xcodeproj          # or:
xcodebuild -project BatSign.xcodeproj -scheme BatSign -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
./scripts/make-ipa.sh           # → BatSign.ipa
```

GitHub Actions does exactly this on `macos-26` (Xcode 26) — see [`.github/workflows/build.yml`](.github/workflows/build.yml).

## Architecture

```
BatSign/
├── BatSign/                 # SwiftUI app
│   ├── App/                 # Entry point, root tab bar, app state
│   ├── Core/
│   │   ├── ZIP/             # Dependency-free ZIP reader (EOCD/ZIP64/deflate)
│   │   ├── IPA/             # IPA metadata + icon + Mach-O probing
│   │   ├── Certs/           # p12 (SecPKCS12Import), profiles, keychain, manager
│   │   ├── Signing/         # Swift wrapper over the C bridge
│   │   ├── Jobs/            # Persistent queue, engine logs, notifications
│   │   ├── Notifications/   # Instant hub + UNUserNotificationCenter delivery
│   │   └── KeepAlive/       # BGTaskScheduler upkeep
│   └── Features/            # Sign, Apps, Certs, Activity, Settings screens
├── Vendor/zsign/            # Vendored zsign (MIT) + BatSign C bridge
├── scripts/                 # OpenSSL cross-build, packaging, icon renderer
└── .github/workflows/       # CI that produces the IPA
```

## Credits & licenses

- [zsign](https://github.com/zhlynn/zsign) — MIT — the signing engine (vendored, with a small log-hook patch, see `docs/VENDORING.md`).
- [OpenSSL](https://www.openssl.org) — Apache-2.0 — built for iOS by `scripts/build-openssl.sh`.
- minizip/zlib — zlib license — bundled with zsign.
- BatSign app code — MIT (see [LICENSE](LICENSE)).

Signing other people's apps with certificates you don't own may violate agreements and laws.
Use BatSign with your own certificates and respect software licenses.
