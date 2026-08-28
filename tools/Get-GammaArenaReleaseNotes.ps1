[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$TagMatch = [regex]::Match(
    $Tag,
    '^v(?<version>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))$',
    [Text.RegularExpressions.RegexOptions]::CultureInvariant
)
if (-not $TagMatch.Success) {
    throw "Release tag must match vX.Y.Z: $Tag"
}
$Version = $TagMatch.Groups['version'].Value

$VersionPath = Join-Path $RepoRoot 'VERSION'
$ChangelogPath = Join-Path $RepoRoot 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $VersionPath -PathType Leaf)) {
    throw "VERSION is missing: $VersionPath"
}
if (-not (Test-Path -LiteralPath $ChangelogPath -PathType Leaf)) {
    throw "CHANGELOG.md is missing: $ChangelogPath"
}

$RecordedVersion = ([IO.File]::ReadAllText($VersionPath)).Trim()
if ($RecordedVersion -cne $Version) {
    throw "Tag version $Version does not match VERSION $RecordedVersion"
}

$Changelog = ([IO.File]::ReadAllText($ChangelogPath)).Replace("`r`n", "`n").Replace("`r", "`n")
$EscapedVersion = [regex]::Escape($Version)
$VersionHeadings = [regex]::Matches(
    $Changelog,
    '(?m)^##[ \t]+' + $EscapedVersion + '(?:[ \t]+-[ \t]+[^\n]*)?[ \t]*$'
)
if ($VersionHeadings.Count -eq 0) {
    throw "Release changelog section is missing: $Version"
}

$ValidHeadings = [regex]::Matches(
    $Changelog,
    '(?m)^##[ \t]+' + $EscapedVersion + '[ \t]+-[ \t]+(?<date>\d{4}-\d{2}-\d{2})[ \t]*$'
)
if ($VersionHeadings.Count -ne 1 -or $ValidHeadings.Count -ne 1) {
    if ($VersionHeadings.Count -eq 1 -and $ValidHeadings.Count -eq 0) {
        throw "Release changelog heading is malformed: $Version"
    }
    throw "Release changelog must contain exactly one section: $Version"
}

$ParsedDate = [DateTime]::MinValue
if (-not [DateTime]::TryParseExact(
    $ValidHeadings[0].Groups['date'].Value,
    'yyyy-MM-dd',
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::None,
    [ref]$ParsedDate
)) {
    throw "Release changelog heading is malformed: $Version"
}

$AllHeadings = [regex]::Matches($Changelog, '(?m)^##[ \t]+[^\n]+$')
$BodyStart = $ValidHeadings[0].Index + $ValidHeadings[0].Length
$BodyEnd = $Changelog.Length
foreach ($Heading in $AllHeadings) {
    if ($Heading.Index -gt $ValidHeadings[0].Index) {
        $BodyEnd = $Heading.Index
        break
    }
}
$Body = $Changelog.Substring($BodyStart, $BodyEnd - $BodyStart).Trim()
if ([string]::IsNullOrWhiteSpace($Body)) {
    throw "Release changelog section is empty: $Version"
}

$OutputParent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $OutputParent -Force | Out-Null
[IO.File]::WriteAllText(
    $OutputPath,
    ($Body + "`n"),
    (New-Object Text.UTF8Encoding($false))
)
