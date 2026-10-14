# BIZBOT-POS-AUDIO-PRINT-003: dependency-free native playback state tests.
# Uses the Kotlin compiler already bundled with the Android Gradle wrapper.
# No Android device, audio playback, APK packaging or new dependency download.
[CmdletBinding()]
param(
    [string]$GradleHome,
    [string]$JavaHome = $env:JAVA_HOME
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$wrapper = Get-Content -LiteralPath (Join-Path $repoRoot 'apps/pos/android/gradle/wrapper/gradle-wrapper.properties') -Raw
if ($wrapper -notmatch 'gradle-([\d.]+)-(all|bin)\.zip') { throw 'Gradle wrapper version not found.' }
$gradleVersion = $Matches[1]
$gradleDistribution = "gradle-$gradleVersion-$($Matches[2])"
if (-not $GradleHome) {
    $gradleCache = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path $env:USERPROFILE '.gradle' }
    $distributionCache = Join-Path $gradleCache "wrapper/dists/$gradleDistribution"
    $candidate = Get-ChildItem -LiteralPath $distributionCache -Directory |
        ForEach-Object { Join-Path $_.FullName "gradle-$gradleVersion" } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ 'lib') } |
        Select-Object -First 1
    if (-not $candidate) { throw 'Run the existing Android Gradle wrapper first, or supply -GradleHome.' }
    $GradleHome = $candidate
}
$kotlinLib = Join-Path $GradleHome 'lib'
$compiler = Get-ChildItem -LiteralPath $kotlinLib -Filter 'kotlin-compiler-embeddable-*.jar' | Select-Object -First 1
$stdlib = Get-ChildItem -LiteralPath $kotlinLib -Filter 'kotlin-stdlib-*.jar' | Select-Object -First 1
$annotations = Get-ChildItem -LiteralPath $kotlinLib -Filter 'annotations-*.jar' | Select-Object -First 1
if (-not $compiler -or -not $stdlib -or -not $annotations) { throw 'Bundled Kotlin compiler/runtime not found.' }
$java = if ($JavaHome) { Join-Path $JavaHome 'bin/java.exe' } else { 'java' }
$separator = [IO.Path]::PathSeparator
$classpath = "$($stdlib.FullName)$separator$($annotations.FullName)"
$asset = Join-Path $repoRoot 'apps/pos/android/app/src/main/res/raw/bizbot_online_order_alert.mp3'
$expectedAssetHash = '47c6a0bee63e297116b98a56cdb9674785b60829cc967c22829485a7399a5d34'
if ((Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedAssetHash) {
    throw 'Bundled notification asset differs from its measured, reviewed master.'
}

$outputJar = Join-Path ([IO.Path]::GetTempPath()) ("restoflow-alert-test-" + [guid]::NewGuid().ToString('N') + '.jar')
try {
    & $java -cp (Join-Path $kotlinLib '*') org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
        -no-stdlib -no-reflect -classpath $classpath -jvm-target 17 -d $outputJar `
        (Join-Path $repoRoot 'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/OnlineOrderAlertPlayback.kt') `
        (Join-Path $repoRoot 'apps/pos/android/test/OnlineOrderAlertPlaybackTest.kt')
    if ($LASTEXITCODE -ne 0) { throw 'Native audio test compilation failed.' }
    & $java -cp "$outputJar$separator$classpath" com.restoflow.pos.OnlineOrderAlertPlaybackTestKt
    if ($LASTEXITCODE -ne 0) { throw 'Native audio playback tests failed.' }
    Write-Output 'Bundled asset SHA-256 verified.'
} finally {
    if (Test-Path -LiteralPath $outputJar) { Remove-Item -LiteralPath $outputJar }
}
