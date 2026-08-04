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
> **No APK or app bundle has been built with this key.** v21 is still planned
> only. The procedure below is retained verbatim as the recovery and re-issue
> reference.

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

## 7. If the key is lost

Losing the private key means **no existing installation can ever be updated in
place again**. Recovery requires a new key and a full uninstall/reinstall of
every device in the fleet, with the local-data loss that implies.

- Verify the two backups **quarterly** (`Get-FileHash` on all three).
- Never generate a "temporary" second production key.
- If the key is believed compromised, treat it as an incident: it can sign
  software that devices will accept as an update.
