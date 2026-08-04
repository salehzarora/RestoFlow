# ANDROID_FLEET_UPDATE_AND_ROLLBACK — installing RestoFlow on real tablets

> Scope: **RELEASE-KEY-AND-PIPELINE-001**. The controlled-sideloading runbook for
> Level A restaurant operation: the one-time migration off the debug-signed pilot
> apps, normal updates afterwards, rollback, and the lost-key case. Signing
> itself is owned by [ANDROID_RELEASE_SIGNING.md](ANDROID_RELEASE_SIGNING.md).

**The rule behind every procedure here:** the POS holds unsynced work in a local
outbox. Uninstalling an app deletes that local data. **Never uninstall while the
outbox is non-empty** — those orders and payments do not exist anywhere else yet.

---

## 1. One-time migration from the debug-signed pilot

Do this **once**, before official operation begins, at a time when the
restaurant is not serving.

> **Why an uninstall is unavoidable.** Android only allows an in-place update
> when the new APK is signed with the **same** key as the installed one. The
> pilot apps (up to v20) were debug-signed; the official build is signed with
> `restoflow-production`. The certificates differ, so the install is **rejected**
> (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`) until the old app is removed. This
> happens exactly once — every later official update installs straight over.

### Before touching anything

1. **Stop taking new orders.** Announce it; do not rely on the screen being idle.
2. **Drain the POS outbox.** Open the outbox indicator and confirm **all three**
   are zero:
   - pending = 0
   - failed = 0
   - delivery-unconfirmed = 0

   If anything is non-zero: restore connectivity and let it sync. Do **not**
   continue. A pending operation is an order or payment that exists only on this
   tablet.
3. **Confirm payments and shifts are synchronized.** Close the shift if one is
   open, and confirm the shift/cash-drawer session is settled server-side.
4. **Record the device pairing.** Note the branch, station/device label and role
   for each tablet — you will re-pair after installing.
5. **Record local device settings**, which live only on the tablet:
   - assigned printer(s): network IP + port, or the paired Bluetooth device,
   - printer-only / KDS mode selection,
   - language, and any per-device toggles (auto-print, etc.).
   A photo of each settings screen is enough.
6. **Close the app** properly (not just background it).

### The migration

7. **Uninstall** the pilot app. POS: `com.restoflow.pos`. KDS: `com.restoflow.kds`.
   *This erases local app data — that is why steps 2–5 exist.*
8. **Verify the artifact before installing.** Compare its SHA-256 against
   `SHA256SUMS.txt` from the official build. Do not install an APK you cannot
   match to a checksum.
9. **Install** the official production-signed APK.
10. **Re-pair the device** to its branch/station using a fresh pairing code.
11. **Reconfigure the printer** and grant Bluetooth/network permissions again.
12. **Run the smoke checklist** (§4).
13. **Do not open the official shift until §4 passes.**

Migrate and verify **one tablet at a time**. If the first one fails, you still
have a working floor.

---

## 2. Normal updates (production-signed → production-signed)

No uninstall. Pairing, printer settings and local data are all retained.

1. Drain the outbox (pending / failed / delivery-unconfirmed all zero).
2. Close the shift if the update lands mid-service.
3. Verify the artifact SHA-256 against `SHA256SUMS.txt`.
4. Confirm package, version and certificate:
   ```powershell
   pwsh tools/android_release/verify_official_apk.ps1 -Apk <file> `
        -ExpectedPackage com.restoflow.pos -ExpectedVersionName <x.y.z> `
        -ExpectedVersionCode <n> -ExpectedCertSha256 <pinned>
   ```
5. Install **over** the existing app.
6. Confirm the device is still paired and the printer still prints.
7. Run the smoke checklist.

---

## 3. Rollback

**There is no clean downgrade.** Plan around that rather than discovering it
mid-incident.

- **versionCode is monotonic.** Android refuses to install an APK whose
  `versionCode` is lower than the installed one. A "rollback APK" simply will
  not install.
- **Downgrading therefore means uninstall + reinstall**, which erases local data
  — the same risk as §1, but now during live service.
- **The default recovery is a forward fix**: build the next `versionCode` with
  the correction and install it normally. It is faster and loses nothing.
- **Emergency uninstall-based downgrade** requires, in order: outbox fully
  drained, shift closed, explicit documented approval from Saleh, and one tablet
  at a time.
- Never re-issue an already-used `versionCode` with different content.

---

## 4. Post-install smoke checklist

Run on every tablet before it returns to service.

- App launches and shows the **correct restaurant identity** in the POS top bar.
- Device is paired; the expected branch/station appears in device settings.
- Staff PIN sign-in works.
- Menu loads with real data (not demo).
- Create a test order → send to kitchen → it appears on KDS / prints.
- Printer test print succeeds.
- Outbox shows zero pending after the test order syncs.
- **Void the test order** so it does not pollute reporting.
- Language/RTL renders correctly.

---

## 5. If the signing key is lost

- Existing installations **can never be updated in place again**.
- Replacement with a different key forces a **full fleet uninstall + reinstall**,
  with local-data loss on every device.
- The two backups must be verified quarterly.
- Nobody should generate an alternative production key casually — doing so
  splits the fleet permanently.

See [ANDROID_RELEASE_SIGNING.md](ANDROID_RELEASE_SIGNING.md) §7.
