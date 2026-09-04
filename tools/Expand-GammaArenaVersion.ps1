[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
$VersionMarker = '@GAMMA_ARENA_VERSION@'

if ($Version -notmatch '^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
    throw "Version must be a plain SemVer triplet: $Version"
}
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Runtime version target is missing: $Path"
}

$Content = [IO.File]::ReadAllText($Path)
$MarkerCount = [regex]::Matches($Content, [regex]::Escape($VersionMarker)).Count
if ($MarkerCount -ne 1) {
    throw "Runtime version target must contain exactly one $VersionMarker marker; found $MarkerCount"
}

$ExpandedContent = $Content.Replace($VersionMarker, $Version)
[IO.File]::WriteAllText($Path, $ExpandedContent, (New-Object Text.UTF8Encoding($false)))
