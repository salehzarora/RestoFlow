# BIZBOT-ANDROID-SIGNING-DRIFT-GUARD-001. Synthetic Gradle/keytool fixtures only.
# No APK builds, real signing material, backend calls, or release-ledger changes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$checker = Join-Path $PSScriptRoot 'check_signing_identity.ps1'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$originalPos = [IO.File]::ReadAllText((Join-Path $sourceRoot 'apps/pos/android/app/build.gradle.kts')).Replace("`r`n", "`n")
$originalKds = [IO.File]::ReadAllText((Join-Path $sourceRoot 'apps/kds/android/app/build.gradle.kts')).Replace("`r`n", "`n")
$fingerprint = '4E:E0:03:49:AD:BD:65:24:49:6A:04:96:0B:AE:63:33:36:EE:BC:87:CB:6B:82:DF:7D:07:5C:F8:C4:7E:FA:E7'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('bizbot-signing-test-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $tmp 'synthetic-repo'
$posPath = Join-Path $repo 'apps/pos/android/app/build.gradle.kts'
$kdsPath = Join-Path $repo 'apps/kds/android/app/build.gradle.kts'
$wrapper = Join-Path $tmp 'invoke-checker.ps1'
$passed = 0

function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL $Name" }
    $script:passed++
    Write-Output "PASS $Name"
}

function Invoke-Case {
    param(
        [string]$Name,
        [string]$Pos = $script:originalPos,
        [string]$Kds = $script:originalKds,
        [bool]$Pass = $false,
        [string]$Expected = '',
        [string]$KeyMode = 'none',
        [switch]$RequireKey
    )
    if (-not $Pass -and $KeyMode -eq 'none' -and -not $RequireKey -and -not $Expected) {
        $Expected = 'POS/KDS Gradle content, counts or placement differ from the reviewed configuration'
    }
    [IO.File]::WriteAllText($script:posPath, $Pos)
    [IO.File]::WriteAllText($script:kdsPath, $Kds)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($arg in @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script:wrapper,
            '-Checker', $script:checker, '-Root', $script:repo, '-KeyMode', $KeyMode)) {
        $start.ArgumentList.Add($arg)
    }
    if ($RequireKey) { $start.ArgumentList.Add('-RequireKey') }
    # Clear inherited production signing paths/passwords only in the child.
    foreach ($credentialEnvName in @('RESTOFLOW_ANDROID_SIGNING_PROPERTIES', 'RESTOFLOW_KS_PW')) { [void]$start.Environment.Remove($credentialEnvName) }
    $process = [Diagnostics.Process]::Start($start)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $output = $outTask.GetAwaiter().GetResult() + $errTask.GetAwaiter().GetResult()
    $exitCode = $process.ExitCode
    $process.Dispose()
    if (($exitCode -eq 0) -ne $Pass -or ($Expected -and -not $output.Contains($Expected))) {
        throw "FAIL $Name (exit=$exitCode): $output"
    }
    Check (-not $output.Contains('synthetic-store-password') -and -not $output.Contains('synthetic-key-password')) "$Name; no password disclosure"
}

function Replace-Required([string]$Text, [string]$Before, [string]$After) {
    if (-not $Text.Contains($Before)) { throw 'Synthetic mutation no longer matches the reviewed source' }
    return $Text.Replace($Before, $After)
}

