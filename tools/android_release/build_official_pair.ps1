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

# OFFICIAL-RELEASE-RUNNER-V21-002: every output file goes through these writers,
# so SHA256SUMS.txt and BUILD-METADATA.txt have one tested format instead of two
# ad-hoc ones. See tools/android_release/test_release_output.ps1.
. (Join-Path $PSScriptRoot 'release_output.ps1')

function Stop-Release([string]$m) { Write-Output "STOP: $m"; exit 1 }

# Reads a tool version without letting a missing tool abort the release; the
# metadata records NOT DETECTED rather than pretending the field is absent.
function Get-ToolVersion([scriptblock]$Probe) {
    try {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $v = & $Probe 2>&1
        $ErrorActionPreference = $prev
        if ($null -eq $v) { return $null }
        $line = (@($v) | Where-Object { "$_".Trim() } | Select-Object -First 1)
        return "$line".Trim()
    }
    catch { return $null }
}

$buildStart = (Get-Date).ToString('s')

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
# SHA256SUMS.txt is written LF-only, UTF-8 without BOM, bare filenames, POS then
# KDS. The v21 build wrote it with WriteAllLines (CRLF) and `sha256sum -c` could
# not open either artifact, so the one thing the file exists to prove - that
# these bytes are the released bytes - could not be checked.
$sumLines = Write-ReleaseChecksums -OutputRoot $OutputRoot `
    -FilePaths ($built | ForEach-Object { $_.Path })
Write-Output "checksums     $($sumLines.Count) entries written (LF, no BOM)"

# Re-read the file and re-verify both digests, so a broken checksums file fails
# the release instead of shipping alongside it.
$checksumsOk = $true
foreach ($line in (Get-Content (Join-Path $OutputRoot 'SHA256SUMS.txt'))) {
    if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { $checksumsOk = $false; continue }
    $expectHash = $Matches[1]; $entry = Join-Path $OutputRoot $Matches[2]
    if (-not (Test-Path $entry)) { $checksumsOk = $false; continue }
    if ((Get-FileHash $entry -Algorithm SHA256).Hash.ToLower() -ne $expectHash) { $checksumsOk = $false }
}
if (-not $checksumsOk) { Stop-Release 'SHA256SUMS.txt did not re-verify against the artifacts' }

# Per-artifact facts for the metadata record. The verifier above already FAILED
# the release on any bad posture, so these calls describe artifacts that are
# known good; they never decide whether to ship.
$sdkRoot = $env:ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if ([string]::IsNullOrWhiteSpace($sdkRoot)) { $sdkRoot = "$env:LOCALAPPDATA\Android\Sdk" }
$btDir = Get-ChildItem "$sdkRoot\build-tools" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1

function Get-ArtifactFacts($b) {
    $item = Get-Item $b.Path
    $facts = @{
        Filename    = $b.Name
        PackageId   = "com.restoflow.$($b.App.ToLower())"
        VersionName = $versionName
        VersionCode = $versionCode
        SizeBytes   = $item.Length
        SizeMiB     = [math]::Round($item.Length / 1MB, 2)
        Sha256      = (Get-FileHash $b.Path -Algorithm SHA256).Hash.ToLower()
        Created     = $item.LastWriteTime.ToString('s')
        Debuggable  = 'false'
        DemoMode    = 'false (RESTOFLOW_DEMO_MODE=false)'
        Aot         = 'AOT release (libapp.so present, no kernel_blob.bin)'
        ZipAlign    = 'verified'
        ApkSigner   = 'verified'
        SourceSha   = $head
    }
    if ($btDir) {
        $badging = & "$($btDir.FullName)\aapt.exe" dump badging $b.Path 2>&1
        $abi = ($badging | Select-String "^native-code:" | Select-Object -First 1)
        if ($abi) { $facts.Abi = (($abi.Line -replace "^native-code:\s*", '') -replace "'", '').Trim() }
        $min = ($badging | Select-String "^sdkVersion:'(\d+)'" | Select-Object -First 1)
        if ($min) { $facts.MinSdk = $min.Matches.Groups[1].Value }
        $tgt = ($badging | Select-String "^targetSdkVersion:'(\d+)'" | Select-Object -First 1)
        if ($tgt) { $facts.TargetSdk = $tgt.Matches.Groups[1].Value }
        $certs = & "$($btDir.FullName)\apksigner.bat" verify --print-certs $b.Path 2>&1
        $fp = ($certs | Select-String 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' | Select-Object -First 1)
        if ($fp) { $facts.CertSha256 = $fp.Matches.Groups[1].Value.ToLower() }
    }
    return $facts
}

$posB = $built | Where-Object { $_.App -eq 'POS' } | Select-Object -First 1
$kdsB = $built | Where-Object { $_.App -eq 'KDS' } | Select-Object -First 1

$javaVer = Get-ToolVersion { & java -version }
$gradleVer = Get-ToolVersion { & (Join-Path $repo 'apps/pos/android/gradlew.bat') --version --quiet }
$flutterRaw = Get-ToolVersion { & flutter --version }
$dartVer = Get-ToolVersion { & dart --version }

Write-ReleaseMetadata -OutputRoot $OutputRoot -Data @{
    TaskId                 = 'official Android release (tools/android_release/build_official_pair.ps1)'
    Status                 = 'BUILT and VERIFIED - not installed, not uploaded, not released'
    ReleaseName            = "RestoFlow official v$versionCode"
    VersionName            = $versionName
    VersionCode            = $versionCode
    Branch                 = $branch
    SourceSha              = $head
    SourceSubject          = (& git log -1 --format='%s' $head).Trim()
    BuildStart             = $buildStart
    BuildEnd               = (Get-Date).ToString('s')
    OutputDirectory        = (Split-Path $OutputRoot -Leaf)
    Flutter                = $flutterRaw
    Dart                   = $dartVer
    Java                   = $javaVer
    Gradle                 = $gradleVer
    BuildTools             = $(if ($btDir) { $btDir.Name } else { $null })
    ApkSignerTool          = $(if ($btDir) { 'apksigner (build-tools ' + $btDir.Name + ')' } else { $null })
    ZipAlignTool           = $(if ($btDir) { 'zipalign (build-tools ' + $btDir.Name + ')' } else { $null })
    CertAlias              = $alias
    CertFingerprint        = $expectedCert
    CertSignatureAlgorithm = $ledger.signingAlgorithm
    CertPublicKey          = $ledger.signingAlgorithm
    CertIsAndroidDebug     = 'NO - verified against the pinned production certificate'
    Pos                    = $(if ($posB) { Get-ArtifactFacts $posB } else { @{} })
    Kds                    = $(if ($kdsB) { Get-ArtifactFacts $kdsB } else { @{} })
    BackendHosted          = 'oqmevrndtivqxgyvcmwy verified present in both artifacts'
    BackendForbidden       = 'ktuupqsaxttrzajmvgif absent from both artifacts'
    BackendLocalhost       = 'absent - no localhost/test backend configuration'
    CreatedThisBuild       = 'YES - both artifacts were produced by this run'
    SameSourceSha          = "YES - both built from $head"
    VersionSymmetry        = "YES - POS and KDS both report $versionName / $versionCode"
    ChecksumsVerified      = 'YES - SHA256SUMS.txt re-read and both digests re-verified'
}

# ---- 8. Post-build source assertion -------------------------------------
if ((& git rev-parse HEAD).Trim() -ne $head) { Stop-Release 'HEAD moved during the release' }
if (-not [string]::IsNullOrWhiteSpace(((& git status --porcelain --untracked-files=no) -join ''))) {
    Stop-Release 'the release left tracked changes behind'
}

Write-Output ''
Write-Output "OFFICIAL PAIR BUILT AND VERIFIED -> $OutputRoot"
Write-Output 'NOT installed. NOT uploaded. NOT released.'
exit 0
