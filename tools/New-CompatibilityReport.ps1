[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AnomalyRoot,
    [Parameter(Mandatory = $true)]
    [string]$Mo2Root,
    [Parameter(Mandatory = $true)]
    [string]$Profile,
    [string]$ReleaseRoot
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReleaseRoot)) {
    $ReleaseRoot = Join-Path $RepoRoot 'src\gamedata'
}

function Resolve-PhysicalDirectory([string]$Path) {
    $Resolved = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
    $Seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    while ($true) {
        if (-not $Seen.Add($Resolved)) {
            throw "Directory reparse-point cycle detected: $Path"
        }
        $Item = Get-Item -LiteralPath $Resolved -Force
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
            return $Item.FullName.TrimEnd('\', '/')
        }
        $Targets = @($Item.Target)
        if ($Targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$Targets[0])) {
            throw "Directory reparse point has no single target: $Resolved"
        }
        $Target = [string]$Targets[0]
        if (-not [IO.Path]::IsPathRooted($Target)) {
            $Target = Join-Path $Item.Parent.FullName $Target
        }
        if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
            throw "Directory reparse-point target does not exist: $Resolved"
        }
        $Resolved = (Resolve-Path -LiteralPath $Target).Path.TrimEnd('\', '/')
    }
}

function Resolve-RequiredDirectory([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }
    return Resolve-PhysicalDirectory $Path
}

