# Local engine tests

`engine-harness.cpp` drives the vendored zsign bridge directly on macOS
(the bridge and engine are pure C/C++, identical code to the iOS build).

```bash
# build (minizip must compile as C, exactly like Xcode does)
clang -c -o zip.o  Vendor/zsign/src/third-party/minizip/zip.c
clang -c -o unzip.o Vendor/zsign/src/third-party/minizip/unzip.c
clang -c -o ioapi.o Vendor/zsign/src/third-party/minizip/ioapi.c
clang++ -std=c++17 -o engine_test tests/engine-harness.cpp Vendor/zsign/bridge/BatSignBridge.cpp \
  Vendor/zsign/src/{archo,bundle,certcheck,macho,metadata,openssl,signing}.cpp \
  Vendor/zsign/src/common/{archive,fs,json,log,sha,timer,util}.cpp zip.o unzip.o ioapi.o \
  -I Vendor/zsign/src -I Vendor/zsign/src/common -I Vendor/zsign/bridge \
  -I "$(brew --prefix openssl@3)/include" -L "$(brew --prefix openssl@3)/lib" -lcrypto -lz

./engine_test test.ipa out.ipa test.p12 PASSWORD test.mobileprovision new.bundle.id "New Name"

# verify
unzip out.ipa -d v && codesign -dvvv v/Payload/TestApp.app && codesign -v --verify v/Payload/TestApp.app
```

Verified locally (v1.0.0): ad-hoc sign, p12+profile sign with bundle-id and
display-name overrides, embedded profile, entitlements embedded,
`codesign --verify` integrity PASS.
