# BIZBOT-POS-BACKGROUND-ORDER-ALERT-001: dependency-free synthetic native state tests.
[CmdletBinding()]
param([string]$GradleHome, [string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $GradleHome) {
    $cache = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
    $distribution = Join-Path $cache 'wrapper/dists/gradle-9.1.0-all'
    $GradleHome = Get-ChildItem -LiteralPath $distribution -Directory |
        ForEach-Object { Join-Path $_.FullName 'gradle-9.1.0' } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ 'lib') } | Select-Object -First 1
}
if (-not $GradleHome) { throw 'Existing Gradle compiler is unavailable.' }
$lib = Join-Path $GradleHome 'lib'
$stdlib = Get-ChildItem -LiteralPath $lib -Filter 'kotlin-stdlib-*.jar' | Select-Object -First 1
$annotations = Get-ChildItem -LiteralPath $lib -Filter 'annotations-*.jar' | Select-Object -First 1
$java = if ($JavaHome) { Join-Path $JavaHome 'bin/java.exe' } else { 'java' }
$classpath = "$($stdlib.FullName)$([IO.Path]::PathSeparator)$($annotations.FullName)"
$jar = Join-Path ([IO.Path]::GetTempPath()) ('bizbot-background-alert-state-' + [guid]::NewGuid().ToString('N') + '.jar')
try {
    & $java -cp (Join-Path $lib '*') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect `
        -classpath $classpath -jvm-target 17 -d $jar `
        (Join-Path $repoRoot 'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/BackgroundOrderAlertState.kt') `
        (Join-Path $repoRoot 'apps/pos/android/test/BackgroundOrderAlertStateTest.kt')
    if ($LASTEXITCODE -ne 0) { throw 'Background alert state compilation failed.' }
    & $java -cp "$jar$([IO.Path]::PathSeparator)$classpath" com.restoflow.pos.BackgroundOrderAlertStateTestKt
    if ($LASTEXITCODE -ne 0) { throw 'Background alert state test failed.' }
    $asset = Join-Path $repoRoot 'apps/pos/android/app/src/main/res/raw/bizbot_online_order_alert.mp3'
    if ((Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant() -ne '47c6a0bee63e297116b98a56cdb9674785b60829cc967c22829485a7399a5d34') {
        throw 'Reviewed bundled notification asset changed.'
    }
    Write-Output 'Bundled notification asset SHA-256 verified.'
} finally {
    if (Test-Path -LiteralPath $jar) { Remove-Item -LiteralPath $jar }
}
