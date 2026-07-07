# ANDROID_BUILD — POS, KDS & Dashboard Android APKs for pilot testing

> Scope: **ANDROID-001** + **ANDROID-001B** (build/packaging setup only). This
> documents how to build installable **Android APKs** for the role apps —
> **`apps/pos`** (cashier), **`apps/kds`** (kitchen), and **`apps/dashboard`**
> (owner/manager) — so they can run on restaurant tablets for the hardware pilot.
> Motivation: the hosted **web** builds ([DEPLOYMENT.md](DEPLOYMENT.md)) cannot
> reliably reach Bluetooth / Wi-Fi / USB thermal printers from a browser; a native
> Android package is the path toward native printer support. (`apps/dashboard`
> stays the primary **web/Vercel** deploy as well — Android is additive.)
>
> This ticket added the Android platform scaffolding and configured app identity.
> It did **not** wire native printing and did **not** change any backend, schema,
> migration, or hosted deployment.

---

## 1. App identity

| App | Directory | `applicationId` (package) | Launcher label |
|---|---|---|---|
| RestoFlow POS | `apps/pos` | `com.restoflow.pos` | **RestoFlow POS** |
| RestoFlow KDS | `apps/kds` | `com.restoflow.kds` | **RestoFlow KDS** |
| RestoFlow Dashboard | `apps/dashboard` | `com.restoflow.dashboard` | **RestoFlow Dashboard** |

The IDs are distinct, so all three apps install side-by-side on one tablet. Identity
is set in each app's `android/app/build.gradle.kts` (`namespace` + `applicationId`),
`android/app/src/main/AndroidManifest.xml` (`android:label`), and
`android/app/src/main/kotlin/com/restoflow/<pos|kds|dashboard>/MainActivity.kt` (`package`).

---

## 2. Prerequisites (the build machine)

- **Flutter `3.44.2`** (the version pinned for CI/web — see [DEPLOYMENT.md](DEPLOYMENT.md) §1).
- **Android SDK** (via Android Studio or the command-line tools). Set `ANDROID_HOME`
  / `ANDROID_SDK_ROOT`, or point Flutter at it with `flutter config --android-sdk <path>`.
- **JDK 17** (bundled with a recent Android Studio; `compileOptions`/`jvmTarget` target 17).
- Confirm the toolchain with `flutter doctor` — the **Android toolchain** row must be `[√]`.

> **NOTE**: The initial ANDROID-001 packaging ran in an environment with **no
> Android SDK/JDK** (`flutter doctor` reported `[X] Android toolchain`), so the APK
> binaries were not produced then. After the toolchain was installed, both **debug
> APKs build successfully** — `flutter build apk --debug` for `apps/pos`,
> `apps/kds`, and `apps/dashboard` (verified). Confirm `flutter doctor` shows the
> Android row as `[√]` before building.

---

## 3. Build commands

Run from each app directory (`apps/pos`, `apps/kds`, `apps/dashboard`).

### 3a. Demo-mode APK (no backend, no secrets) — easiest for first install

The apps default to **demo mode** (`RESTOFLOW_DEMO_MODE` defaults `true`), which runs
fully offline with seeded data and needs **no** environment values. Good for verifying
install + UI on a tablet.

```bash
cd apps/pos       && flutter build apk --debug   # -> debug APK, no signing needed
cd apps/kds       && flutter build apk --debug
cd apps/dashboard && flutter build apk --debug
```

### 3b. Real-backend APK (hosted Supabase) — for a real pilot

Real mode is enabled with `--dart-define`, using the **same env-var NAMES as the web
build** (never literal secret values in source or in this doc). The **anon key is the
PUBLIC key** (RLS-gated) — never a service-role/secret key (**DECISION D-011**). Set
`RESTOFLOW_SUPABASE_URL` and `RESTOFLOW_SUPABASE_ANON_KEY` in your shell env first (the
same values used for Vercel — see [DEPLOYMENT.md](DEPLOYMENT.md) §2):

```bash
cd apps/pos && flutter build apk --release \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL" \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY"

cd apps/kds && flutter build apk --release \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL" \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY"

cd apps/dashboard && flutter build apk --release \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL" \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY"
```

Notes:
- The `main` (release) manifest declares `android.permission.INTERNET` so real-mode
  networking works on a release build — POS/KDS login, device pairing, and sync;
  Dashboard sign-in, org/branch data, and reports (ANDROID-001 / ANDROID-001B fix).
- `RESTOFLOW_PRINT_BRIDGE_URL` is a per-device **local loopback** define only; it is
  never a hosted value and is not needed for a normal pilot build.
- A `--release` APK is signed with the **debug** key by default (see §5) — fine for
  sideloading in a pilot, not for the Play Store.

### 3c. Output paths

```
apps/pos/build/app/outputs/flutter-apk/app-debug.apk         (or app-release.apk)
apps/kds/build/app/outputs/flutter-apk/app-debug.apk         (or app-release.apk)
apps/dashboard/build/app/outputs/flutter-apk/app-debug.apk   (or app-release.apk)
```

---

## 4. Installing on a tablet

