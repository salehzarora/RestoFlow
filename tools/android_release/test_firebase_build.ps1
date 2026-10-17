# BIZBOT-POS-V64-FIREBASE-BUILD-PLUMBING-001. Synthetic inputs and FAKE Flutter only.
# No APK, signing material, Firebase/Supabase request, or release-ledger write.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'firebase_build.ps1')
$passed = 0
function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL $Name" }
    $script:passed++
    Write-Output "PASS $Name"
}
function Reject([scriptblock]$Action, [string]$Name) {
    $rejected = $false
    try { & $Action | Out-Null } catch {
        $rejected = $true
        Check (-not $_.ToString().Contains($script:fixtureKey)) "$Name does not disclose configuration values"
    }
    Check $rejected $Name
}
function global:flutter {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $snapshot = @{}
    foreach ($property in $script:propertyNames) {
        $snapshot[$property] = [Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, 'Process')
    }
    $script:calls += [pscustomobject]@{ Arguments = @($Arguments); Properties = $snapshot }
    if ($script:throwFlutter) { throw 'Synthetic Flutter exception' }
    $global:LASTEXITCODE = $script:flutterExit
}

$propertyNames = @('BIZBOT_BACKGROUND_ORDER_ALERTS', 'BIZBOT_FIREBASE_APP_ID', 'BIZBOT_FIREBASE_API_KEY', 'BIZBOT_FIREBASE_PROJECT_ID', 'BIZBOT_FIREBASE_SENDER_ID')
$managedNames = @('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'JAVA_OPTS', 'GRADLE_OPTS', 'GRADLE_USER_HOME', 'GRADLE_HOME') +
    @($propertyNames | ForEach-Object { 'ORG_GRADLE_PROJECT_' + $_ })
$original = @{}
foreach ($name in $managedNames) { $original[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('bizbot-firebase-test-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $tmp 'repo'
$gradleHome = Join-Path $tmp 'gradle-home'
$configPath = Join-Path $tmp 'public.json'
$fixtureKey = 'AI' + 'za' + ('a' * 35)
$valid = @{
    BIZBOT_FIREBASE_APP_ID = '1:31661231890:android:1856c6d5ac4e64a229adcb'
    BIZBOT_FIREBASE_API_KEY = $fixtureKey
    BIZBOT_FIREBASE_PROJECT_ID = 'bizbot-production'
    BIZBOT_FIREBASE_SENDER_ID = '31661231890'
}
$baseArguments = @('build', 'apk', '--release', '--build-name=0.0.99', '--build-number=99',
    '--dart-define=RESTOFLOW_DEMO_MODE=false', '--dart-define=RESTOFLOW_SUPABASE_URL=https://synthetic.invalid',
    '--dart-define=RESTOFLOW_SUPABASE_ANON_KEY=synthetic-public-client-key')
$calls = @()
$flutterExit = 0
$throwFlutter = $false
try {
    foreach ($dir in @($repo, $gradleHome, (Join-Path $repo 'apps/pos/android'), (Join-Path $repo 'apps/kds/android'))) {
        New-Item -ItemType Directory -Force $dir | Out-Null
    }
    foreach ($name in $managedNames) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process') }
    $env:GRADLE_USER_HOME = $gradleHome
    [IO.File]::WriteAllText($configPath, ($valid | ConvertTo-Json))
    Check ($null -eq (Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo)) 'default OFF requires no configuration'
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -FirebasePublicConfig (Join-Path $tmp 'missing.json') } 'configuration alone cannot opt in'
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts } 'enabled without configuration fails closed'
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig (Join-Path $tmp 'missing.json') } 'missing enabled file fails closed'
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig 'relative.json' } 'relative path rejected'
    $inside = Join-Path $repo 'public.json'
    [IO.File]::WriteAllText($inside, ($valid | ConvertTo-Json))
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig $inside } 'in-repository configuration rejected'
    $linked = Join-Path $tmp 'linked-repo'
    $linkType = if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }
    New-Item -ItemType $linkType -Path $linked -Target $repo | Out-Null
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig (Join-Path $linked 'public.json') } 'link traversal cannot disguise an in-repository file'
    $otherRepo = Join-Path $tmp 'other-repo'
    New-Item -ItemType Directory $otherRepo | Out-Null
    [IO.File]::WriteAllText((Join-Path $otherRepo '.git'), 'synthetic worktree marker')
    [IO.File]::WriteAllText((Join-Path $otherRepo 'public.json'), ($valid | ConvertTo-Json))
    Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig (Join-Path $otherRepo 'public.json') } 'configuration in another Git checkout rejected'

    foreach ($mutation in @(
            @{ BIZBOT_FIREBASE_PROJECT_ID = 'foreign-project' },
            @{ BIZBOT_FIREBASE_SENDER_ID = '999999999' },
            @{ BIZBOT_FIREBASE_APP_ID = '1:31661231890:android:wrong-app' },
            @{ BIZBOT_FIREBASE_API_KEY = 'malformed' },
            @{ BIZBOT_FIREBASE_API_KEY = ($fixtureKey + "`n") },
            @{ BIZBOT_FIREBASE_SENDER_ID = 31661231890 },
            @{ private_key = 'synthetic-forbidden-extra-field' })) {
        $bad = $valid.Clone()
        foreach ($key in $mutation.Keys) { $bad[$key] = $mutation[$key] }
        [IO.File]::WriteAllText($configPath, ($bad | ConvertTo-Json))
        Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig $configPath } "invalid field/type $(($mutation.Keys)[0]) rejected"
    }
    foreach ($json in @('{malformed', '[]', '{"BIZBOT_FIREBASE_PROJECT_ID":"one","BIZBOT_FIREBASE_PROJECT_ID":"two"}')) {
        [IO.File]::WriteAllText($configPath, $json)
        Reject { Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig $configPath } 'malformed shape or duplicate JSON rejected'
    }
    [IO.File]::WriteAllText($configPath, ($valid | ConvertTo-Json))
    $config = Get-PosFirebaseBuildConfiguration -RepositoryRoot $repo -EnableBackgroundOrderAlerts -FirebasePublicConfig $configPath
    Check ($config.Count -eq 4 -and $config.BIZBOT_FIREBASE_API_KEY -ceq $fixtureKey) 'valid pinned public configuration accepted'
    foreach ($property in $propertyNames) { [Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, 'ambient-value', 'Process') }
    Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -PosFirebaseConfig $config -RepositoryRoot $repo
    $enabled = $calls[-1]
    Check (($enabled.Arguments[-1]) -ceq '--dart-define=BIZBOT_BACKGROUND_ORDER_ALERTS=true') 'enabled POS gets Dart opt-in'
    Check ($enabled.Properties.BIZBOT_BACKGROUND_ORDER_ALERTS -ceq 'true') 'enabled POS gets matching Gradle opt-in'
    foreach ($property in $valid.Keys) { Check ($enabled.Properties[$property] -ceq $valid[$property]) "enabled POS forwards $property" }
    foreach ($property in $propertyNames) { Check ([Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, 'Process') -ceq 'ambient-value') "restored $property after success" }
    Invoke-OfficialFlutterBuild -App kds -BuildArguments $baseArguments -PosFirebaseConfig $config -RepositoryRoot $repo
    $kds = $calls[-1]
    Check (($kds.Arguments -join "`n") -ceq ($baseArguments -join "`n")) 'KDS arguments unchanged byte for byte'
    Check ($kds.Properties.BIZBOT_BACKGROUND_ORDER_ALERTS -ceq 'false') 'KDS cannot inherit native opt-in'
    foreach ($property in $valid.Keys) { Check ($null -eq $kds.Properties[$property]) "KDS does not inherit $property" }
    Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -PosFirebaseConfig $null -RepositoryRoot $repo
    Check (($calls[-1].Arguments -join "`n") -ceq ($baseArguments -join "`n")) 'disabled POS arguments unchanged'
    Check ($calls[-1].Properties.BIZBOT_BACKGROUND_ORDER_ALERTS -ceq 'false') 'ambient environment cannot enable disabled POS'
    foreach ($property in $valid.Keys) { Check ($null -eq $calls[-1].Properties[$property]) "disabled POS clears $property" }

    foreach ($mode in @('nonzero', 'exception')) {
        $flutterExit = if ($mode -eq 'nonzero') { 7 } else { 0 }
        $throwFlutter = $mode -eq 'exception'
        Reject { Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -PosFirebaseConfig $config -RepositoryRoot $repo } "Flutter $mode fails the build"
        foreach ($property in $propertyNames) { Check ([Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, 'Process') -ceq 'ambient-value') "$mode restores $property" }
    }
    $flutterExit = 0
    $throwFlutter = $false
    foreach ($name in @('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'JAVA_OPTS', 'GRADLE_OPTS')) {
        [Environment]::SetEnvironmentVariable($name, '-Dorg.gradle.project.BIZBOT_BACKGROUND_ORDER_ALERTS=true', 'Process')
        $before = $calls.Count
        Reject { Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -RepositoryRoot $repo } "$name override rejected before Flutter"
        Check ($calls.Count -eq $before) 'conflicting override invokes no build'
        [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process')
    }
    $propertiesFile = Join-Path $gradleHome 'gradle.properties'
    foreach ($line in @('systemProp.org.gradle.project.BIZBOT_BACKGROUND_ORDER_ALERTS=true', 'systemProp.org.gradle.project.\u0042IZBOT_BACKGROUND_ORDER_ALERTS=true')) {
        [IO.File]::WriteAllText($propertiesFile, $line)
        Reject { Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -RepositoryRoot $repo } 'conflicting Gradle properties fail closed'
    }
    [IO.File]::WriteAllText($propertiesFile, 'org.gradle.jvmargs=-Xmx1G')
    Invoke-OfficialFlutterBuild -App kds -BuildArguments $baseArguments -RepositoryRoot $repo
    Check ($calls[-1].Properties.BIZBOT_BACKGROUND_ORDER_ALERTS -ceq 'false') 'unrelated Gradle settings remain supported'
    foreach ($property in $propertyNames) { [Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, [NullString]::Value, 'Process') }
    Invoke-OfficialFlutterBuild -App pos -BuildArguments $baseArguments -PosFirebaseConfig $config -RepositoryRoot $repo
    foreach ($property in $propertyNames) { Check ($null -eq [Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_' + $property, 'Process')) "previously absent $property remains absent after build" }
    Write-Output "$passed Firebase build-plumbing assertions passed (FAKE Flutter only)."
}
finally {
    foreach ($name in $original.Keys) {
        if ($null -eq $original[$name]) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process') }
        else { [Environment]::SetEnvironmentVariable($name, $original[$name], 'Process') }
    }
    Remove-Item Function:global:flutter -ErrorAction SilentlyContinue
    $tempRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) + [IO.Path]::DirectorySeparatorChar
    $resolvedTmp = [IO.Path]::GetFullPath($tmp)
    if (-not $resolvedTmp.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not ([IO.Path]::GetFileName($resolvedTmp)).StartsWith('bizbot-firebase-test-')) { throw 'Unsafe temporary cleanup target' }
    if (Test-Path -LiteralPath $resolvedTmp) { Remove-Item -LiteralPath $resolvedTmp -Recurse -Force }
}
