# ANDROID_RELEASE_SIGNING — the RestoFlow production signing identity

> Scope: **RELEASE-KEY-AND-PIPELINE-001**. How RestoFlow's official Android
> artifacts are signed, how the key is created and protected, and why a release
> build refuses to run without it. Owner document for signing; the build steps
> themselves stay in [ANDROID_BUILD.md](ANDROID_BUILD.md), and the on-tablet
> procedure in [ANDROID_FLEET_UPDATE_AND_ROLLBACK.md](ANDROID_FLEET_UPDATE_AND_ROLLBACK.md).

---

## 1. What was wrong

Every pilot APK up to and including **v20** was signed with the **Android debug
key**. Both `apps/pos` and `apps/kds` carried the stock Flutter template line:

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

That key is not an identity anyone owns. It is generated per machine, shared by
convention, trivially reproducible, and Android treats it as an ordinary signing
identity for update purposes. Three consequences mattered:

1. **No update path you control.** An app can only be updated in place by an APK
   signed with the *same* key. Debug-signed apps are effectively owned by
   whichever debug keystore built them.
2. **No provenance.** Nothing distinguishes an official RestoFlow build from one
   anybody else compiled.
3. **A silent cliff.** The first real production key would *break* in-place
   updates for every installed pilot app — which is exactly the migration
   documented in the fleet runbook.

Pilot artifacts were never distributed, so this was contained. It had to be
fixed before the first official release.

---

## 2. The signing identity

| | |
|---|---|
| Alias | `restoflow-production` |
| Certificate | `CN=RestoFlow Android Production, OU=Mobile Release, O=RestoFlow, C=IL` |
| Store format | PKCS#12 |
| Key | RSA 4096 |
| Signature | SHA-256 with RSA |
| Validity | ≥ 30 years (an Android app must be updatable for its whole life) |
| Used by | `com.restoflow.pos`, `com.restoflow.kds`, `com.restoflow.kiosk` and (since BIZBOT-ANDROID-RELEASE-V52) `com.restoflow.dashboard` |

POS and KDS deliberately share **one** identity. They are one product shipped as
a synchronized pair; two keys would double the loss surface for no benefit. The
kiosk (KIOSK-001-102) and the dashboard (BIZBOT-ANDROID-RELEASE-V52) sign with
the same identity for the same reason — one product, one key holder — while
keeping their own version lineages in `version.json`.

The certificate's **public SHA-256 fingerprint** is committed in
[`tools/android_release/version.json`](../tools/android_release/version.json).
That is not a secret — pinning it is what lets a build prove it was signed by
the real key rather than by a debug or replacement key.

---

## 3. Where the material lives

Nothing secret is in this repository, and nothing secret may ever enter it.

| Item | Location | Notes |
|---|---|---|
| Keystore (`.jks`/`.p12`) | outside the repo, e.g. `%USERPROFILE%\.restoflow\android-signing\` | never under `dist/`, never under a project folder |
| Backup A | separate encrypted external drive | byte-identical copy |
| Backup B | different encrypted drive or encrypted cloud vault | byte-identical copy |
| `signing.properties` | beside the keystore, outside the repo | holds both passwords |
| Path to properties | `RESTOFLOW_ANDROID_SIGNING_PROPERTIES` env var | user-level, not committed |
| Passwords | a password manager | never in chat, tickets, build logs, or CI |

The template is [`tools/android_release/signing.properties.example`](../tools/android_release/signing.properties.example)
— placeholders only, safe to track.

> **Not in GitHub Actions.** Signing secrets are deliberately *not* added to CI.
> Official artifacts are built locally by the key holder. Adding them to CI is a
> separate decision with its own threat model.

---

## 4. The key ceremony

> **STATUS: COMPLETE — 2026-08-04.** Saleh performed this ceremony manually in a
> secure local PowerShell session. Verified since:
>
> - the production identity exists under alias `restoflow-production` with the
>   expected subject, `SHA256withRSA`, a 4096-bit RSA key, and validity
>   **2026-08-04 → 2053-12-20**;
> - the primary keystore and **two independent backups** (Backup A and Backup B,
>   on separate removable volumes) are **byte-identical** — all three file
>   SHA-256 values match;
> - all three copies live **outside** the repository, and no keystore or
>   signing-properties file is tracked or visible to Git;
> - the public certificate fingerprint is pinned in
>   [`version.json`](../tools/android_release/version.json);
> - POS and KDS both resolve their release variant to **that same certificate**,
>   while debug variants remain debug-signed.
>
> **Official v21 has since been built with this key** — see §8. The procedure
> below is retained verbatim as the recovery and re-issue reference.

It must be run interactively, on the machine that will hold the key. It is
written to be run by a human because the passwords must be typed into a hidden
prompt — never passed as a command argument, where they would land in process
listings and shell history.

### 4.1 Create the key

```powershell
$dir = "$env:USERPROFILE\.restoflow\android-signing"
New-Item -ItemType Directory -Force $dir | Out-Null