- **With adb (USB debugging on):**
  ```bash
  adb install -r apps/pos/build/app/outputs/flutter-apk/app-release.apk
  adb install -r apps/kds/build/app/outputs/flutter-apk/app-release.apk
  ```
- **Manual:** copy the `.apk` to the tablet (USB / cloud / link) and tap it in a file
  manager. Allow "install unknown apps" for that source. Both apps appear as
  **RestoFlow POS** and **RestoFlow KDS**.

---

## 5. Follow-ups (out of scope for ANDROID-001)

- **Release signing (before Play Store or a signed pilot).** Generate a keystore,
  add `android/key.properties` (git-ignored) and a `release` `signingConfig` in each
  `android/app/build.gradle.kts`. **No keystore/keys were invented or committed** by
  this ticket. `*.jks`, `*.keystore`, `key.properties`, and `local.properties` are
  git-ignored; keep the keystore out of the repo.
- **Play Store.** App bundle (`flutter build appbundle`), store listing, versioning
  (`versionCode`/`versionName` — currently Flutter defaults), privacy declarations,
  and a signed upload key. Not started.
- **Native printing.** Native **network (Wi-Fi/Ethernet) ESC/POS printing is now
  wired for the POS app** (ANDROID-002) — see §7. **Bluetooth** and **USB** are still
  follow-ups (§7b). See **OPEN QUESTION Q-015** (encoding/raster fallback for
  Arabic/Hebrew) in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) and the printing owner doc
  [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).

---

## 6. Security & safety notes

- **No secrets in the repo.** URL/anon key are injected at compile time via
  `--dart-define` (env-var NAMES), never hardcoded; the anon key is public.
  `SupabaseBootstrapConfig` fails closed on a missing/placeholder/service-role key.
- **KDS is money-free.** The Android packaging adds no money handling; the kitchen
  app stays money-free.
- **Web deploy unchanged.** This ticket did not touch `apps/*/web/`,
  `tools/vercel_build_web.sh`, or `vercel.json`; the Vercel web build is unaffected.

---

## 7. Native network printing — POS (ANDROID-002)

The POS app can print directly to a **network (Wi-Fi/Ethernet) ESC/POS thermal
printer** with **no print bridge** and **no extra service**.

**How it works.** `packages/restoflow_printing` gains a `NetworkTcpPrintTransport`
(RAW/JetDirect over a `dart:io` TCP socket to `IP:9100`). It is **web-safe**: the
socket sender is selected by a conditional import (`dart.library.io`), so the web
apps never link `dart:io` and keep the existing print-bridge path unchanged. The POS
builds a money-free, ASCII **ESC/POS test document**, encodes it for an 80mm profile,
and sends the bytes over the socket. "Success" means the bytes were flushed to the
printer (best-effort; ESC/POS over a socket has no paper-print acknowledgement).

**Using it on a tablet.** POS app → ⋮ → **Device settings** → **Network printer (this
device)**: enter the printer **IP address** and **Port** (9100 default) + an optional
name → **Test print**. Status is honest: *not configured → saved → sending → sent /
failed*. The config is saved **locally** per device (`shared_preferences`, no secret,
never leaves the device). Once a printer is set up, the assigned-printer note/pill
drop the "Requires print bridge" wording (a bridge is no longer the only path).

**Permissions.** Only `android.permission.INTERNET` (already declared) — a raw TCP
socket needs no extra Android permission.

**No new dependencies.** Network printing uses only `dart:io`; no pub package or
native plugin was added.

### 7b. Bluetooth / USB printing — follow-up (deferred, ANDROID-002)

**Bluetooth Classic (SPP)** is the right target (many thermal printers are Classic,
not BLE), but it is deferred to its own ticket because it **cannot be verified here**
(no physical BT printer) and it needs a **native plugin** (e.g.
`flutter_bluetooth_serial` / `blue_thermal_printer` / `esc_pos_bluetooth`), each of
which adds an unvetted Android-only dependency + a maintenance/androidX risk. Shipping
Wi-Fi first (fully working, zero new deps) is the safe MVP, per the ticket's own
guidance. A Bluetooth follow-up must:

- Add a vetted Bluetooth Classic/SPP plugin and a `BluetoothClassicPrintTransport`
  behind the same `PrintTransport` port (keep web builds green with a conditional
  import / platform guard).
- Declare Android permissions **only when the feature ships** (to keep Play Store
  data declarations honest): `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` (Android 12+,
  with `usesPermissionFlags="neverForLocation"` on scan if discovery is
  location-free), the legacy `BLUETOOTH` + `BLUETOOTH_ADMIN` (`maxSdkVersion="30"`),
  and `ACCESS_FINE_LOCATION` **only if** discovery requires it on older Android.
- Request the runtime permissions from the app (a `permission_handler`-style flow),
  list paired/discovered devices, connect, and send the same ESC/POS test document.

**Encoding follow-up.** The test print is ASCII/English only. Localized Arabic/Hebrew
(RTL) printing goes through the raster path (RF-073, **OPEN QUESTION Q-015**) and is
not exercised by this diagnostic.
