# ============================================================================
# RELEASE-KEY-AND-PIPELINE-001 - production signing identity check.
#
# Answers three questions WITHOUT building anything and WITHOUT revealing any
# secret:
#   1. Do POS and KDS carry the same fail-closed signing block? (drift guard)
#   2. Does the configured production key open, and what is its PUBLIC identity?
#   3. Is that identity the real production certificate rather than the Android
#      debug key?
#
# It prints alias, certificate SHA-256 fingerprint, algorithm, key size and
# validity - all public. It never prints a password, a keystore path, or the
# contents of the signing-properties file.
#
# Usage:  pwsh tools/android_release/check_signing_identity.ps1 [-RequireKey]
#   -RequireKey  fail (rather than warn) when the key is not configured yet.
# ============================================================================
[CmdletBinding()]
param([switch]$RequireKey)

$ErrorActionPreference = 'Stop'
$repo = (& git rev-parse --show-toplevel).Trim()
$fail = 0

function Fail([string]$m) { Write-Output "FAIL  $m"; $script:fail = 1 }
function Ok([string]$m) { Write-Output "OK    $m" }
function Info([string]$m) { Write-Output "      $m" }

# BIZBOT-ANDROID-SIGNING-DRIFT-GUARD-001: exact reviewed differences only.
# Never strip arbitrary Kotlin blocks or derive an accepted pin from the inputs.
function Assert-ExactCount([string]$Text, [string]$Literal, [int]$Expected, [string]$Label) {
    $count = 0; $offset = 0
    while (($offset = $Text.IndexOf($Literal, $offset, [StringComparison]::Ordinal)) -ge 0) {
        $count++; $offset += $Literal.Length
    }
    if ($count -ne $Expected) { throw "unexpected Gradle occurrence count: $Label" }
}

function Remove-ReviewedPosFragment([string]$Text, [string]$Before, [string]$Fragment, [string]$After, [string]$Label) {
    $Before = $Before.Replace("`r`n", "`n")
    $Fragment = $Fragment.Replace("`r`n", "`n")
    $After = $After.Replace("`r`n", "`n")
    Assert-ExactCount $Text $Fragment 1 $Label
    $window = $Before + $Fragment + $After
    Assert-ExactCount $Text $window 1 "$Label context"
    if ($After.Length -eq 0 -and -not $Text.EndsWith($window, [StringComparison]::Ordinal)) {
        throw "unexpected Gradle placement: $Label"
    }
    return $Text.Replace($window, ($Before + $After))
}

function Get-ReviewedCommonGradle([string]$Text, [string]$App) {
    # Line endings are the only whitespace normalization. Preserve all other
    # characters, comments and the final newline in the strict comparison.
    $text = $Text.Replace("`r`n", "`n")
    if ($App -ceq 'pos') {
        $text = Remove-ReviewedPosFragment $text "import java.util.Properties`n" `
            "import java.util.Base64`n" "`nplugins {" 'POS Base64 import'
        $options = @'
// Public Android client configuration only. This opt-in is OFF for every existing release invocation.
val bizbotBackgroundAlerts = providers.gradleProperty("BIZBOT_BACKGROUND_ORDER_ALERTS").orNull == "true"
fun bizbotPublicOption(name: String): String = providers.gradleProperty(name).orNull ?: ""
fun bizbotQuoted(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
// Use the SAME backend define as Flutter; a method-channel caller cannot choose an arbitrary host.
val bizbotDartDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(',').mapNotNull {
    try { String(Base64.getDecoder().decode(it), Charsets.UTF_8).split('=', limit = 2).takeIf { pair -> pair.size == 2 } }
    catch (_: Exception) { null }
}.associate { it[0] to it[1] }
'@
        $text = Remove-ReviewedPosFragment $text "    id(`"dev.flutter.flutter-gradle-plugin`")`n}`n`n" `
            ($options + "`n`n") "// ---------------------------------------------------------------------------`n// RELEASE-KEY-AND-PIPELINE-001" 'POS Firebase options'
        $text = Remove-ReviewedPosFragment $text "    ndkVersion = flutter.ndkVersion`n" `
            "    buildFeatures { buildConfig = true }`n" "`n    compileOptions {" 'POS BuildConfig feature'
        $fields = @'
        manifestPlaceholders["bizbotBackgroundAlertsEnabled"] = bizbotBackgroundAlerts.toString()
        buildConfigField("boolean", "BIZBOT_BACKGROUND_ORDER_ALERTS", bizbotBackgroundAlerts.toString())
        buildConfigField("String", "BIZBOT_SUPABASE_URL", bizbotQuoted(bizbotDartDefines["RESTOFLOW_SUPABASE_URL"].orEmpty()))
        for (name in listOf("BIZBOT_FIREBASE_APP_ID", "BIZBOT_FIREBASE_API_KEY", "BIZBOT_FIREBASE_PROJECT_ID", "BIZBOT_FIREBASE_SENDER_ID")) {
            buildConfigField("String", name, bizbotQuoted(bizbotPublicOption(name)))
        }
'@
        $text = Remove-ReviewedPosFragment $text "        versionName = flutter.versionName`n" `
            ($fields + "`n") "    }`n`n    signingConfigs {" 'POS Firebase fields'
        $dependency = @'
dependencies {
    // Native data-message receiver; no Flutter background isolate or Google Services plugin.
    implementation("com.google.firebase:firebase-messaging:25.1.3")
}
'@
        $text = Remove-ReviewedPosFragment $text "flutter {`n    source = `"../..`"`n}`n" `
            ("`n" + $dependency + "`n") '' 'POS Firebase dependency'
    }
    elseif ($App -cne 'kds') { throw 'unexpected Gradle application identity' }

    $otherApp = if ($App -ceq 'pos') { 'kds' } else { 'pos' }
    foreach ($rule in @(
            @{ Literal = "com.restoflow.$App"; Occurrences = 2; Common = 'APPID' },
            @{ Literal = "RestoFlow $($App.ToUpperInvariant())"; Occurrences = 1; Common = 'APPNAME' },
            @{ Literal = "apps/$otherApp"; Occurrences = 1; Common = 'OTHERAPP' })) {
        Assert-ExactCount $text $rule.Literal $rule.Occurrences 'application identity'
        $text = $text.Replace($rule.Literal, $rule.Common)
    }
    return $text
}

