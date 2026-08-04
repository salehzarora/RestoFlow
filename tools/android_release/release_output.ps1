# ============================================================================
# OFFICIAL-RELEASE-RUNNER-V21-002 — release output writers.
#
# Every file the official runner emits is written through here, so the format
# is defined once and can be regression-tested WITHOUT building an APK.
#
# WHY THIS EXISTS. The first official build (v21) produced a SHA256SUMS.txt that
# `sha256sum -c` could not read: `[System.IO.File]::WriteAllLines` uses
# `Environment.NewLine`, which is CRLF on Windows, and the trailing \r was
# parsed as part of each filename ("No such file or directory"). A checksum file
# that cannot be verified is worse than none - it looks like provenance while
# providing none. The same build also emitted a BUILD-METADATA.txt missing most
# of the release facts a reviewer needs.
#
# Dot-source it:  . "$PSScriptRoot\release_output.ps1"
# ============================================================================

# NOTE: deliberately no `Set-StrictMode` here. This file is dot-sourced into the
# release runner, and strict mode would change that caller's semantics rather
# than just this helper's - an output helper must not alter build behaviour.

# Values that must never reach a release file, even by accident.
$script:ReleaseForbiddenPatterns = @(
    '(?i)storePassword\s*=\s*\S',
    '(?i)keyPassword\s*=\s*\S',
    '(?i)-----BEGIN [A-Z ]*PRIVATE KEY-----',
    '(?i)\.p12(\b|$)',
    '(?i)\.jks(\b|$)',
    '(?i)\.keystore(\b|$)',
    '(?i)signing\.properties',
    '(?i)key\.properties'
)

<#
.SYNOPSIS
Writes UTF-8 (no BOM), LF-only text with exactly one final LF.

.DESCRIPTION
The one writer for every release output. Trailing whitespace is stripped from
each line, CR is removed, and the content is refused outright if it carries
signing material - a release file is published evidence, so a leak here is not
recoverable by editing it afterwards.
#>
function Write-ReleaseTextFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        # AllowEmptyString is required as well as AllowEmptyCollection: a
        # mandatory [string[]] otherwise rejects the blank separator lines that
        # make the metadata readable.
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()][AllowEmptyString()]
        [string[]]$Lines,
        [switch]$AllowSigningPaths
    )
    $clean = foreach ($l in $Lines) { ($l -replace "`r", '').TrimEnd() }

    if (-not $AllowSigningPaths) {
        foreach ($l in $clean) {
            foreach ($p in $script:ReleaseForbiddenPatterns) {
                if ($l -match $p) {
                    throw "Refusing to write a release file containing signing material (pattern: $p)."
                }
            }
        }
    }

    $text = ($clean -join "`n")
    if ($text.Length -gt 0) { $text += "`n" }   # exactly one final LF
    [System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

<#
.SYNOPSIS
Builds the canonical `sha256sum -c` compatible SHA256SUMS.txt lines.

.DESCRIPTION
Format: "<lowercase sha256><two spaces><bare filename>". Bare filename only -
an absolute path would leak the machine layout and would not resolve on a
reviewer's machine. Order is caller-defined (POS first, then KDS).
#>
function New-ReleaseChecksumLines {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$FilePaths)

    $lines = @()
    foreach ($f in $FilePaths) {
        if (-not (Test-Path $f)) { throw "Cannot checksum a missing file: $f" }
        $hash = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
        $name = [System.IO.Path]::GetFileName($f)
        $lines += ('{0}  {1}' -f $hash, $name)
    }
    return $lines
}

<#
.SYNOPSIS
Writes SHA256SUMS.txt into the output directory.
#>
function Write-ReleaseChecksums {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][string[]]$FilePaths
    )
    $lines = New-ReleaseChecksumLines -FilePaths $FilePaths
    # Bare filenames are not signing paths; the guard would trip on ".p12"-like
    # names only, and APKs are safe, but be explicit about intent.
    Write-ReleaseTextFile -Path (Join-Path $OutputRoot 'SHA256SUMS.txt') -Lines $lines
    return $lines
}

# Normalises an optional value: blank/missing becomes the explicit sentinel so a
# reviewer can tell "not detected" from "silently omitted".
function Get-ReleaseValue {
    param($Value)
    if ($null -eq $Value) { return 'NOT DETECTED' }
    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return 'NOT DETECTED' }
    return $s.Trim()
}

function Format-ReleaseField {
    param([string]$Label, $Value)
    return ('{0,-22}{1}' -f $Label, (Get-ReleaseValue $Value))
}

function Format-ReleaseArtifactSection {
    param([string]$Heading, [hashtable]$A)
    $out = @($Heading, ('-' * $Heading.Length))
    foreach ($f in @(
            @('Filename', 'Filename'), @('Package ID', 'PackageId'),
            @('versionName', 'VersionName'), @('versionCode', 'VersionCode'),
            @('Size (bytes)', 'SizeBytes'), @('Size (MiB)', 'SizeMiB'),
            @('SHA-256', 'Sha256'), @('Created', 'Created'),
            @('Debuggable', 'Debuggable'), @('Demo mode', 'DemoMode'),
            @('AOT posture', 'Aot'), @('ABI', 'Abi'),
            @('minSdk', 'MinSdk'), @('targetSdk', 'TargetSdk'),
            @('zipalign', 'ZipAlign'), @('apksigner', 'ApkSigner'),
            @('Certificate SHA-256', 'CertSha256'), @('Source SHA', 'SourceSha'))) {
        $v = $null
        if ($A.ContainsKey($f[1])) { $v = $A[$f[1]] }
        $out += (Format-ReleaseField -Label $f[0] -Value $v)
    }
    return $out
}

