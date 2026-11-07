# BIZBOT-POS-BACKGROUND-ORDER-ALERT-001: dependency-free synthetic native state tests.
[CmdletBinding()]
param([string]$GradleHome, [string]$JavaHome = $env:JAVA_HOME, [string]$AndroidJsonSources)
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
$java = if ($JavaHome) { Join-Path $JavaHome $(if ($IsWindows) { 'bin/java.exe' } else { 'bin/java' }) } else { 'java' }
$classpath = "$($stdlib.FullName)$([IO.Path]::PathSeparator)$($annotations.FullName)"
# Native wildcard arguments expand on Unix. Pass only an explicit, single
# classpath argument so Gradle's lib/plugins directory cannot become main class.
$compilerClasspath = (Get-ChildItem -LiteralPath $lib -Filter '*.jar' -File |
    ForEach-Object { $_.FullName }) -join [IO.Path]::PathSeparator
$jar = Join-Path ([IO.Path]::GetTempPath()) ('bizbot-background-alert-state-' + [guid]::NewGuid().ToString('N') + '.jar')
$scratch = $null
try {
    $extraSources = @()
    if ($AndroidJsonSources) {
        # Compile the Android SDK's actual org.json implementation. Only its
        # platform-internal, non-behavioural annotation declarations need stubs
        # when running these Android sources under the host JVM.
        $scratch = [IO.Directory]::CreateTempSubdirectory('bizbot-alert-json-').FullName
        $classes = [IO.Directory]::CreateDirectory((Join-Path $scratch 'classes')).FullName
        $annotationSources = @{
            SystemApi = 'package android.annotation; public @interface SystemApi { Client client(); enum Client { MODULE_LIBRARIES } }'
            UnsupportedAppUsage = 'package android.compat.annotation; public @interface UnsupportedAppUsage {}'
            NonNull = 'package libcore.util; @java.lang.annotation.Target(java.lang.annotation.ElementType.TYPE_USE) public @interface NonNull {}'
            Nullable = 'package libcore.util; @java.lang.annotation.Target(java.lang.annotation.ElementType.TYPE_USE) public @interface Nullable {}'
        }
        $javaSources = foreach ($name in $annotationSources.Keys) {
            $src = Join-Path $scratch ($name + '.java')
            [IO.File]::WriteAllText($src, $annotationSources[$name])
            $src
        }
        $javaSources += (Get-ChildItem -LiteralPath $AndroidJsonSources -Filter '*.java' -File).FullName
        $javac = if ($JavaHome) { Join-Path $JavaHome $(if ($IsWindows) { 'bin/javac.exe' } else { 'bin/javac' }) } else { 'javac' }
        & $javac -d $classes @javaSources
        if ($LASTEXITCODE -ne 0) { throw 'Android SDK org.json compilation failed.' }
        $classpath += "$([IO.Path]::PathSeparator)$classes"
        $extraSources += Join-Path $repoRoot 'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/BackgroundOrderAlertDutyJournal.kt'
        $extraSources += Join-Path $repoRoot 'apps/pos/android/test/BackgroundOrderAlertDutyJournalTest.kt'
    }
    & $java -cp $compilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler -no-stdlib -no-reflect `
        -classpath $classpath -jvm-target 17 -d $jar `
        (Join-Path $repoRoot 'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/BackgroundOrderAlertState.kt') `
        (Join-Path $repoRoot 'apps/pos/android/app/src/main/kotlin/com/restoflow/pos/BackgroundOrderAlertDuty.kt') `
        (Join-Path $repoRoot 'apps/pos/android/test/BackgroundOrderAlertStateTest.kt') @extraSources
    if ($LASTEXITCODE -ne 0) { throw 'Background alert state compilation failed.' }
    & $java -cp "$jar$([IO.Path]::PathSeparator)$classpath" com.restoflow.pos.BackgroundOrderAlertStateTestKt
    if ($LASTEXITCODE -ne 0) { throw 'Background alert state test failed.' }
    if ($AndroidJsonSources) {
        # Preserved public response fields from an isolated synthetic SQL/Edge run.
        $wire = Join-Path $repoRoot 'apps/pos/android/test/fixtures/shift-duty-wire.json'
        & $java -cp "$jar$([IO.Path]::PathSeparator)$classpath" com.restoflow.pos.BackgroundOrderAlertDutyJournalTestKt $wire
        if ($LASTEXITCODE -ne 0) { throw 'Duty journal wire replay failed.' }
    }
    $asset = Join-Path $repoRoot 'apps/pos/android/app/src/main/res/raw/bizbot_online_order_alert.mp3'
    if ((Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant() -ne '47c6a0bee63e297116b98a56cdb9674785b60829cc967c22829485a7399a5d34') {
        throw 'Reviewed bundled notification asset changed.'
    }
    Write-Output 'Bundled notification asset SHA-256 verified.'
} finally {
    if (Test-Path -LiteralPath $jar) { Remove-Item -LiteralPath $jar }
    if ($scratch -and ([IO.Path]::GetDirectoryName($scratch) -eq [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetTempPath())) -and
        ([IO.Path]::GetFileName($scratch) -like 'bizbot-alert-json-*')) {
        Remove-Item -LiteralPath $scratch -Recurse -Force
    }
}