function Test-ContainedPath([string]$Parent, [string]$Candidate, [bool]$AllowEqual) {
    $NormalizedParent = $Parent.TrimEnd('\', '/')
    $NormalizedCandidate = $Candidate.TrimEnd('\', '/')
    if ($AllowEqual -and [string]::Equals($NormalizedParent, $NormalizedCandidate, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $Prefix = $NormalizedParent + [IO.Path]::DirectorySeparatorChar
    return $NormalizedCandidate.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-ContainedDirectory(
    [string]$Path,
    [string]$Parent,
    [string]$Label,
    [string]$ParentLabel,
    [bool]$AllowEqual = $false
) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label does not exist: $Path"
    }
    $Resolved = Resolve-PhysicalDirectory $Path
    if (-not (Test-ContainedPath $Parent $Resolved $AllowEqual)) {
        throw "Resolved $Label escapes $ParentLabel root: $Resolved"
    }
    return $Resolved
}

function Test-SinglePathComponent([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq '.' -or $Name -eq '..') {
        return $false
    }
    if ($Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        return $false
    }
    if (-not [string]::Equals($Name.TrimEnd([char[]]@(' ', '.')), $Name, [StringComparison]::Ordinal)) {
        return $false
    }
    if ($Name -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
        return $false
    }
    return [string]::Equals([IO.Path]::GetFileName($Name), $Name, [StringComparison]::Ordinal)
}

function Get-OrdinalSortedFiles([string]$Root) {
    $Paths = @([IO.Directory]::GetFiles($Root, '*', [IO.SearchOption]::AllDirectories))
    [Array]::Sort($Paths, [StringComparer]::Ordinal)
    return $Paths
}

function Get-NormalizedRelativePath([string]$Root, [string]$Path) {
    return $Path.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function ConvertTo-MarkdownCell([object]$Value) {
    if ($null -eq $Value) {
        return ''
    }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function Get-ModDataRoot([string]$ModRoot) {
    $NestedGameData = Join-Path $ModRoot 'gamedata'
    if (Test-Path -LiteralPath $NestedGameData -PathType Container) {
        return Resolve-ContainedDirectory $NestedGameData $ModRoot 'MO2 mod data root' 'enabled mod' $false
    }
    return $ModRoot
}

$AnomalyRoot = Resolve-RequiredDirectory $AnomalyRoot 'Anomaly root'
$Mo2Root = Resolve-RequiredDirectory $Mo2Root 'MO2 root'
$ReleaseRoot = Resolve-RequiredDirectory $ReleaseRoot 'Release root'

if ([string]::IsNullOrWhiteSpace($Profile) -or
    $Profile -eq '.' -or $Profile -eq '..' -or
    $Profile.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
    $Profile.Contains('\') -or $Profile.Contains('/')) {
    throw "MO2 profile name is invalid: $Profile"
}

$ProfilesRoot = Resolve-RequiredDirectory (Join-Path $Mo2Root 'profiles') 'MO2 profiles root'
$ProfileRoot = Resolve-ContainedDirectory (Join-Path $ProfilesRoot $Profile) $ProfilesRoot 'MO2 profile' 'profiles' $false
$ModListPath = Join-Path $ProfileRoot 'modlist.txt'
if (-not (Test-Path -LiteralPath $ModListPath -PathType Leaf)) {
    throw "Active MO2 profile modlist.txt does not exist: $ModListPath"
}

$ModsRoot = Resolve-RequiredDirectory (Join-Path $Mo2Root 'mods') 'MO2 mods root'

$EnabledMods = @()
$Priority = 0
foreach ($RawLine in @(Get-Content -LiteralPath $ModListPath)) {
    $Line = $RawLine.TrimStart([char]0xFEFF)
    if (-not $Line.StartsWith('+', [StringComparison]::Ordinal)) {
        continue
    }
    $ModName = $Line.Substring(1)
    if (-not (Test-SinglePathComponent $ModName)) {
        throw "Enabled MO2 mod name is invalid: $ModName"
    }
    $ModRoot = Resolve-ContainedDirectory (Join-Path $ModsRoot $ModName) $ModsRoot 'enabled MO2 mod' 'mods' $false
    $EnabledMods += [PSCustomObject]@{
        Priority = $Priority
        Name = $ModName
        Root = $ModRoot
        DataRoot = Get-ModDataRoot $ModRoot
    }
    $Priority += 1
}

$ExecutablePaths = New-Object System.Collections.Generic.List[string]
$ExecutableSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$BinRoot = Join-Path $AnomalyRoot 'bin'
if (Test-Path -LiteralPath $BinRoot -PathType Container) {
    foreach ($Path in @([IO.Directory]::GetFiles($BinRoot, 'AnomalyDX*.exe', [IO.SearchOption]::TopDirectoryOnly))) {
        if ($ExecutableSeen.Add($Path)) {
            $ExecutablePaths.Add($Path)
        }
    }
    $VerifiedPath = Join-Path $BinRoot 'VerifiedDX11.exe'
    if ((Test-Path -LiteralPath $VerifiedPath -PathType Leaf) -and $ExecutableSeen.Add($VerifiedPath)) {
        $ExecutablePaths.Add($VerifiedPath)
    }
}
$ExecutableArray = $ExecutablePaths.ToArray()
[Array]::Sort($ExecutableArray, [StringComparer]::Ordinal)

$CriticalPaths = @(
    'configs/ui/ui_mm_main.xml',
    'scripts/axr_main.script',
    'scripts/bind_stalker_ext.script',
    'scripts/ui_main_menu.script',
    'scripts/ui_mm_faction_select.script',
    'scripts/xrs_rnd_npc_loadout.script'
)
[Array]::Sort($CriticalPaths, [StringComparer]::Ordinal)
$Providers = @()
foreach ($RelativePath in $CriticalPaths) {
    $NativeRelativePath = $RelativePath.Replace('/', '\')
    $ProviderName = 'MISSING'
    $ProviderPath = $null
    $BasePath = Join-Path (Join-Path $AnomalyRoot 'gamedata') $NativeRelativePath
    if (Test-Path -LiteralPath $BasePath -PathType Leaf) {
        $ProviderName = 'Anomaly base'
        $ProviderPath = $BasePath
    }
    foreach ($Mod in $EnabledMods) {
        $Candidate = Join-Path $Mod.DataRoot $NativeRelativePath
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $ProviderName = 'MO2 mod: ' + $Mod.Name
            $ProviderPath = $Candidate
        }
    }
    $Providers += [PSCustomObject]@{
        RelativePath = $RelativePath
        Provider = $ProviderName
        Path = $ProviderPath
        Sha256 = if ($null -eq $ProviderPath) { '-' } else { Get-Sha256 $ProviderPath }
    }
}
$MissingProviders = @($Providers | Where-Object { $null -eq $_.Path })

$ForbiddenOverrides = @(
    'configs/items/settings/npc_loadouts/npc_loadouts.ltx',
    'configs/system.ltx',
    'scripts/axr_main.script',
    'scripts/bind_stalker_ext.script',
    'scripts/ui_main_menu.script',
    'scripts/ui_mm_faction_select.script'
)
$ForbiddenSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($ForbiddenPath in $ForbiddenOverrides) {
    $null = $ForbiddenSet.Add($ForbiddenPath)
}

$ReleaseFiles = @()
foreach ($Path in (Get-OrdinalSortedFiles $ReleaseRoot)) {
    $RelativePath = Get-NormalizedRelativePath $ReleaseRoot $Path
    $ReleaseFiles += [PSCustomObject]@{
        RelativePath = $RelativePath
        Path = $Path
        Sha256 = Get-Sha256 $Path
    }
}

$BlockingOverrides = @($ReleaseFiles | Where-Object { $ForbiddenSet.Contains($_.RelativePath) })
$OverlapRows = @()
foreach ($ReleaseFile in $ReleaseFiles) {
    $NativeRelativePath = $ReleaseFile.RelativePath.Replace('/', '\')
    foreach ($Mod in $EnabledMods) {
        $Candidate = Join-Path $Mod.DataRoot $NativeRelativePath
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            $OverlapRows += [PSCustomObject]@{
                RelativePath = $ReleaseFile.RelativePath
                ModName = $Mod.Name
                Priority = $Mod.Priority
                ExistingSha256 = Get-Sha256 $Candidate
                ReleaseSha256 = $ReleaseFile.Sha256
            }
        }
    }
}
# ReleaseFiles is ordinally sorted and EnabledMods retains modlist priority, so
# the nested scan already emits deterministic path/priority order without a
# culture-sensitive Sort-Object comparison.

$Lines = New-Object System.Collections.Generic.List[string]
$Lines.Add('# Gamma Arena compatibility report')
$Lines.Add('')
$Lines.Add('Active MO2 profile: `' + (ConvertTo-MarkdownCell $Profile) + '`')
$Lines.Add('')
$Lines.Add('- Anomaly root: `' + (ConvertTo-MarkdownCell $AnomalyRoot) + '`')
$Lines.Add('- MO2 root: `' + (ConvertTo-MarkdownCell $Mo2Root) + '`')
$Lines.Add('- Release data root: `' + (ConvertTo-MarkdownCell $ReleaseRoot) + '`')
$Lines.Add('- Enabled-mod precedence: later enabled entries in `modlist.txt` win')
$Lines.Add('')
$Lines.Add('## Active profile fingerprint')
$Lines.Add('')
$Lines.Add('| File | SHA-256 |')
$Lines.Add('| --- | --- |')
$Lines.Add('| `' + (ConvertTo-MarkdownCell $ModListPath) + '` | `' + (Get-Sha256 $ModListPath) + '` |')
$Lines.Add('')
$Lines.Add('## Executable fingerprints')
$Lines.Add('')
if ($ExecutableArray.Count -eq 0) {
    $Lines.Add('No matching `AnomalyDX*.exe` or `VerifiedDX11.exe` files are present.')
}
else {
    $Lines.Add('| File | SHA-256 |')
    $Lines.Add('| --- | --- |')
    foreach ($Path in $ExecutableArray) {
        $Lines.Add('| `' + (ConvertTo-MarkdownCell ([IO.Path]::GetFileName($Path))) + '` | `' + (Get-Sha256 $Path) + '` |')
    }
}
$Lines.Add('')
$Lines.Add('## Effective critical providers')
$Lines.Add('')
$Lines.Add('| Virtual path | Provider | Provider file | SHA-256 |')
$Lines.Add('| --- | --- | --- | --- |')
foreach ($Provider in $Providers) {
    $ProviderPathText = if ($null -eq $Provider.Path) { '-' } else { '`' + (ConvertTo-MarkdownCell $Provider.Path) + '`' }
    $HashText = if ($Provider.Sha256 -eq '-') { '-' } else { '`' + $Provider.Sha256 + '`' }
    $Lines.Add('| `' + (ConvertTo-MarkdownCell $Provider.RelativePath) + '` | ' + (ConvertTo-MarkdownCell $Provider.Provider) + ' | ' + $ProviderPathText + ' | ' + $HashText + ' |')
}
$Lines.Add('')
$Lines.Add('Missing critical providers: ' + $MissingProviders.Count)
if ($MissingProviders.Count -gt 0) {
    $Lines.Add('Evidence status: **INCOMPLETE**')
}
$Lines.Add('')
$Lines.Add('## Release overlap review')
$Lines.Add('')
$Lines.Add('- **' + $BlockingOverrides.Count + ' blocking overlaps**')
$WarningLabel = if ($OverlapRows.Count -eq 1) { 'warning overlap' } else { 'warning overlaps' }
$Lines.Add('- **' + $OverlapRows.Count + ' ' + $WarningLabel + '** requiring explicit review')
$Lines.Add('- Forbidden core overrides: ' + $BlockingOverrides.Count)
$Lines.Add('')
$Lines.Add('Exact same-path matches are warnings only. This tool never overwrites or modifies Anomaly, MO2, profile, or mod files.')
$Lines.Add('')
if ($BlockingOverrides.Count -gt 0) {
    $Lines.Add('### Blocking release files')
    $Lines.Add('')
    foreach ($Blocked in $BlockingOverrides) {
        $Lines.Add('- `' + (ConvertTo-MarkdownCell $Blocked.RelativePath) + '`')
    }
    $Lines.Add('')
}
if ($OverlapRows.Count -eq 0) {
    $Lines.Add('No active MO2 mod folder contains an exact relative-path match for a release file.')
}
else {
    $Lines.Add('| Release path | Active mod | Priority | Existing SHA-256 | Release SHA-256 |')
    $Lines.Add('| --- | --- | ---: | --- | --- |')
    foreach ($Overlap in $OverlapRows) {
        $Lines.Add('| `' + (ConvertTo-MarkdownCell $Overlap.RelativePath) + '` | ' + (ConvertTo-MarkdownCell $Overlap.ModName) + ' | ' + $Overlap.Priority + ' | `' + $Overlap.ExistingSha256 + '` | `' + $Overlap.ReleaseSha256 + '` |')
    }
}
$Lines.Add('')
if ($MissingProviders.Count -gt 0) {
    $Lines.Add('This fingerprint is INCOMPLETE because one or more critical providers are missing; it is not an installed-runtime PASS result.')
}
else {
    $Lines.Add('This fingerprint is compatibility evidence only; it is not an installed-runtime PASS result.')
}

[Console]::Out.Write(($Lines -join "`n") + "`n")
if ($BlockingOverrides.Count -gt 0) {
    exit 2
}
if ($MissingProviders.Count -gt 0) {
    exit 3
}
