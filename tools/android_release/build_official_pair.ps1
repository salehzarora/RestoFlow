# ============================================================================
# RELEASE-KEY-AND-PIPELINE-001 - the OFFICIAL RestoFlow Android release runner.
#
# Builds the synchronized POS + KDS pair from one audited source commit, signed
# with the production key, and verifies every artifact before declaring success.
# It replaces the per-ticket dist/build-*.ps1 pilot runners, which were
# debug-signed, machine-specific and re-authored for every version.
#
# It DOES NOT and MUST NOT: install, upload, push, open a PR, create a GitHub
# Release, deploy, touch Supabase, or edit any tracked file.
#
# Credentials are never parameters here. The runner only learns where the
# signing properties live (RESTOFLOW_ANDROID_SIGNING_PROPERTIES); Gradle reads
# the secrets itself, so no password reaches a command line, a process listing,
# shell history, or a build log.
#
# Usage (from a clean tree on main):
#   pwsh tools/android_release/build_official_pair.ps1
#   pwsh tools/android_release/build_official_pair.ps1 -SourceSha <40-hex> -AllowNonMain
# ============================================================================
[CmdletBinding()]
param(
    [string]$SourceSha = '',
    [switch]$AllowNonMain,
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'
$repo = (& git rev-parse --show-toplevel).Trim()
Set-Location $repo

function Stop-Release([string]$m) { Write-Output "STOP: $m"; exit 1 }

Write-Output '===== RestoFlow official Android release ====='

# ---- 1. Source must be audited, clean and exactly what we intend ----------
$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
$head = (& git rev-parse HEAD).Trim()
$dirty = (& git status --porcelain --untracked-files=no)
Write-Output "branch        $branch"
Write-Output "HEAD          $head"
Write-Output "tree clean    $([string]::IsNullOrWhiteSpace(($dirty -join '')))"

if (-not [string]::IsNullOrWhiteSpace(($dirty -join ''))) {
    Stop-Release 'tracked working tree is dirty - an official artifact must match committed history exactly'
}
if ($SourceSha) {
    if ($head -ne $SourceSha) { Stop-Release "HEAD is not the requested audited source $SourceSha" }
}
if ($branch -ne 'main' -and -not $AllowNonMain) {
    Stop-Release 'official releases are built from main; pass -SourceSha <sha> -AllowNonMain for an audited exception'
}

# ---- 2. Version ledger is the single source of version truth --------------
$ledgerPath = Join-Path $repo 'tools/android_release/version.json'
$ledger = Get-Content $ledgerPath -Raw | ConvertFrom-Json
$versionName = $ledger.nextOfficialRelease.versionName
$versionCode = [int]$ledger.nextOfficialRelease.versionCode
$expectedCert = $ledger.expectedCertificateSha256
$alias = $ledger.signingKeyAlias
Write-Output "version       $versionName / $versionCode  (alias $alias)"

if ($expectedCert -eq 'PENDING_KEY_CEREMONY') {
    Stop-Release 'the production certificate fingerprint is still the placeholder in version.json - run the key ceremony and pin the real SHA-256 first'
}

# ---- 3. Production signing must be present and correct BEFORE building ----
$propsPath = $env:RESTOFLOW_ANDROID_SIGNING_PROPERTIES
if ([string]::IsNullOrWhiteSpace($propsPath) -or -not (Test-Path $propsPath)) {
    Stop-Release 'Production Android signing configuration is unavailable.'
}
& (Join-Path $repo 'tools/android_release/check_signing_identity.ps1') -RequireKey
if ($LASTEXITCODE -ne 0) { Stop-Release 'signing identity check failed' }

# ---- 4. Real-mode backend configuration ----------------------------------
$url = $env:RESTOFLOW_SUPABASE_URL
$key = $env:RESTOFLOW_SUPABASE_ANON_KEY
$expectedUrl = 'https://oqmevrndtivqxgyvcmwy.supabase.co'
if ($url -ne $expectedUrl) { Stop-Release 'RESTOFLOW_SUPABASE_URL is not the expected hosted project' }
if ([string]::IsNullOrWhiteSpace($key)) { Stop-Release 'RESTOFLOW_SUPABASE_ANON_KEY is not set' }
if ($key.StartsWith('sb_secret_') -or $key -match 'service_role') {
    Stop-Release 'the configured key is a SECRET key - only the public anon/publishable key may ship in a client'
}
Write-Output 'backend       hosted project verified, public key only, demo=false'

# ---- 5. Build POS then KDS sequentially ----------------------------------
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repo "dist/official-v$versionCode"
}
New-Item -ItemType Directory -Force $OutputRoot | Out-Null
$shortSha = $head.Substring(0, 7)
$built = @()

