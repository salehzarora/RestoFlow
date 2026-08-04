# ============================================================================
# OFFICIAL-RELEASE-RUNNER-V21-002 — regression tests for the release writers.
#
# Covers the two defects the first official v21 build exposed, using the SAME
# production functions the runner calls, with synthetic values only. It builds
# nothing, needs no signing password, never touches the real signing properties
# and never reads the real keystore.
#
# Run:  pwsh tools/android_release/test_release_output.ps1
# ============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release_output.ps1')

$pass = 0
$fail = 0
function Ok([string]$m) { Write-Output "  PASS  $m"; $script:pass++ }
function Bad([string]$m) { Write-Output "  FAIL  $m"; $script:fail++ }
function Check([bool]$cond, [string]$m) { if ($cond) { Ok $m } else { Bad $m } }

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("restoflow-relout-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    Write-Output 'release-output regression tests'
    Write-Output ''

    # ---------------------------------------------------------------- TEST 1
    Write-Output 'TEST 1 - SHA256SUMS.txt is portable and verifiable'
    $posFake = Join-Path $tmp 'RestoFlow-POS-official-v99-abcdef1.apk'
    $kdsFake = Join-Path $tmp 'RestoFlow-KDS-official-v99-abcdef1.apk'
    [System.IO.File]::WriteAllBytes($posFake, [byte[]](1, 2, 3, 4, 5, 6, 7, 8))
    [System.IO.File]::WriteAllBytes($kdsFake, [byte[]](9, 8, 7, 6, 5, 4, 3, 2))

    $written = Write-ReleaseChecksums -OutputRoot $tmp -FilePaths @($posFake, $kdsFake)
    $sumsPath = Join-Path $tmp 'SHA256SUMS.txt'
    $bytes = [System.IO.File]::ReadAllBytes($sumsPath)
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)

    Check ($written.Count -eq 2) 'writer returned exactly two entries'
    Check (($text -split "`n" | Where-Object { $_ -ne '' }).Count -eq 2) 'file holds exactly two non-empty lines'
    Check (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'no UTF-8 BOM'
    Check (-not $text.Contains("`r")) 'no carriage return anywhere (LF-only)'
    Check ($text.EndsWith("`n") -and -not $text.EndsWith("`n`n")) 'exactly one final LF'
    Check ($text -notmatch '[A-Za-z]:\\' -and $text -notmatch '/tmp/') 'no absolute paths - bare filenames only'
    Check (($text -split "`n")[0] -match '^[0-9a-f]{64}  RestoFlow-POS-') 'POS is first, canonical "<sha256>  <name>" format'
    Check (($text -split "`n")[1] -match '^[0-9a-f]{64}  RestoFlow-KDS-') 'KDS is second'

    # Independent digest check (never trusts the writer's own hashing).
    $allMatch = $true
    foreach ($line in ($text -split "`n" | Where-Object { $_ -ne '' })) {
        if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { $allMatch = $false; continue }
        $f = Join-Path $tmp $Matches[2]
        if (-not (Test-Path $f)) { $allMatch = $false; continue }
        if ((Get-FileHash $f -Algorithm SHA256).Hash.ToLower() -ne $Matches[1]) { $allMatch = $false }
    }
    Check $allMatch 'both digests independently re-verify against the files'

    # The real thing: the tool that failed on v21. On Windows it usually lives
    # in the Git for Windows toolchain rather than on PATH, so look there too -
    # skipping this check is exactly how the v21 defect stayed invisible.
    $sha = Get-Command sha256sum -ErrorAction SilentlyContinue
    if (-not $sha) {
        foreach ($cand in @(
                "$env:ProgramFiles\Git\usr\bin\sha256sum.exe",
                "${env:ProgramFiles(x86)}\Git\usr\bin\sha256sum.exe",
                "$env:LOCALAPPDATA\Programs\Git\usr\bin\sha256sum.exe")) {
            if (Test-Path $cand) { $sha = [pscustomobject]@{ Source = $cand }; break }
        }
    }
    if ($sha) {
        Push-Location $tmp
        $out = & $sha.Source -c 'SHA256SUMS.txt' 2>&1
        $code = $LASTEXITCODE
        Pop-Location
        Check ($code -eq 0) "sha256sum -c accepts the file (exit $code)"
        Check (($out | Select-String ': OK').Count -eq 2) 'sha256sum reports OK for both artifacts'
    }
    else {
        Write-Output '  SKIP  sha256sum not on PATH; PowerShell digest check above stands in'
    }
    Write-Output ''

    # ---------------------------------------------------------------- TEST 2
    Write-Output 'TEST 2 - BUILD-METADATA.txt is complete and deterministic'
    $artifact = @{
        Filename = 'RestoFlow-POS-official-v99-abcdef1.apk'; PackageId = 'com.restoflow.pos'
        VersionName = '9.9.9'; VersionCode = 99; SizeBytes = 8; SizeMiB = 0.01
        Sha256 = ('a' * 64); Created = '2026-01-01T00:00:00'; Debuggable = 'false'
        DemoMode = 'false'; Aot = 'AOT release'; Abi = 'arm64-v8a'
        MinSdk = '24'; TargetSdk = '36'; ZipAlign = 'verified'; ApkSigner = 'verified'
        CertSha256 = ('b' * 64); SourceSha = ('c' * 40)
    }
    $kdsArtifact = $artifact.Clone()
    $kdsArtifact.Filename = 'RestoFlow-KDS-official-v99-abcdef1.apk'
    $kdsArtifact.PackageId = 'com.restoflow.kds'

    $data = @{
        TaskId = 'TEST'; Status = 'TEST'; ReleaseName = 'TEST'; VersionName = '9.9.9'
        VersionCode = 99; Branch = 'main'; SourceSha = ('c' * 40); SourceSubject = 'test subject'
        BuildStart = '2026-01-01T00:00:00'; BuildEnd = '2026-01-01T00:05:00'
        OutputDirectory = 'official-v99'
        Flutter = 'Flutter 9.9.9'; Dart = 'Dart 9.9.9'; Java = 'openjdk 9'; Gradle = 'Gradle 9'
        BuildTools = '37.0.0'; ApkSignerTool = 'apksigner'; ZipAlignTool = 'zipalign'
        CertAlias = 'restoflow-production'; CertFingerprint = ('b' * 64)
        CertSignatureAlgorithm = 'SHA256withRSA'; CertPublicKey = '4096-bit RSA'
        CertIsAndroidDebug = 'NO'
        Pos = $artifact; Kds = $kdsArtifact
        BackendHosted = 'verified'; BackendForbidden = 'absent'; BackendLocalhost = 'absent'
        CreatedThisBuild = 'YES'; SameSourceSha = 'YES'; VersionSymmetry = 'YES'
        ChecksumsVerified = 'YES'
        Comparison = "previous  v98`ncurrent   v99"
    }
    $lines = Write-ReleaseMetadata -OutputRoot $tmp -Data $data
    $metaPath = Join-Path $tmp 'BUILD-METADATA.txt'
    $mBytes = [System.IO.File]::ReadAllBytes($metaPath)
    $mText = [System.Text.Encoding]::UTF8.GetString($mBytes)

    $required = @(
        'Task ID', 'Status', 'Release name', 'versionName', 'versionCode', 'Branch',
        'Source SHA', 'Source subject', 'Build started', 'Build completed', 'Output directory',
        'Flutter', 'Dart', 'Java', 'Gradle', 'Android build-tools', 'apksigner', 'zipalign',
        'Alias', 'Certificate SHA-256', 'Signature algorithm', 'Public key', 'Is Android Debug',
        'POS ARTIFACT', 'KDS ARTIFACT', 'Filename', 'Package ID', 'Size (bytes)', 'Size (MiB)',
        'Created', 'Debuggable', 'Demo mode', 'AOT posture', 'ABI', 'minSdk', 'targetSdk',
        'Hosted project', 'Forbidden reference', 'Localhost/test backend',
        'Created this build', 'Same source SHA', 'Version symmetry', 'SHA256SUMS verified',
        'Installed', 'Uploaded', 'GitHub Release', 'Tracked source change', 'Commit or push'
    )
    $missing = @($required | Where-Object { $mText -notmatch [regex]::Escape($_) })
    Check ($missing.Count -eq 0) ("every mandatory field label present" + $(if ($missing.Count) { " (missing: $($missing -join ', '))" } else { '' }))

    Check (-not ($mBytes.Length -ge 3 -and $mBytes[0] -eq 0xEF -and $mBytes[1] -eq 0xBB -and $mBytes[2] -eq 0xBF)) 'no UTF-8 BOM'
    Check (-not $mText.Contains("`r")) 'no CRLF'
    Check (($mText -split "`n" | Where-Object { $_ -match '\s+$' }).Count -eq 0) 'no trailing whitespace on any line'
    Check ($mText.IndexOf('POS ARTIFACT') -lt $mText.IndexOf('KDS ARTIFACT')) 'POS section precedes KDS section'
    Check ($mText.IndexOf('RELEASE IDENTITY') -lt $mText.IndexOf('TOOLCHAIN')) 'deterministic section ordering'

    # Same input must produce byte-identical output.
    $again = New-ReleaseMetadataLines -Data $data
    Check (($again -join "`n") -eq ($lines -join "`n")) 'generation is deterministic for identical input'

    # Missing optional tool values must be explicit, never silently dropped.
    $sparse = $data.Clone()
    $sparse.Remove('Gradle'); $sparse['ApkSignerTool'] = ''; $sparse['ZipAlignTool'] = $null
    $sparseText = (New-ReleaseMetadataLines -Data $sparse) -join "`n"
    Check ($sparseText -match 'Gradle\s+NOT DETECTED') 'absent Gradle version renders NOT DETECTED'
    Check ($sparseText -match 'apksigner\s+NOT DETECTED') 'blank apksigner renders NOT DETECTED'
    Check ($sparseText -match 'zipalign\s+NOT DETECTED') 'null zipalign renders NOT DETECTED'
    Check (($sparseText -split "`n").Count -eq (($lines) -join "`n" -split "`n").Count) 'no field disappears when a value is missing'
    Write-Output ''

    # ---------------------------------------------------------------- TEST 3
    Write-Output 'TEST 3 - secret safety'
    Check ($mText -match ('b' * 64)) 'public certificate fingerprint IS allowed'
    foreach ($bad in @('storePassword', 'keyPassword', '.p12', '.jks', 'signing.properties', 'BEGIN RSA PRIVATE KEY')) {
        Check ($mText -notmatch [regex]::Escape($bad)) "metadata contains no '$bad'"
    }

    # The writer must REFUSE secret-bearing content outright.
    #
    # These fixtures are ASSEMBLED at runtime rather than written as literals.
    # A source line reading `storePassword=<something>` would (correctly) trip
    # tools/check_secrets.sh, and the honest fix is to not put the pattern in
    # the file - not to add this file to the guard's exemption list. The writer
    # still receives exactly the realistic strings it must reject.
    # Each element is PARENTHESISED on purpose: PowerShell's comma binds tighter
    # than `+`, so `"a$eq" + 'b', "c$eq" + 'd'` collapses into ONE concatenated
    # string and this loop would silently run once instead of five times.
    $eq = '='
    foreach ($leak in @(
            ("storePassword$eq" + 'Tr0ub4dor-and-3-horses'),
            ("keyPassword$eq" + 'hunter2'),
            ("storeFile$eq" + 'C:\Users\someone\keys\restoflow-production.p12'),
            ("backup$eq" + 'E:\Key-Backup\restoflow-production.jks'),
            ("properties$eq" + 'C:\Users\someone\signing.properties'))) {
        $threw = $false
        try { Write-ReleaseTextFile -Path (Join-Path $tmp 'leak.txt') -Lines @('safe line', $leak) }
        catch { $threw = $true }
        Check $threw "writer refuses to emit: $($leak.Split('=')[0])"
    }
    Check (-not (Test-Path (Join-Path $tmp 'leak.txt'))) 'no partial leak file was left behind'
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output "release-output tests: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
