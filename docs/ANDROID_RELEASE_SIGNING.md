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
| Used by | **both** `com.restoflow.pos` and `com.restoflow.kds` |

POS and KDS deliberately share **one** identity. They are one product shipped as
a synchronized pair; two keys would double the loss surface for no benefit.

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

`apps/{pos,kds}/android/app/build.gradle.kts` resolve the release signing config
from the properties file and **never** fall back to debug:

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