try {
    foreach ($dir in @((Split-Path $posPath -Parent), (Split-Path $kdsPath -Parent), (Join-Path $repo 'tools/android_release'))) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    [IO.File]::WriteAllText((Join-Path $repo 'tools/android_release/version.json'), (@{ expectedCertificateSha256 = $fingerprint } | ConvertTo-Json))
    # The child resolves git and keytool to these functions. No native keytool or
    # real configured key can be reached, including on production build machines.
    [IO.File]::WriteAllText($wrapper, @'
param([string]$Checker, [string]$Root, [string]$KeyMode, [switch]$RequireKey)
$ErrorActionPreference = 'Stop'
$global:SigningTestRoot = $Root
$global:SigningTestKeyMode = $KeyMode
function global:git { $global:LASTEXITCODE = 0; Write-Output $global:SigningTestRoot }
function global:keytool {
    $global:LASTEXITCODE = if ($global:SigningTestKeyMode -eq 'unavailable') { 1 } else { 0 }
    if ($global:SigningTestKeyMode -eq 'unavailable') { return }
    $fp = '4E:E0:03:49:AD:BD:65:24:49:6A:04:96:0B:AE:63:33:36:EE:BC:87:CB:6B:82:DF:7D:07:5C:F8:C4:7E:FA:E7'
    if ($global:SigningTestKeyMode -eq 'wrong-certificate') { $fp = ('00:' * 31) + '00' }
    if ($global:SigningTestKeyMode -eq 'debug-certificate') { Write-Output 'Owner: CN=Android Debug' }
    else { Write-Output 'Owner: CN=Synthetic Signing Test' }
    if ($global:SigningTestKeyMode -ne 'missing-fingerprint') { Write-Output "SHA256: $fp" }
    Write-Output 'Signature algorithm name: SHA256withRSA'
    Write-Output 'Subject Public Key Algorithm: 4096-bit RSA key'
    Write-Output 'Valid from: synthetic-test-only'
}
if ($KeyMode -ne 'none') {
    $propsPath = Join-Path (Split-Path $Root -Parent) 'synthetic.properties'
    $store = Join-Path (Split-Path $Root -Parent) 'synthetic.store'
    if ($KeyMode -ne 'missing-store') { [IO.File]::WriteAllText($store, 'NOT A KEYSTORE; fake keytool only') }
    elseif (Test-Path -LiteralPath $store) { Remove-Item -LiteralPath $store }
    $lines = @("storeFile=$store", 'storePassword=synthetic-store-password', 'keyAlias=synthetic-alias', 'keyPassword=synthetic-key-password')
    if ($KeyMode.StartsWith('missing-property:')) {
        $missing = $KeyMode.Substring('missing-property:'.Length)
        $lines = @($lines | Where-Object { -not $_.StartsWith("$missing=") })
    }
    [IO.File]::WriteAllText($propsPath, ($lines -join "`n"))
    $env:RESTOFLOW_ANDROID_SIGNING_PROPERTIES = $propsPath
}
if ($RequireKey) { & $Checker -RequireKey } else { & $Checker }
exit $LASTEXITCODE
'@)

    Invoke-Case -Name 'current POS/KDS LF configuration passes' -Pass $true -Expected 'OK (config only)'
    Invoke-Case -Name 'current CRLF configuration passes' -Pos $originalPos.Replace("`n", "`r`n") -Kds $originalKds.Replace("`n", "`r`n") -Pass $true
    Invoke-Case -Name 'mixed POS/KDS line endings pass' -Pos $originalPos.Replace("`n", "`r`n") -Pass $true
    Invoke-Case -Name 'RequireKey rejects unconfigured signing' -RequireKey -Expected 'production signing is NOT configured'
    Invoke-Case -Name 'ordinal comparison rejects POS-only soft-hyphen signing drift' -Pos (
        Replace-Required $originalPos 'signingConfig = signingConfigs.findByName("release")' (
            'signing' + [char]0x00AD + 'Config = signingConfigs.findByName("release")'))

    $allowances = @(
        @{ Name = 'Base64 import'; Block = "import java.util.Base64`n" },
        @{ Name = 'public Firebase helpers'; Block = @'
// Public Android client configuration only. This opt-in is OFF for every existing release invocation.
val bizbotBackgroundAlerts = providers.gradleProperty("BIZBOT_BACKGROUND_ORDER_ALERTS").orNull == "true"
fun bizbotPublicOption(name: String): String = providers.gradleProperty(name).orNull ?: ""
fun bizbotQuoted(value: String): String = "\"" + value.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
// Use the SAME backend define as Flutter; a method-channel caller cannot choose an arbitrary host.
val bizbotDartDefines = (project.findProperty("dart-defines") as? String).orEmpty().split(',').mapNotNull {
    try { String(Base64.getDecoder().decode(it), Charsets.UTF_8).split('=', limit = 2).takeIf { pair -> pair.size == 2 } }
    catch (_: Exception) { null }
}.associate { it[0] to it[1] }

'@ },
        @{ Name = 'BuildConfig feature'; Block = "    buildFeatures { buildConfig = true }`n" },
        @{ Name = 'native Firebase fields'; Block = @'
        manifestPlaceholders["bizbotBackgroundAlertsEnabled"] = bizbotBackgroundAlerts.toString()
        buildConfigField("boolean", "BIZBOT_BACKGROUND_ORDER_ALERTS", bizbotBackgroundAlerts.toString())
        buildConfigField("String", "BIZBOT_SUPABASE_URL", bizbotQuoted(bizbotDartDefines["RESTOFLOW_SUPABASE_URL"].orEmpty()))
        for (name in listOf("BIZBOT_FIREBASE_APP_ID", "BIZBOT_FIREBASE_API_KEY", "BIZBOT_FIREBASE_PROJECT_ID", "BIZBOT_FIREBASE_SENDER_ID")) {
            buildConfigField("String", name, bizbotQuoted(bizbotPublicOption(name)))
        }
'@ },
        @{ Name = 'Firebase dependency'; Block = @'
dependencies {
    // Native data-message receiver; no Flutter background isolate or Google Services plugin.
    implementation("com.google.firebase:firebase-messaging:25.1.3")
}
'@ }
    )
    foreach ($allowance in $allowances) {
        # PowerShell here-strings omit their closing newline; include it exactly.
        $block = $allowance.Block
        if (-not $block.EndsWith("`n")) { $block += "`n" }
        if (-not $originalPos.Contains($block)) { throw "Fixture mismatch: $($allowance.Name)" }
        Invoke-Case -Name "$($allowance.Name) deletion fails" -Pos ($originalPos.Replace($block, ''))
        Invoke-Case -Name "$($allowance.Name) duplication fails" -Pos ($originalPos.Replace($block, $block + $block))
        Invoke-Case -Name "$($allowance.Name) relocation fails" -Pos ($block + $originalPos.Replace($block, ''))
        Invoke-Case -Name "$($allowance.Name) mutation fails" -Pos ($originalPos.Replace($block, $block.Replace(' ', '  ')))
        Invoke-Case -Name "$($allowance.Name) injected statement fails" -Pos ($originalPos.Replace($block, $block + 'println("unreviewed input")' + "`n"))
        Invoke-Case -Name "$($allowance.Name) cannot leak into KDS" -Kds ($originalKds + $block)
    }

    foreach ($identity in @(
            @{ Name = 'package identity'; Before = 'com.restoflow.pos'; After = 'com.restoflow.POS' },
            @{ Name = 'app label'; Before = 'RestoFlow POS'; After = 'RestoFlow pos' },
            @{ Name = 'opposite-app path'; Before = 'apps/kds'; After = 'apps/KDS' })) {
        Invoke-Case -Name "$($identity.Name) case change fails" -Pos (Replace-Required $originalPos $identity.Before $identity.After)
        Invoke-Case -Name "$($identity.Name) duplicate fails" -Pos ($originalPos + "`n// $($identity.Before)`n")
    }
    Invoke-Case -Name 'Firebase property case change fails' -Pos (Replace-Required $originalPos 'BIZBOT_BACKGROUND_ORDER_ALERTS' 'bizbot_background_order_alerts')
    Invoke-Case -Name 'unknown POS content fails' -Pos ($originalPos + "`n// unreviewed POS input`n")
    Invoke-Case -Name 'unknown KDS content fails' -Kds ($originalKds + "`n// unreviewed KDS input`n")
    Invoke-Case -Name 'identical unknown content in both apps fails' -Pos ($originalPos + "`n// unreviewed common input`n") -Kds ($originalKds + "`n// unreviewed common input`n")

    # The pin must reject security regressions even when both copied blocks are
    # changed identically, where a pairwise equality-only guard would pass.
    $securityMutations = @(
        @{ Name = 'release signing wiring'; Before = 'signingConfig = signingConfigs.findByName("release")'; After = 'signingConfig = null' },
        @{ Name = 'debug signing fallback'; Before = 'signingConfig = signingConfigs.findByName("release")'; After = 'signingConfig = signingConfigs.getByName("debug")' },
        @{ Name = 'signing material environment'; Before = 'System.getenv("RESTOFLOW_ANDROID_SIGNING_PROPERTIES")'; After = 'System.getenv("UNREVIEWED_SIGNING_PROPERTIES")' },
        @{ Name = 'required signing properties'; Before = 'listOf("storeFile", "storePassword", "keyAlias", "keyPassword")'; After = 'listOf("storeFile", "storePassword", "keyAlias")' },
        @{ Name = 'keystore availability guard'; Before = 'if (!store.isFile) return "keystore file is missing"'; After = '// removed keystore file guard' },
        @{ Name = 'private-key unlock'; Before = 'keyStore.getKey(alias, props.getProperty("keyPassword").toCharArray())'; After = 'keyStore.containsAlias(alias)' },
        @{ Name = 'alias availability guard'; Before = 'if (!keyStore.containsAlias(alias))'; After = 'if (false)' },
        @{ Name = 'release guard condition'; Before = 'if (restoflowSigningProblem() == null)'; After = 'if (true)' },
        @{ Name = 'release task failure'; Before = 'if (problem != null)'; After = 'if (false)' },
        @{ Name = 'preReleaseBuild hook'; Before = 'it.name == "preReleaseBuild" ||'; After = 'false ||' },
        @{ Name = 'packageRelease hook'; Before = 'it.name == "packageRelease" ||'; After = 'false ||' },
        @{ Name = 'assembleRelease hook'; Before = 'it.name == "assembleRelease" ||'; After = 'false ||' },
        @{ Name = 'bundleRelease hook'; Before = 'it.name == "bundleRelease"'; After = 'false' },
        @{ Name = 'release guard dependency'; Before = '.configureEach { dependsOn(restoflowValidateReleaseSigning) }'; After = '.configureEach { }' },
        @{ Name = 'unrelated compile configuration'; Before = 'sourceCompatibility = JavaVersion.VERSION_17'; After = 'sourceCompatibility = JavaVersion.VERSION_11' }
    )
    foreach ($mutation in $securityMutations) {
        $posMutation = Replace-Required $originalPos $mutation.Before $mutation.After
        $kdsMutation = Replace-Required $originalKds $mutation.Before $mutation.After
        Invoke-Case -Name "$($mutation.Name) POS-only change fails" -Pos $posMutation
        Invoke-Case -Name "$($mutation.Name) identical two-app change fails" -Pos $posMutation -Kds $kdsMutation
    }

    Invoke-Case -Name 'synthetic configured key passes pinned public identity' -Pass $true -KeyMode 'valid' -RequireKey -Expected 'certificate fingerprint matches'
    Invoke-Case -Name 'synthetic keytool failure fails closed' -KeyMode 'unavailable' -RequireKey -Expected 'keystore could not be opened'
    Invoke-Case -Name 'wrong certificate fails pin' -KeyMode 'wrong-certificate' -RequireKey -Expected 'certificate fingerprint does NOT match'
    Invoke-Case -Name 'Android debug certificate fails' -KeyMode 'debug-certificate' -RequireKey -Expected 'ANDROID DEBUG certificate'
    Invoke-Case -Name 'missing keystore fails closed' -KeyMode 'missing-store' -RequireKey -Expected 'keystore file is missing'
    foreach ($property in @('storeFile', 'storePassword', 'keyAlias', 'keyPassword')) {
        Invoke-Case -Name "missing $property fails closed" -KeyMode "missing-property:$property" -RequireKey -Expected "missing $property"
    }
    Write-Output "$passed signing-identity synthetic regression cases passed. No APK or real signing material used."
}
finally {
    $tempRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) + [IO.Path]::DirectorySeparatorChar
    $resolvedTmp = [IO.Path]::GetFullPath($tmp)
    if (-not $resolvedTmp.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolvedTmp)).StartsWith('bizbot-signing-test-')) { throw 'Unsafe temporary cleanup target' }
    if (Test-Path -LiteralPath $resolvedTmp) { Remove-Item -LiteralPath $resolvedTmp -Recurse -Force }
}