# ---- 1. POS / KDS signing blocks must not drift ---------------------------
$pos = Join-Path $repo 'apps/pos/android/app/build.gradle.kts'
$kds = Join-Path $repo 'apps/kds/android/app/build.gradle.kts'
foreach ($f in @($pos, $kds)) {
    if (-not (Test-Path $f)) { Fail "missing $f"; }
}
if ($fail -eq 0) {
    try {
        $a = Get-ReviewedCommonGradle (Get-Content $pos -Raw) 'pos'
        $b = Get-ReviewedCommonGradle (Get-Content $kds -Raw) 'kds'
        if (-not [string]::Equals($a, $b, [StringComparison]::Ordinal)) { throw 'unreviewed POS/KDS Gradle difference' }
        # Reviewed common Gradle from approved main 8cf2d425. Pair equality alone
        # cannot catch an unsafe change made identically to BOTH apps. Every
        # future shared Gradle edit requires an explicitly reviewed pin update.
        $pin = '4480a3bb20acd72de2fcb31655b1228f09f6d4c72aabfdd93b0d9bb8f3ec7db1'
        $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($b))).ToLowerInvariant()
        if (-not [string]::Equals($digest, $pin, [StringComparison]::Ordinal)) { throw 'reviewed common Gradle content changed' }
        Ok 'POS and KDS Gradle match reviewed signing and application differences'
    }
    catch { Fail 'POS/KDS Gradle content, counts or placement differ from the reviewed configuration' }

    # The debug-fallback must never come back. Comments are stripped first: the
    # file deliberately NAMES the forbidden call in prose to explain why it is
    # gone, and matching that would be a permanent false positive.
    foreach ($f in @($pos, $kds)) {
        $label = Split-Path (Split-Path (Split-Path $f -Parent) -Parent) -Leaf
        $code = (Get-Content $f | Where-Object { $_.TrimStart() -notmatch '^(//|\*|/\*)' }) -join "`n"
        if ($code -match 'signingConfigs\.getByName\(\s*"debug"\s*\)') {
            Fail "${label}: release falls back to DEBUG signing"
        }
        if ($code -notmatch 'signingConfigs\.findByName\(\s*"release"\s*\)') {
            Fail "${label}: release signing config is not wired"
        }
    }
    if ($fail -eq 0) { Ok 'neither app can fall back to debug signing for a release' }
}

if ($fail -ne 0) { Write-Output ''; Write-Output 'signing-identity check: FAIL'; exit 1 }

