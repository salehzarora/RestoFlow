# ============================================================================
# RELEASE-KEY-AND-PIPELINE-001 - official APK verifier.
#
# Proves an artifact is what it claims to be, from the outside. Reads the
# archive IN MEMORY: an APK legitimately contains both res/9n.9.png and
# res/9N.9.png, which collide on a case-insensitive filesystem, so unpacking to
# disk is unsafe on Windows.
#
# Usage:
#   pwsh tools/android_release/verify_official_apk.ps1 `
#        -Apk <path> -ExpectedPackage com.restoflow.pos `
#        -ExpectedVersionName 0.0.21 -ExpectedVersionCode 21 `
#        -ExpectedCertSha256 <AA:BB:...> -ExpectedSourceSha <40-hex>
#
# Exit 0 = every check passed. Prints only public facts.
# ============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$ExpectedPackage,
    [Parameter(Mandatory = $true)][string]$ExpectedVersionName,
    [Parameter(Mandatory = $true)][int]$ExpectedVersionCode,
    [Parameter(Mandatory = $true)][string]$ExpectedCertSha256,
    [string]$ExpectedSourceSha = ''
)

$ErrorActionPreference = 'Stop'
$fail = 0
function Fail([string]$m) { Write-Output "FAIL  $m"; $script:fail = 1 }
function Ok([string]$m) { Write-Output "OK    $m" }
function Info([string]$m) { Write-Output "      $m" }

if (-not (Test-Path $Apk)) { Write-Output "FAIL  no such APK"; exit 1 }
$item = Get-Item $Apk

Info "file         $($item.Name)"
Info "bytes        $($item.Length)  ($([math]::Round($item.Length / 1MB, 2)) MiB)"
Info "sha256       $((Get-FileHash $Apk -Algorithm SHA256).Hash.ToLower())"
Info "modified     $($item.LastWriteTime.ToString('s'))"
if ($ExpectedSourceSha) { Info "source sha   $ExpectedSourceSha" }

# ---- Android build tools ---------------------------------------------------
$sdk = $env:ANDROID_HOME
if ([string]::IsNullOrWhiteSpace($sdk)) { $sdk = $env:ANDROID_SDK_ROOT }
if ([string]::IsNullOrWhiteSpace($sdk)) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
$bt = Get-ChildItem "$sdk\build-tools" -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $bt) { Write-Output 'FAIL  Android build-tools not found'; exit 1 }
$jbr = 'C:\Program Files\Android\Android Studio\jbr'
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME) -and (Test-Path "$jbr\bin\java.exe")) {
    $env:JAVA_HOME = $jbr; $env:PATH = "$jbr\bin;$env:PATH"
}

# ---- identity + posture (aapt badging) ------------------------------------
$badging = & "$($bt.FullName)\aapt.exe" dump badging $Apk 2>&1
$pkgLine = ($badging | Select-String -Pattern "^package:" | Select-Object -First 1).Line
if ($pkgLine -match "name='([^']+)'") {
    if ($Matches[1] -eq $ExpectedPackage) { Ok "package id   $($Matches[1])" }
    else { Fail "package id is $($Matches[1]), expected $ExpectedPackage" }
}
else { Fail 'package id could not be read' }
if ($pkgLine -match "versionName='([^']+)'") {
    if ($Matches[1] -eq $ExpectedVersionName) { Ok "versionName  $($Matches[1])" }
    else { Fail "versionName is $($Matches[1]), expected $ExpectedVersionName" }
}
if ($pkgLine -match "versionCode='([^']+)'") {
    if ([int]$Matches[1] -eq $ExpectedVersionCode) { Ok "versionCode  $($Matches[1])" }
    else { Fail "versionCode is $($Matches[1]), expected $ExpectedVersionCode" }
}

if (($badging | Select-String -Pattern 'application-debuggable').Count -gt 0) {
    Fail 'artifact is DEBUGGABLE - never ship this'
}
else { Ok 'not debuggable' }

