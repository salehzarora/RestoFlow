# POS transitional release-mode update strategy [POS-RUNTIME-RECOVERY-002]

> Status: recorded during POS-RUNTIME-RECOVERY-002 (2026-08-08). Planning
> record only — no build is produced by that task. Owner for execution: Saleh.

## 1. What went wrong with vc23

`RestoFlow-POS-transitional-debug-a243fd65-vc23.apk` was built as a **Flutter
Debug/JIT** APK on the stated reasoning that *"--debug is the only mode that
still signs with the same [Android debug] certificate"* (see the runner header
in `dist/build-transitional-pos-debug-a243fd65-vc23.ps1`). That reasoning is
**false**, and the Debug build both (a) runs an order of magnitude slower than
the Release pilot builds and (b) enabled Riverpod's debug assertions, which
exposed the kitchen-readiness provider defect this task repaired (a Debug-only
mid-build state write abort froze the cart on
«جارٍ التحقق من إعداد المطبخ…»).

## 2. Why the "Debug keeps the signer" claim is false

Android update compatibility depends on exactly three things:

1. the **package id** (`com.restoflow.pos`),
2. the **signing certificate** (currently the machine's Android debug
   certificate, SHA-256 `d427ec08…`),
3. a **non-decreasing `versionCode`**.

The Flutter build mode (Debug/JIT vs Release/AOT) plays **no part** in update
compatibility. The signer comes from the Gradle signing config, not from the
build mode:

* Historical proof in this repository: the smooth pilot pair **v20**
  (`RestoFlow-POS-pos-topbar-quick-tweak-v20-279c4fc.apk`) is a **Release/AOT**
  build (`BUILD-METADATA.txt`: `libapp.so` present, no `kernel_blob.bin`,
  `debuggable=False`) signed with the **same Android debug certificate** — and
  it updated the pilot chain v7…v19 in place.
* Current Gradle (`apps/pos/android/app/build.gradle.kts`): the release build
  type now resolves its keystore from the properties file named by
  `RESTOFLOW_ANDROID_SIGNING_PROPERTIES` and **fails closed** when unset. That
  is what pushed the vc23 builder to `--debug` — but the seam accepts ANY
  keystore, including the debug keystore itself.

## 3. The correct next transitional build (vc24)

Until the production-keystore migration window is scheduled, transitional
builds that must update the currently-installed debug-signed apps should be:

* **Flutter Release/AOT** (`flutter build apk --release`), demo=false, real
  Supabase defines — same as the v20 recipe;
* signed with the **same debug certificate** by pointing
  `RESTOFLOW_ANDROID_SIGNING_PROPERTIES` at a local properties file that names
  the debug keystore:

  a properties file with the four standard fields (`storeFile`,
  `storePassword`, `keyAlias`, `keyPassword`) filled with the well-known
  Android debug-keystore defaults: the store at
  `%USERPROFILE%\.android\debug.keystore`, the alias `androiddebugkey`, and
  the SDK's fixed, publicly documented debug store/key password (see the
  Android documentation on debug signing). These are not secrets — every
  Android SDK install shares them — but the literal values are deliberately
  kept out of this repository so the secret scanner stays strict.

  Note: the Gradle validation helper opens the store as PKCS12. If the local
  debug keystore is still JKS-format (older SDK installs), convert a COPY once:
  `keytool -importkeystore -srckeystore debug.keystore -destkeystore
  debug-p12.keystore -deststoretype pkcs12` and point the properties file at
  the converted copy. Verify with `apksigner verify --print-certs` that the
  emitted certificate digest is unchanged (`d427ec08…`) before installing.

* **`versionCode` 24** (`--build-name=0.0.24 --build-number=24`) — the
  installed transitional build is 23; Android refuses downgrades.
* Package id unchanged. Then `adb install -r` updates vc23 **in place** — no
  uninstall, no data loss, no re-pairing.

## 4. Boundaries

* This document changes nothing by itself: no keystore is generated, no signing
  material is touched, no build is produced.
* The dedicated production keystore plan (ANDROID-SIGNING-001) is unchanged and
  still required before official operation; the debug-certificate path above is
  strictly the **transitional** update lane for the already-installed pilot
  fleet.
* The release/version ledger (`tools/android_release/version.json`) remains the
  authority for official pair numbering; transitional versionCodes must keep
  ascending through it, never fork it.