<#
.SYNOPSIS
Builds BUILD-METADATA.txt content with deterministic labels and ordering.

.DESCRIPTION
Takes a plain hashtable so it can be exercised from tests with synthetic values
and no signing access. Any absent toolchain value renders as NOT DETECTED
rather than disappearing: a missing line reads like "not applicable", which is
exactly the wrong impression in a provenance record.
#>
function New-ReleaseMetadataLines {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Data)

    function V($k) { if ($Data.ContainsKey($k)) { return $Data[$k] } return $null }

    $lines = @()
    $lines += 'RestoFlow official Android release'
    $lines += '=================================='
    $lines += ''
    $lines += 'RELEASE IDENTITY'
    $lines += '----------------'
    $lines += (Format-ReleaseField 'Task ID' (V 'TaskId'))
    $lines += (Format-ReleaseField 'Status' (V 'Status'))
    $lines += (Format-ReleaseField 'Release name' (V 'ReleaseName'))
    $lines += (Format-ReleaseField 'versionName' (V 'VersionName'))
    $lines += (Format-ReleaseField 'versionCode' (V 'VersionCode'))
    $lines += (Format-ReleaseField 'Branch' (V 'Branch'))
    $lines += (Format-ReleaseField 'Source SHA' (V 'SourceSha'))
    $lines += (Format-ReleaseField 'Source subject' (V 'SourceSubject'))
    $lines += (Format-ReleaseField 'Build started' (V 'BuildStart'))
    $lines += (Format-ReleaseField 'Build completed' (V 'BuildEnd'))
    $lines += (Format-ReleaseField 'Output directory' (V 'OutputDirectory'))
    $lines += ''
    $lines += 'TOOLCHAIN'
    $lines += '---------'
    $lines += (Format-ReleaseField 'Flutter' (V 'Flutter'))
    $lines += (Format-ReleaseField 'Dart' (V 'Dart'))
    $lines += (Format-ReleaseField 'Java' (V 'Java'))
    $lines += (Format-ReleaseField 'Gradle' (V 'Gradle'))
    $lines += (Format-ReleaseField 'Android build-tools' (V 'BuildTools'))
    $lines += (Format-ReleaseField 'apksigner' (V 'ApkSignerTool'))
    $lines += (Format-ReleaseField 'zipalign' (V 'ZipAlignTool'))
    $lines += ''
    $lines += 'PRODUCTION CERTIFICATE'
    $lines += '----------------------'
    $lines += (Format-ReleaseField 'Alias' (V 'CertAlias'))
    $lines += (Format-ReleaseField 'Certificate SHA-256' (V 'CertFingerprint'))
    $lines += (Format-ReleaseField 'Signature algorithm' (V 'CertSignatureAlgorithm'))
    $lines += (Format-ReleaseField 'Public key' (V 'CertPublicKey'))
    $lines += (Format-ReleaseField 'Is Android Debug' (V 'CertIsAndroidDebug'))
    $lines += ''
    $pos = @{}; if ($Data.ContainsKey('Pos') -and $Data['Pos']) { $pos = $Data['Pos'] }
    $kds = @{}; if ($Data.ContainsKey('Kds') -and $Data['Kds']) { $kds = $Data['Kds'] }
    $lines += (Format-ReleaseArtifactSection 'POS ARTIFACT' $pos)
    $lines += ''
    $lines += (Format-ReleaseArtifactSection 'KDS ARTIFACT' $kds)
    $lines += ''
    $lines += 'BACKEND POSTURE'
    $lines += '---------------'
    $lines += (Format-ReleaseField 'Hosted project' (V 'BackendHosted'))
    $lines += (Format-ReleaseField 'Forbidden reference' (V 'BackendForbidden'))
    $lines += (Format-ReleaseField 'Localhost/test backend' (V 'BackendLocalhost'))
    $lines += (Format-ReleaseField 'Secrets in this file' 'none - no password, properties content or private path is recorded')
    $lines += ''
    $lines += 'PROVENANCE AND SAFETY'
    $lines += '---------------------'
    $lines += (Format-ReleaseField 'Created this build' (V 'CreatedThisBuild'))
    $lines += (Format-ReleaseField 'Same source SHA' (V 'SameSourceSha'))
    $lines += (Format-ReleaseField 'Version symmetry' (V 'VersionSymmetry'))
    $lines += (Format-ReleaseField 'SHA256SUMS verified' (V 'ChecksumsVerified'))
    $lines += (Format-ReleaseField 'Installed' 'NO - no artifact was installed on any device')
    $lines += (Format-ReleaseField 'Uploaded' 'NO - no artifact was uploaded or distributed')
    $lines += (Format-ReleaseField 'GitHub Release' 'NO - no release was created')
    $lines += (Format-ReleaseField 'Tracked source change' 'NONE retained - version came from build-time arguments')
    $lines += (Format-ReleaseField 'Commit or push' 'NONE performed by the build runner')
    $comparison = V 'Comparison'
    if (-not [string]::IsNullOrWhiteSpace([string]$comparison)) {
        $lines += ''
        $lines += 'COMPARISON WITH PREVIOUS RELEASE'
        $lines += '--------------------------------'
        foreach ($c in ([string]$comparison -split "`n")) { $lines += ($c -replace "`r", '').TrimEnd() }
    }
    return $lines
}

<#
.SYNOPSIS
Writes BUILD-METADATA.txt into the output directory.
#>
function Write-ReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][hashtable]$Data
    )
    $lines = New-ReleaseMetadataLines -Data $Data
    Write-ReleaseTextFile -Path (Join-Path $OutputRoot 'BUILD-METADATA.txt') -Lines $lines
    return $lines
}