foreach ($p in @('^sdkVersion:', '^targetSdkVersion:', '^native-code:', "^application-label:'")) {
    $l = ($badging | Select-String -Pattern $p | Select-Object -First 1)
    if ($l) { Info $l.Line.Trim() }
}

# ---- structure + signature ------------------------------------------------
& "$($bt.FullName)\zipalign.exe" -c -v 4 $Apk > $null 2>&1
if ($LASTEXITCODE -eq 0) { Ok 'zipalign verified' } else { Fail 'zipalign verification failed' }

$signer = & "$($bt.FullName)\apksigner.bat" verify --print-certs $Apk 2>&1
if ($LASTEXITCODE -ne 0) { Fail 'apksigner could not verify the signature' }
else { Ok 'apksigner verifies the signature' }

$certLine = ($signer | Select-String -Pattern 'certificate SHA-256 digest:\s*([0-9a-fA-F]{64})' |
    Select-Object -First 1)
if (-not $certLine) { Fail 'certificate fingerprint could not be read' }
else {
    $actual = $certLine.Matches.Groups[1].Value.ToLower()
    # Accept the pinned value with or without colons.
    $expect = ($ExpectedCertSha256 -replace ':', '').ToLower()
    if ($expect -eq 'pending_key_ceremony') {
        Fail 'expected certificate fingerprint is still the placeholder - refuse to bless this artifact'
    }
    elseif ($actual -eq $expect) { Ok "certificate  SHA-256 matches the pinned production identity" }
    else { Fail 'certificate fingerprint does NOT match the pinned production identity' }
}
if ($signer -match 'CN=Android Debug') { Fail 'signed with the ANDROID DEBUG certificate' }
else { Ok 'not signed with the Android debug certificate' }

# ---- in-archive posture (read in memory) ----------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
try {
    $hosted = 0; $forbidden = 0; $localhost = 0; $jwt = 0; $arch = @{}
    foreach ($e in $zip.Entries) {
        if ($e.FullName -match '^lib/([^/]+)/') { $arch[$Matches[1]] = $true }
        if ($e.FullName -notmatch '\.(so|dex)$') { continue }
        $ms = New-Object System.IO.MemoryStream
        $s = $e.Open(); $s.CopyTo($ms); $s.Close()
        $txt = [System.Text.Encoding]::ASCII.GetString($ms.ToArray()); $ms.Dispose()
        if ($txt.Contains('oqmevrndtivqxgyvcmwy')) { $hosted++ }
        if ($txt.Contains('ktuupqsaxttrzajmvgif')) { $forbidden++ }
        if ($txt -match 'localhost:54321|127\.0\.0\.1:54321') { $localhost++ }
        if ($txt -match 'eyJhbGciOi') { $jwt++ }
    }
    if ($hosted -ge 1) { Ok "hosted Supabase reference present ($hosted binaries)" }
    else { Fail 'expected hosted Supabase reference is ABSENT - is this a demo build?' }
    if ($forbidden -eq 0) { Ok 'forbidden Supabase reference absent' } else { Fail 'FORBIDDEN Supabase reference present' }
    if ($localhost -eq 0) { Ok 'no localhost Supabase configuration' } else { Fail 'localhost Supabase configuration present' }
    if ($jwt -eq 0) { Ok 'no JWT-shaped token embedded' } else { Fail 'JWT-shaped token embedded' }

    $aot = [bool]($zip.Entries | Where-Object { $_.FullName -eq 'lib/arm64-v8a/libapp.so' })
    $jit = [bool]($zip.Entries | Where-Object { $_.FullName -match 'kernel_blob\.bin' })
    if ($aot -and -not $jit) { Ok 'AOT release posture (libapp.so present, no kernel_blob)' }
    else { Fail 'not an AOT release build' }
    Info "abi          $(($arch.Keys | Sort-Object) -join ',')"
    Info "entries      $($zip.Entries.Count)"
}
finally { $zip.Dispose() }

Write-Output ''
Write-Output "verify: $(if ($fail) {'FAIL'} else {'PASS'})  $($item.Name)"
exit $fail