& "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe" `
  -genkeypair -v `
  -keystore "$dir\restoflow-production.jks" `
  -storetype PKCS12 `
  -alias restoflow-production `
  -keyalg RSA -keysize 4096 -sigalg SHA256withRSA `
  -validity 12000 `
  -dname "CN=RestoFlow Android Production, OU=Mobile Release, O=RestoFlow, C=IL"
```

`keytool` prompts for the keystore password with hidden input. Do not add
`-storepass` / `-keypass`; that is precisely the leak this avoids.

### 4.2 Restrict permissions

```powershell
icacls "$dir" /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null
```

### 4.3 Two independent backups

Copy the keystore to **two** destinations that do not fail together — an
encrypted external drive and a different encrypted drive or cloud vault. Then
prove all three are the same file:

```powershell
Get-FileHash "$dir\restoflow-production.jks", "<BACKUP_A>\restoflow-production.jks", "<BACKUP_B>\restoflow-production.jks" -Algorithm SHA256
```

All three SHA-256 values must be identical. **A single copy is not a backup**;
until two verified copies exist, the P0 signing requirement is not complete.

### 4.4 Signing properties + environment

Copy the `.example` template to `$dir\signing.properties`, fill in the real
values, then:

```powershell
setx RESTOFLOW_ANDROID_SIGNING_PROPERTIES "$env:USERPROFILE\.restoflow\android-signing\signing.properties"
```

Open a new shell afterwards so the variable is present.

### 4.5 Record the public fingerprint

```powershell
pwsh tools/android_release/check_signing_identity.ps1 -RequireKey
```

Copy the printed SHA-256 into `expectedCertificateSha256` in
`tools/android_release/version.json` and commit it. Until a real fingerprint is
pinned there, the official runner refuses to build.

**Format matters.** Use the colon-separated UPPERCASE form exactly as `keytool`
prints it: `check_signing_identity.ps1` compares the ledger value directly
against `keytool`, while `verify_official_apk.ps1` strips the colons and
lowercases before comparing against `apksigner`. Only that one form satisfies
both.

> Do not confuse the two SHA-256 values in play. The **certificate fingerprint**
> (pinned in `version.json`, public) identifies the signing identity. The
> **keystore file hash** is only used to prove the backups are byte-identical
> and is not an identity.

---

## 5. Fail-closed behaviour

`apps/{pos,kds,kiosk,dashboard}/android/app/build.gradle.kts` resolve the release
signing config from the properties file and **never** fall back to debug (the
dashboard copy landed with BIZBOT-ANDROID-RELEASE-V52; until then its release
build type still carried the template debug-signing line and only pilot debug
builds were ever made):

```kotlin
signingConfig = signingConfigs.findByName("release")   // null when unavailable
```

A `restoflowValidateReleaseSigning` task is wired into `preReleaseBuild` (and
onto `assembleRelease`/`bundleRelease`/`packageRelease`) and throws before
anything compiles when:

- `RESTOFLOW_ANDROID_SIGNING_PROPERTIES` is unset,
- the properties file is missing or unreadable,
- any of `storeFile` / `storePassword` / `keyAlias` / `keyPassword` is missing,
- the keystore file is missing,
- the alias is absent from the keystore,
- the credentials cannot unlock the key.

The message is deliberately generic — *"Production Android signing
configuration is unavailable."* plus a short non-secret reason. Debug builds are
untouched.

**Verify it yourself** (this is the check that matters):

```powershell
$env:RESTOFLOW_ANDROID_SIGNING_PROPERTIES = ''
cd apps/pos/android; ./gradlew.bat :app:restoflowValidateReleaseSigning   # must FAIL
```

---

## 6. Building an official release

```powershell
pwsh tools/android_release/build_official_pair.ps1
```

It refuses to run unless the tree is clean, HEAD is `main` (or an explicitly
audited SHA), the fingerprint is pinned, signing resolves, and the hosted
backend configuration is correct. It builds POS then KDS from one commit,
verifies both artifacts, and writes `SHA256SUMS.txt` + `BUILD-METADATA.txt`. It
never installs, uploads, pushes, releases or deploys.

---

### Optional POS background-order notifications

`BIZBOT-POS-V64-FIREBASE-BUILD-PLUMBING-001` adds an explicit, default-OFF
POS-only build opt-in. After separate source/release authorization, use the
same official runner with:

```powershell
pwsh tools/android_release/build_official_pair.ps1 `
  -EnablePosBackgroundOrderAlerts `
  -FirebasePublicConfig "$env:USERPROFILE\.codex\local-config\BIZBOT-FIREBASE-PRODUCTION-SETUP-002\android-public-build-config.json"
```

The external JSON must contain exactly four string fields:
`BIZBOT_FIREBASE_APP_ID`, `BIZBOT_FIREBASE_API_KEY`,
`BIZBOT_FIREBASE_PROJECT_ID`, and `BIZBOT_FIREBASE_SENDER_ID`.
The project, number and Android app are pinned to the approved
`bizbot-production` / `31661231890` registration. Missing, malformed,
foreign, in-checkout or linked configuration fails before a build. No private
service-account or signing credential belongs in this file.

