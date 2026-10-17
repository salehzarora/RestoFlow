# BIZBOT-POS-V64-FIREBASE-BUILD-PLUMBING-001. Public build inputs only.
# Dot-sourceable for synthetic tests; never builds anything on import.

function Set-OfficialBuildEnvironmentValue([string]$Name, [AllowNull()][object]$Value) {
    if ($null -eq $Value) {
        # PowerShell converts an ordinary $null to an empty string for .NET string parameters.
        [Environment]::SetEnvironmentVariable($Name, [NullString]::Value, 'Process')
    }
    else { [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process') }
}

function Get-PosFirebaseBuildConfiguration {
    [CmdletBinding()]
    param(
        [switch]$EnableBackgroundOrderAlerts,
        [string]$FirebasePublicConfig = '',
        [Parameter(Mandatory)][string]$RepositoryRoot
    )

    if (-not $EnableBackgroundOrderAlerts) {
        if ($FirebasePublicConfig) { throw 'Firebase configuration requires explicit background-alert opt-in.' }
        return $null
    }
    if (-not $FirebasePublicConfig -or -not [IO.Path]::IsPathFullyQualified($FirebasePublicConfig)) {
        throw 'Enabled POS alerts require an absolute external public-configuration file path.'
    }
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($RepositoryRoot)) + [IO.Path]::DirectorySeparatorChar
    $path = [IO.Path]::GetFullPath($FirebasePublicConfig)
    if ($path.StartsWith($root, $comparison)) { throw 'Firebase public configuration must remain outside the repository.' }
    try { $file = Get-Item -LiteralPath $path -ErrorAction Stop }
    catch { throw 'Firebase public configuration is unavailable.' }
    if ($file.PSIsContainer -or $file.Length -gt 8192) { throw 'Invalid Firebase public-configuration file.' }
    # Reject link/junction traversal rather than mistaking an in-repo target for an external file.
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Firebase configuration cannot traverse filesystem links.' }
    for ($entry = $file.Directory; $null -ne $entry; $entry = $entry.Parent) {
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Firebase configuration cannot traverse filesystem links.' }
        if (Test-Path -LiteralPath (Join-Path $entry.FullName '.git')) { throw 'Firebase public configuration must remain outside Git checkouts.' }
    }
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($path))
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'shape' }
        $config = @{}
        foreach ($field in $document.RootElement.EnumerateObject()) {
            if ($field.Name -cnotin @('BIZBOT_FIREBASE_APP_ID', 'BIZBOT_FIREBASE_API_KEY', 'BIZBOT_FIREBASE_PROJECT_ID', 'BIZBOT_FIREBASE_SENDER_ID') -or
                $config.ContainsKey($field.Name) -or $field.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw 'field' }
            $config[$field.Name] = $field.Value.GetString()
        }
        if ($config.Count -ne 4 -or
            $config.BIZBOT_FIREBASE_APP_ID -cne '1:31661231890:android:1856c6d5ac4e64a229adcb' -or
            $config.BIZBOT_FIREBASE_PROJECT_ID -cne 'bizbot-production' -or
            $config.BIZBOT_FIREBASE_SENDER_ID -cne '31661231890' -or
            $config.BIZBOT_FIREBASE_API_KEY -cnotmatch '\AAIza[0-9A-Za-z_-]{35}\z') { throw 'identity' }
        return $config
    }
    catch { throw 'Invalid public Firebase configuration: require exactly four string fields for the approved BIZBOT production Android app.' }
    finally { if ($document) { $document.Dispose() } }
}

function Assert-NoFirebaseBuildOverrides {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $reserved = 'BIZBOT_(BACKGROUND_ORDER_ALERTS|FIREBASE_)'
    foreach ($name in @('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'JAVA_OPTS', 'GRADLE_OPTS')) {
        if ([Environment]::GetEnvironmentVariable($name, 'Process') -match $reserved) {
            throw 'Reserved Firebase JVM overrides are not permitted in an official build.'
        }
    }
    $userGradle = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gradle' }
    $files = @((Join-Path $userGradle 'gradle.properties'),
        (Join-Path $RepositoryRoot 'apps/pos/android/gradle.properties'),
        (Join-Path $RepositoryRoot 'apps/kds/android/gradle.properties'))
    if ($env:GRADLE_HOME) { $files += Join-Path $env:GRADLE_HOME 'gradle.properties' }
    foreach ($file in $files) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $text = [IO.File]::ReadAllText($file)
        $text = [regex]::Replace($text, '\\u([0-9a-fA-F]{4})', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
        $text = $text -replace '\\\r?\n\s*', '' -replace '\\(.)', '$1'
        if ($text -match $reserved) { throw 'Reserved Firebase Gradle settings must be supplied only by the official runner.' }
    }
}

function Invoke-OfficialFlutterBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('pos', 'kds')][string]$App,
        [Parameter(Mandatory)][string[]]$BuildArguments,
        [AllowNull()][hashtable]$PosFirebaseConfig,
        [Parameter(Mandatory)][string]$RepositoryRoot
    )
    Assert-NoFirebaseBuildOverrides -RepositoryRoot $RepositoryRoot
    $enabled = $App -eq 'pos' -and $null -ne $PosFirebaseConfig
    $properties = @{
        BIZBOT_BACKGROUND_ORDER_ALERTS = $(if ($enabled) { 'true' } else { 'false' })
        BIZBOT_FIREBASE_APP_ID = $null
        BIZBOT_FIREBASE_API_KEY = $null
        BIZBOT_FIREBASE_PROJECT_ID = $null
        BIZBOT_FIREBASE_SENDER_ID = $null
    }
    if ($enabled) {
        foreach ($key in $PosFirebaseConfig.Keys) { $properties[$key] = $PosFirebaseConfig[$key] }
        $BuildArguments = @($BuildArguments) + '--dart-define=BIZBOT_BACKGROUND_ORDER_ALERTS=true'
    }
    $previous = @{}
    try {
        foreach ($key in $properties.Keys) {
            $name = 'ORG_GRADLE_PROJECT_' + $key
            $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
            Set-OfficialBuildEnvironmentValue $name $properties[$key]
        }
        & flutter @BuildArguments
        if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    }
    finally {
        foreach ($name in $previous.Keys) { Set-OfficialBuildEnvironmentValue $name $previous[$name] }
    }
}