foreach ($app in @('pos', 'kds')) {
    $upper = $app.ToUpper()
    Write-Output "---------- $upper ----------"

    # Re-assert the source independently before EACH app.
    if ((& git rev-parse HEAD).Trim() -ne $head) { Stop-Release 'HEAD moved during the release' }
    if (-not [string]::IsNullOrWhiteSpace(((& git status --porcelain --untracked-files=no) -join ''))) {
        Stop-Release 'tracked tree became dirty during the release'
    }

    Push-Location (Join-Path $repo "apps/$app")
    try {
        & flutter build apk --release `
            --build-name=$versionName `
            --build-number=$versionCode `
            --dart-define=RESTOFLOW_DEMO_MODE=false `
            --dart-define=RESTOFLOW_SUPABASE_URL=$url `
            --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=$key
        if ($LASTEXITCODE -ne 0) { Stop-Release "$upper build failed" }
    }
    finally { Pop-Location }

    $src = Join-Path $repo "apps/$app/build/app/outputs/flutter-apk/app-release.apk"
    if (-not (Test-Path $src)) { Stop-Release "$upper release APK not found" }
    $name = "RestoFlow-$upper-official-v$versionCode-$shortSha.apk"
    $dest = Join-Path $OutputRoot $name
    Copy-Item $src $dest -Force
    $built += [pscustomobject]@{ App = $upper; Path = $dest; Name = $name }
    Write-Output "artifact      $name"
}

# ---- 6. Verify BOTH artifacts before declaring anything ------------------
foreach ($b in $built) {
    Write-Output "---------- verify $($b.App) ----------"
    & (Join-Path $repo 'tools/android_release/verify_official_apk.ps1') `
        -Apk $b.Path `
        -ExpectedPackage "com.restoflow.$($b.App.ToLower())" `
        -ExpectedVersionName $versionName `
        -ExpectedVersionCode $versionCode `
        -ExpectedCertSha256 $expectedCert `
        -ExpectedSourceSha $head
    if ($LASTEXITCODE -ne 0) { Stop-Release "$($b.App) artifact verification FAILED" }
}

# ---- 7. Checksums + non-secret metadata ---------------------------------
$sums = Join-Path $OutputRoot 'SHA256SUMS.txt'
$lines = foreach ($b in $built) { "$((Get-FileHash $b.Path -Algorithm SHA256).Hash.ToLower())  $($b.Name)" }
[System.IO.File]::WriteAllLines($sums, $lines, (New-Object System.Text.UTF8Encoding($false)))

$meta = @"
RestoFlow official Android release
==================================
version        $versionName / $versionCode
source sha     $head
branch         $branch
built          (local time recorded by the operator)
signing        alias $alias, certificate SHA-256 pinned in tools/android_release/version.json
posture        release, not debuggable, demo=false, AOT, hosted project verified

$(foreach ($b in $built) {
"$($b.App)
  file    $($b.Name)
  bytes   $((Get-Item $b.Path).Length)
  sha256  $((Get-FileHash $b.Path -Algorithm SHA256).Hash.ToLower())
"
})
Confirmations
  * neither artifact was installed, uploaded or distributed by this runner
  * no tracked file was modified; the version came from version.json and
    build-time arguments only
  * no commit, push, PR, GitHub Release, deployment or Supabase action occurred
  * no secret value appears in this file
"@
[System.IO.File]::WriteAllText((Join-Path $OutputRoot 'BUILD-METADATA.txt'), $meta,
    (New-Object System.Text.UTF8Encoding($false)))

# ---- 8. Post-build source assertion -------------------------------------
if ((& git rev-parse HEAD).Trim() -ne $head) { Stop-Release 'HEAD moved during the release' }
if (-not [string]::IsNullOrWhiteSpace(((& git status --porcelain --untracked-files=no) -join ''))) {
    Stop-Release 'the release left tracked changes behind'
}

Write-Output ''
Write-Output "OFFICIAL PAIR BUILT AND VERIFIED -> $OutputRoot"
Write-Output 'NOT installed. NOT uploaded. NOT released.'
exit 0