# ---- 2. The configured key (optional until the ceremony has run) -----------
$propsPath = $env:RESTOFLOW_ANDROID_SIGNING_PROPERTIES
if ([string]::IsNullOrWhiteSpace($propsPath) -or -not (Test-Path $propsPath)) {
    $msg = 'production signing is NOT configured on this machine (key ceremony not done, or env var unset)'
    if ($RequireKey) { Fail $msg } else { Write-Output "WARN  $msg" }
    Write-Output ''
    Write-Output "signing-identity check: $(if ($fail) {'FAIL'} else {'OK (config only)'})"
    exit $fail
}

# Read the properties WITHOUT echoing them.
$props = @{}
foreach ($line in Get-Content $propsPath) {
    if ($line -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$Matches[1]] = $Matches[2] }
}
foreach ($k in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
    if (-not $props.ContainsKey($k) -or [string]::IsNullOrWhiteSpace($props[$k])) {
        Fail "signing properties are incomplete (missing $k)"
    }
}
if ($fail -ne 0) { Write-Output ''; Write-Output 'signing-identity check: FAIL'; exit 1 }
if (-not (Test-Path $props['storeFile'])) { Fail 'keystore file is missing'; Write-Output ''; exit 1 }

# The keystore must live OUTSIDE the repository.
$storeFull = (Resolve-Path $props['storeFile']).Path
if ($storeFull.StartsWith($repo.Replace('/', '\'), [StringComparison]::OrdinalIgnoreCase)) {
    Fail 'keystore is INSIDE the repository - move it out immediately'
}
else { Ok 'keystore is stored outside the repository' }

# The password goes to keytool through a PRIVATE ENV VAR (`-storepass:env`), so
# it never appears in the command line, a process listing, or shell history, and
# no password-bearing temp file is written. The variable is removed immediately.
#
# Piping the password to keytool's stdin prompt was tried first and is wrong on
# Windows PowerShell 5.1: keytool writes "Enter keystore password:" to STDERR,
# which 5.1 wraps in a NativeCommandError, and with $ErrorActionPreference='Stop'
# that aborts the script before it can read a single certificate field.
# $ErrorActionPreference is relaxed around the native call for the same reason.
$jbr = 'C:\Program Files\Android\Android Studio\jbr'
if ([string]::IsNullOrWhiteSpace($env:JAVA_HOME) -and (Test-Path "$jbr\bin\keytool.exe")) {
    $env:JAVA_HOME = $jbr; $env:PATH = "$jbr\bin;$env:PATH"
}
$keytoolExit = 1
$env:RESTOFLOW_KS_PW = $props['storePassword']
try {
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $listing = & keytool -list -v `
        -keystore $props['storeFile'] -alias $props['keyAlias'] `
        -storepass:env RESTOFLOW_KS_PW 2>&1
    $keytoolExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
}
finally { Remove-Item Env:\RESTOFLOW_KS_PW -ErrorAction SilentlyContinue }
if ($keytoolExit -ne 0) { Fail 'keystore could not be opened with the supplied credentials' }
else {
    $fp = ($listing | Select-String -Pattern 'SHA256:\s*([0-9A-F:]{95})' |
        Select-Object -First 1).Matches.Groups[1].Value
    $alg = ($listing | Select-String -Pattern 'Signature algorithm name:\s*(.+)' |
        Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $size = ($listing | Select-String -Pattern 'Subject Public Key Algorithm:\s*(.+)' |
        Select-Object -First 1).Matches.Groups[1].Value.Trim()
    $valid = ($listing | Select-String -Pattern 'Valid from:\s*(.+)' |
        Select-Object -First 1).Matches.Groups[1].Value.Trim()

    Ok "alias        $($props['keyAlias'])"
    Info "fingerprint  SHA-256 $fp"
    Info "algorithm    $alg"
    Info "public key   $size"
    Info "validity     $valid"

    # Never the Android debug identity.
    if ($listing -match 'CN=Android Debug') { Fail 'this is the ANDROID DEBUG certificate, not a production key' }
    else { Ok 'certificate is NOT the Android debug certificate' }

    # Must match the pinned public fingerprint once the ledger is filled in.
    $ledger = Get-Content (Join-Path $repo 'tools/android_release/version.json') -Raw | ConvertFrom-Json
    if ($ledger.expectedCertificateSha256 -eq 'PENDING_KEY_CEREMONY') {
        Write-Output "WARN  version.json still has the placeholder fingerprint - record SHA-256 above after the ceremony"
    }
    elseif ($ledger.expectedCertificateSha256 -ne $fp) {
        Fail 'certificate fingerprint does NOT match the pinned value in version.json'
    }
    else { Ok 'certificate fingerprint matches the pinned value in version.json' }
}

Write-Output ''
Write-Output "signing-identity check: $(if ($fail) {'FAIL'} else {'OK'})"
exit $fail