Only POS receives the Dart flag and matching native Gradle properties. The
runner temporarily scopes public inputs to that Flutter invocation, clears
them for KDS/default-OFF builds, and restores prior environment on success or
failure. Conflicting reserved JVM/Gradle settings fail closed rather than
overriding the audited inputs. Configuration values are never logged.

This plumbing does not authorize an APK build, consume reserved v64, modify
v63 artifacts, or activate Firebase/server notifications. Existing source,
signing, synchronized versions and APK/checksum verification gates still apply.
Synthetic checks (no APK, signing access or hosted calls):
`pwsh tools/android_release/test_firebase_build.ps1`.

## 7. Release history

| Version | Signing | Source | Status |
|---|---|---|---|
| 0.0.20 / 20 | Android **debug** key | `279c4fc` | pilot, manual tablet testing only, never distributed |
| 0.0.21 / 21 | `restoflow-production` | `ed803bb` | built 2026-08-04 and verified — never installed, never uploaded; superseded by v25 |
| 0.0.22 / 22 | `restoflow-production` | — | SKIPPED, never built (transitional vc23/vc24 consumed the codes below 25) |
| vc23 / vc24 | Android **debug** key | `a243fd6` / `f89c8c4` | POS-only transitional lane (Debug/JIT then Release/AOT); vc24 field-tested on SALEH-POS-TEST-01 |
| 0.0.25 / 25 | `restoflow-production` | `f76b67c` (app source `f89c8c4`) | POS fresh-installed 2026-08-06 on SALEH-POS-TEST-01 (paired, login, printer test, read-only smoke OK; no controlled end-to-end order); KDS never installed; updated in place by v26 |
| 0.0.26 / 26 | `restoflow-production` | `e62cc54` (app source `2b05204`) | POS updated IN PLACE over v25 on 2026-08-07 — state preserved; Offline foundation validated but THREE acceptance defects found (latched offline state, reconnect payment block, no offline pre-bill) — fixed by PR #202; updated in place by v27; KDS never installed |
| **0.0.27 / 27** | **`restoflow-production`** | `6a82ec8` (app source `b670b59`) | **POS updated IN PLACE over v26 on 2026-08-07 — FOCUSED ACCEPTANCE MATRIX PASSED: automatic reconnect without restart, Offline unpaid pre-bill printed, payment correctly blocked until sync then completed once on the reconciled order, no duplicates; KDS built, not installed; not uploaded** |
| 0.0.28 / 28 | `restoflow-production` | — | reserved, not planned in detail |
| 0.0.50 / 50 | `restoflow-production` | `d6a9934` (app source `e727e0c`) | built 2026-09-03 with the interim VEYRO brand — never installed, never uploaded; superseded by v51 before any rollout (code 50 stays consumed) |
| 0.0.51 / 51 | `restoflow-production` | `7326d03` (app source `f2bf734b`) | built 2026-09-06 — first official pair carrying the official BIZBOT visual identity; verified, never installed, never uploaded; kiosk 0.2.21 / 23 built from the same source. Superseded by v52 before any rollout: it predates the FINAL approved symbol (PR #262) and the POS navbar lockup (PR #263); code 51 stays consumed |
| 0.0.52 / 52 | `restoflow-production` | `4a3946b` (app source `8d6bc34a`) | built 2026-09-06 (BIZBOT-ANDROID-RELEASE-V52) — the first pair carrying the final approved BIZBOT symbol + the POS navbar lockup; owner-installed the same day on SALEH-POS-TEST-01 (no acceptance matrix recorded), never uploaded; kiosk 0.2.22 / 24 and the first production-signed dashboard 0.0.2 / 2 from the same source. Superseded by v53 (code 52 stays consumed) |
| 0.0.53 / 53 | `restoflow-production` | `28a9b42` (PR #266 merge) | built 2026-09-06 — transparent launcher icons (nothing behind the symbol) for all four apps + the frameless POS lockup + bar-centred identity; verified, never installed, never uploaded; kiosk 0.2.23 / 25 and dashboard 0.0.3 / 3 built from the same source. Superseded by v54 (code 53 stays consumed) |
| 0.0.54 / 54 | `restoflow-production` | `3e5b579` (PR #294 prep merge) | built 2026-10-05 with build_official_pair.ps1 — POS removable quick-note chips (PR #293); owner-installed on the tablet and reported working 2026-10-05; never uploaded. Output: dist/official-v54; archived without promotion to currentOfficialRelease |
| 0.0.55 / 55 | `restoflow-production` | `40aeb18` (PR #296 prep merge) | built 2026-10-06 with build_official_pair.ps1 — BIZBOT device-session heartbeat (PR #295); verified against the production pin; owner trial began 2026-10-06; never uploaded. Output: dist/official-v55 (with kiosk 0.2.24 / 26). Code 55 stays consumed |
| 0.0.56 / 56 | `restoflow-production` | — | planned 2026-10-06 (PR #298) for the POS manual cash-drawer button (PR #297); no build recorded in this ledger before v57 superseded it. Code 56 stays consumed: if a v56 pair was built outside the ledger, record it and never reuse 56 |
| 0.0.57 / 57 | `restoflow-production` | `556136f` (PR #319 source-refresh merge) | built 2026-10-13 with build_official_pair.ps1 — editing an order after it reached the kitchen (ORDER-EDIT-001A..001G) + fail-closed kitchen dispatch (PR #304) + order-detail ids (PR #305) + the cash-drawer button (PR #297); verify_official_apk.ps1 PASS for both against the production pin; not installed at record time; never uploaded. Output: dist/official-v57. Code 57 stays consumed |
| 0.0.58 / 58 | `restoflow-production` | `a739e6c2be6cecd3e668ed80623f5db2c70bd15d` (PR #325 normal merge; application inputs unchanged from approved `de292a6`) | built and verified 2026-10-14 with the unchanged official pair runner — Online Orders Inbox / Accept/Reject (PR #322), item notes and modifier quantities (PR #323), existing POS/offline/printing functionality. Both APKs pass production certificate, version, zipalign, apksigner, AOT and hosted/demo-disabled checks. POS 70525195 bytes; KDS 57922358 bytes. Output dist/official-v58 with SHA256SUMS.txt and BUILD-METADATA.txt. PR #314/#315 excluded. NOT installed, NOT uploaded; no hardware acceptance claimed. Code 58 stays consumed |
| 0.0.59 / 59 | `restoflow-production` | `4889760af75c10c8642ad7f39bdc786b791d415c` (PR #328 normal merge; application inputs unchanged from approved PR #327 merge `3186081`) | built and verified 2026-10-14 with the unchanged official pair runner — richer Online Orders Inbox, authenticated menu-ID photos and Android foreground pending-order double chimes/repeating alerts; existing decision recovery, notes, modifiers, offline and printing preserved. Both APKs pass production certificate, version, zipalign, apksigner, AOT and hosted/demo-disabled checks. POS 70607115 bytes; KDS 57922358 bytes. Output dist/official-v59 with verified SHA256SUMS.txt and BUILD-METADATA.txt. PR #314/#315 excluded; KDS implementation unchanged. NOT installed, NOT uploaded; physical audio/volume/DND/photo acceptance remains separately authorized, with no background/screen-off claim. Code 59 stays consumed |
| 0.0.60 / 60 | `restoflow-production` | `5cdca8d5cb8e62376fb57db88d627b1eecc29a15` (PR #332 normal merge; application inputs unchanged from approved `50bd8fb`) | built and verified 2026-10-15 with the unchanged official pair runner — PR #330 louder bundled foreground audio and PR #331 targeted kitchen printing after confirmed online acceptance, retaining v59 functionality. Both APKs pass production certificate, version, zipalign, apksigner, AOT and hosted/demo-disabled checks. POS 70785999 bytes; KDS 57922358 bytes. Independent checks reconcile both artifacts with dist/official-v60/SHA256SUMS.txt and BUILD-METADATA.txt. In-APK audio matches `47c6a0bee63e297116b98a56cdb9674785b60829cc967c22829485a7399a5d34`; targeted-print integration is present in all three POS ABIs. PR #314/#315 excluded; KDS implementation unchanged. NOT installed, NOT uploaded; no v60 physical acceptance or hosted changes. Code 60 stays consumed |
| 0.0.61 / 61 | restoflow-production | 40be700d687e014570c1bbcefad8991068e465b5 (application source17d8c1cd) | Reconciled2026-10-16 from actual official pair hashes/metadata: built/verified2026-10-15; POS70933455bytes, KDS57938742bytes. POS later owner-installed HOME hg; Inbox/audio PASS; automatic kitchen printing FAILED before claim with zero authorized sends/paper. NOT fully accepted; KDS NOT installed; NOT uploaded. Original build-time facts preserved; adbVerified=false. Code61 consumed. |
| 0.0.62 / 62 | restoflow-production | f0a2628ecb874996a16426075c3fc88664576f97 (approved application source a9ac1778) | Built and verified 2026-10-16 by unchanged official pair runner after main CI38897614692 passed. POS 75568549 bytes, KDS 57938786 bytes; actual SHA256SUMS.txt and BUILD-METADATA.txt reconcile. Both version0.0.62/62, production pin, non-debuggable AOT, demo=false, correct backend, signatures/alignment. POS SQLite present for all3 ABIs and matches fresh isolated loader-only PASS. 258 focused regressions and35 release-writer checks passed. NOT installed, NOT uploaded; no physical print acceptance. Code62 consumed. |
| 0.0.63 / 63 | restoflow-production | 9718e101ceb23897cda149e63b88095dc48eab35 (PR #338 merge; exact approved main) | Built and verified 2026-10-17 by unchanged official pair runner after source CI38980905685 passed. POS 75568549 bytes, KDS 57938786 bytes; actual checksums/metadata reconcile. POS includes the per-device POS-selected kitchen-label locale fix. Both version0.0.63/63, production pin, non-debuggable AOT, demo=false, correct backend, signatures and 16-KB ZIP alignment. POS SQLite hashes match preserved loader-tested v62 for all3 ABIs. 142 focused regressions and35 release-writer checks passed. NOT installed, NOT uploaded; no v63 physical acceptance. Code63 consumed. |
| 0.0.64 / 64 | restoflow-production | ecfdbec6985c160589684b2ccd8486af6142656e (PR #345 merge; exact approved main) | Built and verified 2026-10-17 by unchanged official pair runner after source CI39058672744 SUCCESS. POS 76048997 bytes, KDS 57938786 bytes; actual checksums/metadata reconcile. Both 0.0.64/64, pinned production certificate, non-debuggable AOT, demo=false, production backend, valid signatures and 16-KB ZIP alignment. POS Firebase background-alert Dart/native build opt-in ON; KDS OFF/absent and unchanged. NOT installed, NOT uploaded, NOT distributed; no physical or notification-delivery acceptance. Code64 consumed. |
| 0.0.65 / 65 | restoflow-production | 87a4552a9d344fcc8babaefb2664e34f0055c01d (PR #349 merge; exact approved main) | Built and verified 2026-10-18 by the unchanged official pair runner after source CI39126905219 SUCCESS. POS 76130917 bytes, KDS 57938786 bytes; preserved checksums, metadata and consumption receipt reconcile. Both 0.0.65/65, production pin, release/AOT, demo=false, production backend and valid signatures/alignment. POS Firebase/alert opt-in ON; KDS OFF/absent. PR #349 enable-flow correction included, not physically accepted. BUILT / PRODUCTION-SIGNED / VERIFIED / CONSUMED / NOT INSTALLED / NOT UPLOADED / NOT DISTRIBUTED. |
| **0.0.66 / 66** | **restoflow-production** | source and scope require separate owner approval | **Bookkeeping reservation only after verified v65; NOT approved for building, signing, installing or releasing. NOT planned, NOT built, NOT installed, NOT uploaded. No device, hosted, admission, notification or printing activation authorized.** |
| Kiosk 0.2.23 / 25 | `restoflow-production` | `28a9b422` (same source as the v53 pair) | built 2026-09-06 — official candidate; Production-signed, NOT installed, NOT uploaded; existing facts moved unchanged to kioskReleases |
| Kiosk 0.2.24 / 26 | `restoflow-production` | `40aeb18` (same source as the v55 pair) | built 2026-10-06 — BIZBOT device-session heartbeat (PR #295), pair runner's flags; verify_official_apk.ps1 PASS (production pin, portrait setting); never uploaded. No kiosk build is planned with v56 or v57 (no kiosk change) |

**v65 build reconciliation - 2026-10-18 (BIZBOT-ANDROID-V65-RELEASE-LEDGER-001).** The already completed official synchronized pair was built from clean isolated approved main/application source `87a4552a9d344fcc8babaefb2664e34f0055c01d` after PR #349 and source CI `39126905219` SUCCESS (application validation and pgTAP). The unchanged runner used `-SourceSha`, documented `-AllowNonMain`, `-EnablePosBackgroundOrderAlerts` and the approved external public Firebase configuration. Preflight began 12:59:56 UTC; the build ran 13:05:12-13:09:03 UTC (16:05:12-16:09:03 Asia/Jerusalem). The verification summary is timestamped 13:13:55.2329093 UTC; final readback completed at 13:14:29 UTC. Source identity is clean-build/receipt provenance, not an independently embedded APK Git field.

- POS: `RestoFlow-POS-official-v65-87a4552.apk`, **76130917 bytes**, SHA-256 `2c1b72e695f921b22405a6946d9867941da06a763500a223f1adb803cd9bbcf9`.
- KDS: `RestoFlow-KDS-official-v65-87a4552.apk`, **57938786 bytes**, SHA-256 `62277e3ca82e5444ea47a1245ffcee20b70eeaa3ead644c911ddc4108817e5a8`.
- Both: `0.0.65 / 65`, packages `com.restoflow.pos` / `com.restoflow.kds`, signing `restoflow-production`, certificate SHA-256 `4E:E0:03:49:AD:BD:65:24:49:6A:04:96:0B:AE:63:33:36:EE:BC:87:CB:6B:82:DF:7D:07:5C:F8:C4:7E:FA:E7`.

Both official verifiers PASS for package/version/certificate, signatures, ZIP alignment, non-debuggable release/AOT, demo=false and the production `oqmevrndtivqxgyvcmwy` backend with public client key only. Actual APK bytes/hashes independently reconcile with preserved `SHA256SUMS.txt`, `BUILD-METADATA.txt`, `runner-invocation.json`, `verification-summary.json` and the durable code-65 consumption receipt; independent artifact review is APPROVE. Privileged-credential/private-key pattern scans found no matches, without claiming absolute detection of arbitrary unknown strings. The original Gradle metadata field still contains the first output separator; the separate read-only probe established **Gradle 9.1.0**. Original artifacts and receipts were not repaired or replaced.

POS Dart/native Firebase/background-alert build opt-in is **ON**, with actual manifest/DEX, generated release BuildConfig and retained Dart inputs matching `bizbot-production`, sender `31661231890`, app `1:31661231890:android:1856c6d5ac4e64a229adcb`. Four alert components are enabled and non-exported; messaging auto-init and analytics remain false. No API-key value is recorded. KDS opt-in/configuration/alert integration remain **OFF/absent**, with application behavior unchanged.

Both APKs pass supplemental **16-KB ZIP alignment and all checked 64-bit ELF load alignment** checks. The existing 32-bit armeabi-v7a POS SQLite `p_align=4096` limitation remains; this is not an all-architecture ELF or physical-device compatibility claim. POS SQLite libraries for all three ABIs are byte-identical to v64, and native inventories are preserved. Six libdartjni.so GNU build-ID notes differ outside AOT; their code/data remain unchanged. No new native-loader or physical test was performed.

PR #349 preserves confirmed enable intent through asynchronous preparation and strengthens uncertain-registration cleanup/reconciliation. This build does **not** prove the HOME switch or registration is physically fixed, nor background notification delivery. Uncertain registration still requires reconciliation: **no restart, re-enable, provider/pairing reset or data clearing as a recovery shortcut**.

v65 is **BUILT / PRODUCTION-SIGNED / VERIFIED / CONSUMED / NOT INSTALLED / NOT UPLOADED / NOT DISTRIBUTED**. Code65 cannot be reused. Code66 is reserved for bookkeeping only and is **NOT approved for building, signing, installing or releasing**. The local code-65 receipt remains authoritative while this Draft reconciliation PR is unmerged. All previous ledger objects, acceptance supplements, v64 artifacts/receipts and `currentOfficialRelease` are unchanged. The owner subsequently reported v64 installed and working on HOME; this is owner testimony, not ADB verification or formal background-alert acceptance, and does not rewrite its original build-time record. PR #314/#315 remain excluded.

This two-file record authorizes no new build/signing, merge, installation, upload, distribution, release promotion, hosted/device action or notification pilot. Installation, promotion and any future pilot need separate owner approval. Existing checkout/printing protections are untouched; commercial cold-offline imported-spool behavior remains unapproved.

**v64 build record — 2026-10-17 (BIZBOT-ANDROID-V64-RELEASE-LEDGER-001).** The official synchronized pair was built from clean isolated approved main `ecfdbec6985c160589684b2ccd8486af6142656e` after PR #345 and source CI `39058672744` completed SUCCESS, including application validation and pgTAP. The unchanged runner used `-SourceSha`, its documented `-AllowNonMain` option, `-EnablePosBackgroundOrderAlerts` and the external public Firebase configuration. Build time was 21:59:20–22:03:13 Asia/Jerusalem. Both official verifiers PASS for packages `com.restoflow.pos` / `com.restoflow.kds`, version `0.0.64 / 64`, production certificate, signatures, alignment, non-debuggable AOT, demo=false and the `oqmevrndtivqxgyvcmwy` backend with public client key only. Both additionally pass 16-KB ZIP alignment; POS retains SQLite and AOT libraries for all three supported ABIs. Source identity is established by the clean exact-source build and metadata, not a separately embedded Git SHA.

- POS: `RestoFlow-POS-official-v64-ecfdbec.apk`, **76048997 bytes**, SHA-256 `6cf6358e9a895d2f68f2294fe39f797a5f1352c322175de212f3d73b1e819d76`.
- KDS: `RestoFlow-KDS-official-v64-ecfdbec.apk`, **57938786 bytes**, SHA-256 `327aaf7ee722a409722a1b934f4f6fcd19a405c6b1eb18910eb244f5e721b713`.
- Signing: `restoflow-production`, certificate SHA-256 `4E:E0:03:49:AD:BD:65:24:49:6A:04:96:0B:AE:63:33:36:EE:BC:87:CB:6B:82:DF:7D:07:5C:F8:C4:7E:FA:E7`.

POS Firebase background-alert build opt-in is **ON** in retained Dart inputs and native BuildConfig. The actual manifest/DEX and generated configuration match `bizbot-production`, sender `31661231890`, Android app `1:31661231890:android:1856c6d5ac4e64a229adcb`; its public API key was compared in memory and is not recorded here. Four alert components are enabled and non-exported, while Firebase messaging auto-init and analytics remain false. KDS opt-in is **OFF/absent**, with no alert Dart define, Firebase configuration or alert integration in its APK. KDS application behavior is unchanged. This is build verification, not device opt-in or notification-delivery acceptance.

The preserved `dist/official-v64/SHA256SUMS.txt`, `BUILD-METADATA.txt`, `verification-summary.json` and actual APK facts independently reconcile; both checksum entries pass PowerShell hashing and `sha256sum -c`. The original metadata has one known formatting limitation: its Gradle field contains the first output separator; a separate read-only probe confirmed **Gradle 9.1.0**, recorded in the verification summary. No metadata or artifact was rewritten. v63 APKs, checksums and metadata are hash-identical; prior ledger/history entries, owner-reported acceptance supplements and `currentOfficialRelease` are unchanged. PR #314/#315 remain excluded.

v64 is **BUILT / VERIFIED / CONSUMED / NOT INSTALLED / NOT UPLOADED / NOT DISTRIBUTED**, without a GitHub Release, physical acceptance or notification-delivery test. Code65 is reserved as bookkeeping only and is **NOT approved for building, installing or releasing**. Do not promote v64 to `currentOfficialRelease` before physical device acceptance. No APK build, installation, upload, application/runner/signing/Firebase change, hosted mutation, notification activation, order or printing occurs under this reconciliation. Existing business and printing protections remain untouched; commercial cold-offline imported-spool behavior remains unapproved. This PR requires separate merge approval and authorizes no device installation or notification activation.

**v63 build record — 2026-10-17.** The official synchronized POS/KDS pair was built from clean exact approved main 9718e101ceb23897cda149e63b88095dc48eab35, with no release-preparation source changes. The unchanged runner used `-SourceSha` and `-AllowNonMain`; both builds completed between 02:55:29 and 02:58:48 Asia/Jerusalem. `SHA256SUMS.txt` and `BUILD-METADATA.txt` reconcile with both actual APKs and the production certificate pin. Supplemental 16-KB ZIP alignment passes for both. POS native SQLite libraries for arm64-v8a, armeabi-v7a and x86_64 match the preserved v62 loader-tested binaries; no new loader or physical-device test was performed. PR #338 changes only automatic kitchen-label locale selection: each render uses one snapshot of that POS installation's selected language, without altering saved content, preparation totals, manual printing or send fencing. KDS functionality, shared inputs, dependencies, official runner, signing and backend configuration are unchanged from v62; PR #314/#315 are excluded. v63 is BUILT / VERIFIED / NOT INSTALLED / NOT UPLOADED, with no physical locale acceptance claim. Code63 is consumed and code64 reserved. No hosted, admission, policy, hold, device or printer action occurred; BLOCKED revision1264 and all625 holds were not modified. This record authorizes neither its own PR merge nor HOME installation. Do not rebuild v63 or resend an earlier order.

**v62 owner-reported installation and physical-print supplement — recorded 2026-10-17.** The v62 row and original release entry retain their build-time NOT INSTALLED/no-physical-acceptance facts. The owner subsequently confirmed installation of official v62 on HOME hg and one correct physical automatic kitchen ticket under BIZBOT-HOME-V62-REAL-PRINT-ACCEPTANCE-001. Backend evidence separately establishes one accepted canonical order, one targeted initial dispatch and one irreversible transport reservation. The later owner-operated website pilot also reached HOME, was accepted and physically printed with the expected preparation counts above the items. The owner reported English automatic labels while Arabic was selected, and Arabic labels on a manual POS kitchen reprint. Therefore v62 physical-print flow passed but full locale acceptance did not; the PR #338 correction is now included in v63 and is not yet physically verified. `ownerReportedAcceptanceRecords` appends these observations with `adbVerified=false`, preserving prior release records, hashes and `currentOfficialRelease`. No independent installed-certificate check or precise installation time, KDS installation, new physical test or commercial cold-offline imported-spool approval is inferred.

**v62 build record — 2026-10-16.** The synchronized production-signed pair was built from clean audited local source f0a2628ecb874996a16426075c3fc88664576f97, with application inputs identical to approved main a9ac17780c5adeaf6edde981c87a81159685787d. Only the ledger/documentation differ. The unchanged official runner used its documented audited-source options. All artifact identity, production backend, AOT, signature and alignment checks passed. Native SQLite packaging matches the loader-tested binaries; the isolated Android check opened no database. The metadata/record PR does not authorize its own merge or any HOME installation. Preserve BLOCKED1254, 624 holds, all earlier artifacts and the existing accepted-but-unsent test enrollment. HOME update requires fresh synchronization/outbox/uncertain-operation and local spool/key evidence, settings records, other printing clients quiescent and printers OFF during guarded startup. Never uninstall, clear data or reset pairing/keys. Cold-offline imported-spool commercial rollout remains unapproved.

**v61 reconciliation and limited HOME acceptance — recorded2026-10-16.** The preserved official pair checksums, metadata and actual artifacts reconcile with the ledger. Original NOT INSTALLED build-time evidence remains untouched. Later HOME installation is owner-reported (adbVerified=false), without independent installation timestamp or installed-certificate verification. Real pending-only Inbox/audio passed; automatic kitchen printing FAILED before claim, with one accepted canonical order but zero authorized sends/paper. The earlier preinstall gate was BLOCKED, not installation PASS. v61 is NOT fully accepted; no KDS installation or commercial offline-policy approval is claimed. Current owner authorization permits a clean local audited v62 source commit and the unchanged official pair runner, without a prior preparation-PR merge. Stop before installation and production mutation.

**v59 owner-reported acceptance supplement — recorded 2026-10-15.** The v59 row
and `previousOfficialReleases` entry above preserve their earlier build-time
NOT INSTALLED/no-acceptance facts. The owner subsequently reported successful
POS v59 installation and acceptance under BIZBOT-POS-V59-ACCEPTANCE-001:
foreground chime/repeats without overlap while the Inbox was closed, correct
photos/quantities/totals/notes, confirmed acceptance with badge/alert clearance
and at least 20 seconds of silence, and exactly one correct physical kitchen
ticket. `ownerReportedAcceptanceRecords` appends this evidence without changing
historical artifacts, hashes or `currentOfficialRelease`. This is owner testimony,
not Codex ADB, current-device certificate or hardware verification; no installation
date, DND/background capability or KDS installation is inferred.

**v60 rollout sequence — handoff only.** The approved source has been built and
both official APKs verified; the release-record PR records actual metadata and
reserves v61, without authorizing its own merge. With separate device authorization,
reconcile synchronization/uncertain
operations, record pairing/printer settings and update POS in place over v59
without uninstalling or clearing data. Verify device/PIN/pairing/printer health
before separately applying only
`20261014184409_bizbot_pos_audio_print_003_targeted_print`. Verify its private
attempt ledger, four authorized RPCs and existing printing compatibility, then
obtain separate authorization for one real acceptance/physical-print test.
Keep `WEB_ORDERS_ENABLED=false`, `WEB_ORDERS_TEST_ENABLED=false`, the test permit
unset and all channels disabled until Android and backend installations are
independently verified. Uncertain sends require operator reconciliation, never
automatic resend; at-most-once transmission is not guaranteed exactly-once paper.

**v21 was the first RestoFlow artifact ever signed with the production identity**
(verified production-signed, non-debuggable, `demo=false`, AOT, zipaligned,
`apksigner`-verified, correct hosted Supabase project) but was never installed;
official **v25** performed the actual one-time migration. Public SHA-256 values
for every official artifact are recorded in
[`version.json`](../tools/android_release/version.json); the artifact files
themselves stay local and git-ignored.

**The one-time pilot → production migration was completed for the POS on the
personal test tablet on 2026-08-06**: transitional vc24 (debug-signed) was
uninstalled and official v25 fresh-installed per
[ANDROID_FLEET_UPDATE_AND_ROLLBACK.md](ANDROID_FLEET_UPDATE_AND_ROLLBACK.md) §1,
then pairing (station record «SALEHPOS ONEPLUS»), employee login, printer
restore + physical test print and a read-only cashier smoke check were all
confirmed. **The first production-certificate update-in-place followed on
2026-08-07**: official v26 updated the installed v25 POS with no uninstall and
no data loss — pairing, printer configuration, shift state and employee access
all survived, proving the normal update path for every future official release.
The v26 offline validation passed its foundation (true cold-start offline,
cached menu, locally saved unpaid order, kitchen printing) and exposed three
acceptance defects — the offline state stayed latched after reconnect until an
app restart, an offline-created order stayed payment-blocked after reconnect,
and the unpaid pre-bill could not print offline — all fixed by PR #202
(`b670b59`). **v27 closed the loop on 2026-08-07**: another in-place update
preserved all state, and the focused acceptance matrix passed on real
hardware — the Offline banner cleared automatically on reconnection with the
app kept open, the unpaid preliminary bill printed while Offline, payment
stayed correctly unavailable until the Offline-created order synchronized and
then completed exactly once on the reconciled order, with no duplicate order
and no duplicate print. v27 is the current official release. The
operational restaurant tablet has still not been migrated: it requires the
full §1 outbox-drain gate and migration procedure before anything is installed
on it.

### Two runner defects fixed after the first official build

The v21 build was the first real exercise of the pipeline and exposed two bugs,
both fixed in `build_official_pair.ps1` (OFFICIAL-RELEASE-RUNNER-V21-002):

1. **`SHA256SUMS.txt` was unverifiable.** `WriteAllLines` uses
   `Environment.NewLine`, so the file was CRLF and `sha256sum -c` treated the
   trailing `\r` as part of each filename — both checks failed. A checksum file
   that cannot be verified is worse than none: it looks like provenance while
   providing none.
2. **`BUILD-METADATA.txt` was incomplete**, omitting toolchain versions,
   timestamps, per-artifact package/ABI/SDK/zipalign/signature/certificate
   detail and any comparison.

Both outputs now go through `release_output.ps1` (UTF-8 without BOM, LF-only,
deterministic field order, `NOT DETECTED` instead of silent omission, and a
hard refusal to emit signing material), covered by
`test_release_output.ps1`. The v21 directory's own metadata was corrected by
hand at the time and is left untouched as historical evidence.

## 8. If the key is lost

Losing the private key means **no existing installation can ever be updated in
place again**. Recovery requires a new key and a full uninstall/reinstall of
every device in the fleet, with the local-data loss that implies.

- Verify the two backups **quarterly** (`Get-FileHash` on all three).
- Never generate a "temporary" second production key.
- If the key is believed compromised, treat it as an incident: it can sign
  software that devices will accept as an update.
