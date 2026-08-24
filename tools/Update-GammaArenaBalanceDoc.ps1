[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$DocumentPath,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($DocumentPath)) {
    $DocumentPath = Join-Path $RepoRoot 'docs\arena-balance.md'
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$DocumentPath = [IO.Path]::GetFullPath($DocumentPath)

function Read-GammaArenaLtx([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Balance source is missing: $Path"
    }

    $Sections = [ordered]@{}
    $Current = $null
    $LineNumber = 0
    foreach ($RawLine in Get-Content -LiteralPath $Path) {
        $LineNumber++
        $Line = $RawLine.Trim()
        if ($Line.Length -eq 0 -or $Line.StartsWith(';') -or $Line.StartsWith('#')) {
            continue
        }
        if ($Line -match '^\[([^\]]+)\]$') {
            $Name = $Matches[1]
            if ($Sections.Contains($Name)) {
                throw "LTX duplicate section '$Name' at ${Path}:$LineNumber"
            }
            $Sections[$Name] = [ordered]@{}
            $Current = $Sections[$Name]
            continue
        }
        if ($null -eq $Current -or $Line -notmatch '^([^=]+?)\s*=\s*(.*?)\s*$') {
            throw "Malformed LTX line at ${Path}:$LineNumber"
        }
        $Key = $Matches[1].Trim()
        if ($Current.Contains($Key)) {
            throw "LTX duplicate key '$Key' at ${Path}:$LineNumber"
        }
        $Current[$Key] = $Matches[2]
    }
    return $Sections
}

function Get-RequiredLtxValue($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    if (-not $Ltx.Contains($Section) -or -not $Ltx[$Section].Contains($Key)) {
        throw "Required LTX value [$Section] $Key is missing: $Path"
    }
    $Value = [string]$Ltx[$Section][$Key]
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Required LTX value [$Section] $Key is empty: $Path"
    }
    return $Value
}

function Get-RequiredLtxInt($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    $Raw = Get-RequiredLtxValue $Ltx $Section $Key $Path
    $Value = 0
    if (-not [int]::TryParse(
        $Raw,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$Value
    )) {
        throw "Required integer [$Section] $Key is malformed: $Path"
    }
    return $Value
}

function Get-RequiredLtxNumber($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    $Raw = Get-RequiredLtxValue $Ltx $Section $Key $Path
    $Value = 0.0
    if (-not [double]::TryParse(
        $Raw,
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$Value
    )) {
        throw "Required number [$Section] $Key is malformed: $Path"
    }
    return $Value
}

function Get-LtxCsv($Ltx, [string]$Section, [string]$Key, [string]$Path) {
    $Values = New-Object System.Collections.Generic.List[string]
    $Seen = @{}
    foreach ($Value in (Get-RequiredLtxValue $Ltx $Section $Key $Path).Split(',')) {
        $Trimmed = $Value.Trim()
        if ($Trimmed.Length -eq 0) { throw "Empty list value [$Section] $Key`: $Path" }
        if ($Seen.ContainsKey($Trimmed)) { throw "Duplicate list value '$Trimmed' [$Section] $Key`: $Path" }
        $Seen[$Trimmed] = $true
        $Values.Add($Trimmed) | Out-Null
    }
    return @($Values)
}

function Get-RequiredLtxNumberList($Ltx, [string]$Section, [string]$Key, [string]$Path, [int]$ExpectedCount) {
    $Values = New-Object System.Collections.Generic.List[double]
    $Seen = @{}
    foreach ($RawValue in (Get-RequiredLtxValue $Ltx $Section $Key $Path).Split(',')) {
        $Trimmed = $RawValue.Trim()
        $Value = 0.0
        if (-not [double]::TryParse(
            $Trimmed,
            [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture,
            [ref]$Value
        ) -or $Value -le 0) {
            throw "Required positive number list [$Section] $Key is malformed: $Path"
        }
        $Canonical = $Value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        if ($Seen.ContainsKey($Canonical)) {
            throw "Duplicate number '$Canonical' [$Section] $Key`: $Path"
        }
        $Seen[$Canonical] = $true
        $Values.Add($Value) | Out-Null
    }
    if ($ExpectedCount -gt 0 -and $Values.Count -ne $ExpectedCount) {
        throw "Required number list [$Section] $Key must contain $ExpectedCount values: $Path"
    }
    return @($Values)
}

function Get-RequiredLuaMatch([string]$Path, [string]$Pattern, [string]$Symbol) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Balance source is missing: $Path" }
    $Text = [IO.File]::ReadAllText($Path)
    $Options = [Text.RegularExpressions.RegexOptions]::Multiline -bor [Text.RegularExpressions.RegexOptions]::Singleline
    $Match = [regex]::Match($Text, $Pattern, $Options)
    if (-not $Match.Success) {
        throw "Required Lua balance symbol '$Symbol' is missing: $Path"
    }
    return $Match
}

function Get-RequiredLuaInt([string]$Path, [string]$Symbol) {
    $Pattern = '(?m)^local\s+' + [regex]::Escape($Symbol) + '\s*=\s*(\d+)\s*$'
    $Match = Get-RequiredLuaMatch $Path $Pattern $Symbol
    return [int]::Parse($Match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
}

function Get-RequiredLuaNumberText([string]$Path, [string]$Symbol) {
    $Pattern = '(?m)^local\s+' + [regex]::Escape($Symbol) + '\s*=\s*(\d+(?:\.\d+)?)\s*$'
    $Match = Get-RequiredLuaMatch $Path $Pattern $Symbol
    return $Match.Groups[1].Value
}

function Get-RequiredLuaTable([string]$Path, [string]$Symbol, [string]$ValuePattern) {
    $TablePattern = 'local\s+' + [regex]::Escape($Symbol) + '\s*=\s*\{(?<body>.*?)\r?\n\}'
    $Table = Get-RequiredLuaMatch $Path $TablePattern $Symbol
    $Values = [ordered]@{}
    $EntryPattern = '^\s*([A-Za-z0-9_]+)\s*=\s*' + $ValuePattern + '\s*,?\s*$'
    foreach ($Line in ($Table.Groups['body'].Value -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $Entry = [regex]::Match($Line, $EntryPattern)
        if (-not $Entry.Success) {
            throw "Lua balance table '$Symbol' has an unsupported entry: $Path"
        }
        $Key = $Entry.Groups[1].Value
        if ($Values.Contains($Key)) { throw "Duplicate Lua table key '$Key' in $Symbol`: $Path" }
        $Values[$Key] = $Entry.Groups[2].Value
    }
    if ($Values.Count -eq 0) { throw "Lua balance table '$Symbol' is empty: $Path" }
    return $Values
}

function Get-RequiredLuaQuotedArray([string]$Path, [string]$Symbol) {
    $Pattern = 'local\s+' + [regex]::Escape($Symbol) + '\s*=\s*\{(?<body>.*?)\}'
    $Match = Get-RequiredLuaMatch $Path $Pattern $Symbol
    $Values = New-Object System.Collections.Generic.List[string]
    foreach ($Entry in [regex]::Matches($Match.Groups['body'].Value, '"([^"]+)"')) {
        $Values.Add($Entry.Groups[1].Value) | Out-Null
    }
    $Remainder = [regex]::Replace($Match.Groups['body'].Value, '\s*"[^"]+"\s*,?', '')
    if (-not [string]::IsNullOrWhiteSpace($Remainder)) {
        throw "Lua balance array '$Symbol' has an unsupported entry: $Path"
    }
    if ($Values.Count -eq 0) { throw "Lua balance array '$Symbol' is empty: $Path" }
    return @($Values)
}

function Get-RequiredLuaRankTable([string]$Path, [string]$Symbol) {
    $TablePattern = 'local\s+' + [regex]::Escape($Symbol) + '\s*=\s*\{(?<body>.*?)\r?\n\}'
    $Table = Get-RequiredLuaMatch $Path $TablePattern $Symbol
    $Values = [ordered]@{}
    $EntryPattern = '^\s*\{\s*id\s*=\s*"([^"]+)"\s*,\s*cost\s*=\s*(\d+)\s*\}\s*,?\s*$'
    foreach ($Line in ($Table.Groups['body'].Value -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($Line)) { continue }
        $Entry = [regex]::Match($Line, $EntryPattern)
        if (-not $Entry.Success) {
            throw "Lua balance table '$Symbol' has an unsupported entry: $Path"
        }
        $Id = $Entry.Groups[1].Value
        if ($Values.Contains($Id)) { throw "Duplicate Lua rank '$Id' in $Symbol`: $Path" }
        $Values[$Id] = [int]::Parse($Entry.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Values.Count -eq 0) { throw "Lua balance table '$Symbol' is empty: $Path" }
    return $Values
}

function Get-PercentBar([int]$Percent) {
    $Filled = [Math]::Min(10, [Math]::Max(0, [Math]::Floor(($Percent + 5) / 10)))
    return ('#' * $Filled) + ('.' * (10 - $Filled))
}

function Join-MarkdownLines($Lines) {
    return (@($Lines) -join "`n")
}

function Get-SubstringCount([string]$Text, [string]$Value) {
    $Count = 0
    $Offset = 0
    while (($Offset = $Text.IndexOf($Value, $Offset, [StringComparison]::Ordinal)) -ge 0) {
        $Count++
        $Offset += $Value.Length
    }
    return $Count
}

function Set-GeneratedMarkdownBlocks([string]$Document, $Blocks) {
    $Result = $Document.Replace("`r`n", "`n").Replace("`r", "`n")
    $Ranges = New-Object System.Collections.Generic.List[object]
    foreach ($Name in $Blocks.Keys) {
        $Begin = "<!-- BEGIN GENERATED: $Name -->"
        $End = "<!-- END GENERATED: $Name -->"
        if ((Get-SubstringCount $Result $Begin) -ne 1 -or (Get-SubstringCount $Result $End) -ne 1) {
            throw "Generated block markers must exist exactly once: $Name"
        }
        $BeginIndex = $Result.IndexOf($Begin, [StringComparison]::Ordinal)
        $EndIndex = $Result.IndexOf($End, [StringComparison]::Ordinal)
        if ($EndIndex -le $BeginIndex) {
            throw "Generated block markers are reversed: $Name"
        }
        $Ranges.Add([pscustomobject]@{
            Name = $Name
            Begin = $Begin
            End = $End
            BeginIndex = $BeginIndex
            EndIndex = $EndIndex
            EndExclusive = $EndIndex + $End.Length
        }) | Out-Null
    }

    $OrderedRanges = @($Ranges | Sort-Object BeginIndex)
    for ($Index = 1; $Index -lt $OrderedRanges.Count; $Index++) {
        if ($OrderedRanges[$Index - 1].EndExclusive -gt $OrderedRanges[$Index].BeginIndex) {
            throw "Generated block markers overlap or are nested: $($OrderedRanges[$Index - 1].Name), $($OrderedRanges[$Index].Name)"
        }
    }

    foreach ($Range in @($Ranges | Sort-Object BeginIndex -Descending)) {
        $Before = $Result.Substring(0, $Range.BeginIndex + $Range.Begin.Length)
        $After = $Result.Substring($Range.EndIndex)
        $Body = ([string]$Blocks[$Range.Name]).Replace("`r`n", "`n").Replace("`r", "`n").Trim("`n")
        $Result = $Before + "`n" + $Body + "`n" + $After
    }

    $ValidatedRanges = New-Object System.Collections.Generic.List[object]
    foreach ($Name in $Blocks.Keys) {
        $Begin = "<!-- BEGIN GENERATED: $Name -->"
        $End = "<!-- END GENERATED: $Name -->"
        if ((Get-SubstringCount $Result $Begin) -ne 1 -or (Get-SubstringCount $Result $End) -ne 1) {
            throw "Generated block markers were corrupted during replacement: $Name"
        }
        $BeginIndex = $Result.IndexOf($Begin, [StringComparison]::Ordinal)
        $EndIndex = $Result.IndexOf($End, [StringComparison]::Ordinal)
        if ($EndIndex -le $BeginIndex) {
            throw "Generated block markers were reversed during replacement: $Name"
        }
        $ValidatedRanges.Add([pscustomobject]@{
            Name = $Name
            BeginIndex = $BeginIndex
            EndExclusive = $EndIndex + $End.Length
        }) | Out-Null
    }
    $OrderedValidatedRanges = @($ValidatedRanges | Sort-Object BeginIndex)
    for ($Index = 1; $Index -lt $OrderedValidatedRanges.Count; $Index++) {
        if ($OrderedValidatedRanges[$Index - 1].EndExclusive -gt $OrderedValidatedRanges[$Index].BeginIndex) {
            throw "Generated block markers overlap after replacement: $($OrderedValidatedRanges[$Index - 1].Name), $($OrderedValidatedRanges[$Index].Name)"
        }
    }
    if (-not $Result.EndsWith("`n", [StringComparison]::Ordinal)) {
        $Result += "`n"
    }
    return $Result
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$DifficultyPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$LayoutPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$TacticalPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'
$DiscoveryScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
$CatalogScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
$BootstrapScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$GeneratorScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
$MedicalGeneratorScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_medical_generator.script'
$NpcMedicalScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_npc_medical.script'
$TacticalDirectorScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_tactical_director.script'

$Catalog = Read-GammaArenaLtx $CatalogPath
$Difficulties = Read-GammaArenaLtx $DifficultyPath
$Layout = Read-GammaArenaLtx $LayoutPath
$Tactical = Read-GammaArenaLtx $TacticalPath

$DifficultyIds = @('rookie', 'stalker', 'veteran', 'master')
$WeaponWeightKeys = [ordered]@{
    w_pistol = 'weapon_weight_pistol'
    w_smg = 'weapon_weight_smg'
    w_shotgun = 'weapon_weight_shotgun'
    w_rifle = 'weapon_weight_rifle'
    w_sniper = 'weapon_weight_sniper'
}
$ArmorWeightKeys = [ordered]@{
    light = 'armor_weight_light'
    medium = 'armor_weight_medium'
    scientific = 'armor_weight_scientific'
    heavy = 'armor_weight_heavy'
    powered_exo = 'armor_weight_powered_exo'
}
$MedicalWeightKeys = [ordered]@{
    bleed = 'medical_weight_bleed'
    health = 'medical_weight_health'
    boost = 'medical_weight_boost'
    rare = 'medical_weight_rare'
}

$DifficultyModel = New-Object System.Collections.Generic.List[object]
foreach ($DifficultyId in $DifficultyIds) {
    $Section = 'ga_difficulty_' + $DifficultyId
    $WeaponWeights = [ordered]@{}
    foreach ($Class in $WeaponWeightKeys.Keys) {
        $WeaponWeights[$Class] = Get-RequiredLtxInt $Difficulties $Section $WeaponWeightKeys[$Class] $DifficultyPath
    }
    $ArmorWeights = [ordered]@{}
    foreach ($Class in $ArmorWeightKeys.Keys) {
        $ArmorWeights[$Class] = Get-RequiredLtxInt $Difficulties $Section $ArmorWeightKeys[$Class] $DifficultyPath
    }
    if ((($WeaponWeights.Values | Measure-Object -Sum).Sum) -ne 100) {
        throw "Weapon weights must total 100: $Section"
    }
    if ((($ArmorWeights.Values | Measure-Object -Sum).Sum) -ne 100) {
        throw "Armor weights must total 100: $Section"
    }
    $MedicalWeights = [ordered]@{}
    foreach ($Category in $MedicalWeightKeys.Keys) {
        $MedicalWeights[$Category] = Get-RequiredLtxInt $Difficulties $Section $MedicalWeightKeys[$Category] $DifficultyPath
    }
    if ((($MedicalWeights.Values | Measure-Object -Sum).Sum) -ne 100) {
        throw "Medical weights must total 100: $Section"
    }
    $DifficultyModel.Add([pscustomobject]@{
        id = $DifficultyId
        tier = Get-RequiredLtxInt $Difficulties $Section 'tier' $DifficultyPath
        enemy_min = Get-RequiredLtxInt $Difficulties $Section 'enemy_min' $DifficultyPath
        enemy_max = Get-RequiredLtxInt $Difficulties $Section 'enemy_max' $DifficultyPath
        enemy_total_budget = Get-RequiredLtxInt $Difficulties $Section 'enemy_total_budget' $DifficultyPath
        player_gear_budget = Get-RequiredLtxInt $Difficulties $Section 'player_gear_budget' $DifficultyPath
        player_medical_budget = Get-RequiredLtxInt $Difficulties $Section 'player_medical_budget' $DifficultyPath
        primary_share_percent = Get-RequiredLtxInt $Difficulties $Section 'primary_share_percent' $DifficultyPath
        medical_weights = $MedicalWeights
        weapon_weights = $WeaponWeights
        armor_weights = $ArmorWeights
    }) | Out-Null
}

$ProfileIds = @(Get-LtxCsv $Catalog 'profiles' 'ids' $CatalogPath)
$ProfileRanks = Get-RequiredLuaRankTable $CatalogScriptPath 'PROFILE_RANKS'
if ($ProfileIds.Count -ne $ProfileRanks.Count) {
    throw 'PROFILE_RANKS and fallback profile ids must have the same cardinality'
}
$FallbackProfiles = New-Object System.Collections.Generic.List[object]
for ($Index = 0; $Index -lt $ProfileIds.Count; $Index++) {
    $Id = $ProfileIds[$Index]
    if (@($ProfileRanks.Keys)[$Index] -cne $Id) {
        throw "PROFILE_RANKS order differs from fallback profiles at index $Index"
    }
    $Section = 'profile_' + $Id
    $Cost = Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath
    if ($ProfileRanks[$Id] -ne $Cost) {
        throw "PROFILE_RANKS cost differs from fallback profile '$Id'"
    }
    $FallbackProfiles.Add([pscustomobject]@{
        id = $Id
        section = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
        cost = $Cost
    }) | Out-Null
}

$FallbackAmmo = [ordered]@{}
foreach ($Id in Get-LtxCsv $Catalog 'ammo' 'ids' $CatalogPath) {
    $Section = 'ammo_' + $Id
    $GameSection = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
    $FallbackAmmo[$GameSection] = [pscustomobject]@{
        section = $GameSection
        cost = Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath
    }
}

$FallbackWeapons = New-Object System.Collections.Generic.List[object]
foreach ($Id in Get-LtxCsv $Catalog 'weapons' 'ids' $CatalogPath) {
    $Section = 'weapon_' + $Id
    $FallbackWeapons.Add([pscustomobject]@{
        section = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
        ammo = Get-RequiredLtxValue $Catalog $Section 'ammo' $CatalogPath
        cost = Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath
        ammo_box_min = Get-RequiredLtxInt $Catalog $Section 'ammo_box_min' $CatalogPath
        ammo_box_max = Get-RequiredLtxInt $Catalog $Section 'ammo_box_max' $CatalogPath
        kind = Get-RequiredLtxValue $Catalog $Section 'kind' $CatalogPath
        slot = Get-RequiredLtxInt $Catalog $Section 'slot' $CatalogPath
    }) | Out-Null
}

$FallbackOutfits = New-Object System.Collections.Generic.List[object]
foreach ($Id in Get-LtxCsv $Catalog 'outfits' 'ids' $CatalogPath) {
    $Section = 'outfit_' + $Id
    $FallbackOutfits.Add([pscustomobject]@{
        section = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
        cost = Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath
        armor_class = Get-RequiredLtxValue $Catalog $Section 'armor_class' $CatalogPath
    }) | Out-Null
}

$FallbackConsumables = New-Object System.Collections.Generic.List[object]
foreach ($Id in Get-LtxCsv $Catalog 'consumables' 'ids' $CatalogPath) {
    $Section = 'consumable_' + $Id
    $FallbackConsumables.Add([pscustomobject]@{
        id = $Id
        section = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
        cost = Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath
    }) | Out-Null
}
$Bandage = @($FallbackConsumables | Where-Object { $_.id -eq 'bandage' })
if ($Bandage.Count -ne 1) { throw 'Fallback catalog must contain exactly one bandage' }
$BandageCost = $Bandage[0].cost
$MedicalItems = New-Object System.Collections.Generic.List[object]
foreach ($Id in Get-LtxCsv $Catalog 'medical_items' 'ids' $CatalogPath) {
    $Section = 'medical_' + $Id
    $MedicalItems.Add([pscustomobject]@{
        id = $Id
        section = Get-RequiredLtxValue $Catalog $Section 'section' $CatalogPath
        category = Get-RequiredLtxValue $Catalog $Section 'category' $CatalogPath
        actor_cost = Get-RequiredLtxInt $Catalog $Section 'actor_cost' $CatalogPath
        npc_cost = Get-RequiredLtxInt $Catalog $Section 'npc_cost' $CatalogPath
        min_tier = Get-RequiredLtxInt $Catalog $Section 'min_tier' $CatalogPath
        max_count = Get-RequiredLtxInt $Catalog $Section 'max_count' $CatalogPath
    }) | Out-Null
}
if ($MedicalItems.Count -ne 16) { throw 'Curated medical catalog must contain exactly 16 items' }
$KnifeIds = @(Get-LtxCsv $Catalog 'knives' 'ids' $CatalogPath)
if ($KnifeIds.Count -ne 9) { throw 'Fallback knife catalog must contain exactly 9 ids' }
$FallbackKnives = New-Object System.Collections.Generic.List[object]
$KnifeSections = @{}
foreach ($Id in $KnifeIds) {
    $Section = Get-RequiredLtxValue $Catalog ('knife_' + $Id) 'section' $CatalogPath
    if ($KnifeSections.ContainsKey($Section)) { throw "Duplicate fallback knife section '$Section'" }
    $KnifeSections[$Section] = $true
    $FallbackKnives.Add([pscustomobject]@{ id = $Id; section = $Section }) | Out-Null
}
$WeaponClassCosts = Get-RequiredLuaTable $DiscoveryScriptPath 'WEAPON_COST' '(\d+)'
$OutfitKindCosts = Get-RequiredLuaTable $DiscoveryScriptPath 'OUTFIT_COST' '(\d+)'
$OutfitKindClasses = Get-RequiredLuaTable $DiscoveryScriptPath 'OUTFIT_CLASS' '"([^"]+)"'
$PrimaryBandPercent = Get-RequiredLuaInt $GeneratorScriptPath 'PRIMARY_BAND_PERCENT'
$BandThresholdFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+threshold\s*=\s*math\.ceil\(maximum\s*\*\s*PRIMARY_BAND_PERCENT\s*/\s*100\)' 'affordable band formula'
$BandFallbackRule = Get-RequiredLuaMatch $GeneratorScriptPath 'if\s+#band\s*==\s*0\s+then.*?value\.cost\s*==\s*highest' 'affordable band fallback'
$ActorPairWeightFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+weight\s*=\s*weapon_weight\s*\*\s*armor_weight' 'actor class-pair weight formula'
$ActorWeaponPick = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+weapon\s*=\s*stream\(request,\s*fight_index,\s*catalogs,\s*"actor_weapon"\):pick\(weapons\)' 'actor weapon pick'
$ActorAmmoPick = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+ammo_boxes\s*=\s*stream\(request,\s*fight_index,\s*catalogs,\s*"actor_ammo_boxes"\):pick\(boxes\)' 'actor ammo-box pick'
$ActorOutfitPick = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+outfit\s*=\s*stream\(request,\s*fight_index,\s*catalogs,\s*"actor_outfit"\):pick\(outfits\)' 'actor outfit pick'
$RandomKnifeSelection = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+function\s+random_knife\(rng,\s*knives\).*?local\s+choice\s*=\s*rng:pick\(knives\)' 'random knife selection'
$EnemyCountFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+enemy_count\s*=\s*stream\(normalized_request,\s*fight_index,\s*catalogs,\s*"enemy_count"\):next_int\(difficulty\.enemy_min,\s*maximum\)' 'enemy count formula'
$EnemyFactionFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+enemy_faction\s*=\s*stream\(normalized_request,\s*fight_index,\s*catalogs,\s*"enemy_faction"\):pick\(catalogs\.faction_ids\)' 'enemy faction formula'
$PrimaryCountFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+primary_count\s*=\s*math\.ceil\(enemy_count\s*\*\s*difficulty\.primary_share_percent\s*/\s*100\)' 'primary count formula'
$BudgetDivisionFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+base,\s*remainder\s*=\s*math\.floor\(difficulty\.enemy_total_budget\s*/\s*enemy_count\),\s*difficulty\.enemy_total_budget\s*%\s*enemy_count' 'enemy budget division formula'
$SlotBudgetFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+slot_budget\s*=\s*base\s*\+\s*\(index\s*<=\s*remainder\s+and\s+1\s+or\s+0\)' 'enemy slot budget formula'
$OpponentRoleFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+role\s*=\s*index\s*==\s*1\s+and\s+"leader"\s+or\s*\(index\s*<=\s*primary_count\s+and\s+"primary"\s+or\s+"secondary"\)' 'opponent role formula'
$WeaponRoleFormula = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+weapon_role\s*=\s*role\s*==\s*"secondary"\s+and\s+"secondary"\s+or\s+"primary"' 'opponent weapon-role formula'

$PoweredExoRule = Get-RequiredLuaMatch $DiscoveryScriptPath 'armor_class\s*=\s*"powered_exo"' 'powered_exo classification'
$DynamicAmmoCostMatch = Get-RequiredLuaMatch $DiscoveryScriptPath 'local\s+record\s*=\s*\{\s*id\s*=\s*(?<ammo_ref>ammo_section|variant\.section)\s*,\s*section\s*=\s*\k<ammo_ref>\s*,\s*cost\s*=\s*(\d+)\s*\}' 'dynamic ammo cost'
$DynamicAmmoCost = [int]::Parse($DynamicAmmoCostMatch.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
$SniperState = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+sniper_used\s*=\s*false' 'sniper_used initialization'
$SniperFilter = Get-RequiredLuaMatch $GeneratorScriptPath 'sniper_used\s+and\s+weapon\.kind\s*==\s*"w_sniper"' 'sniper_used filter'
$SniperUpdate = Get-RequiredLuaMatch $GeneratorScriptPath 'selected_weapon\.kind\s*==\s*"w_sniper"\s+then\s+sniper_used\s*=\s*true' 'sniper_used update'
$TacticalRoleOrder = Get-RequiredLuaQuotedArray $TacticalDirectorScriptPath 'ROLE_ORDER'
$TacticalStrength = Get-RequiredLuaTable $TacticalDirectorScriptPath 'STRENGTH' '(\d+)'
$RepeatedRoleRule = Get-RequiredLuaMatch $TacticalDirectorScriptPath 'count\s*>\s*4\s+and\s+index\s*%\s*2\s*==\s*1\s+then\s+return\s+"pressure".*?return\s+"flank"' 'repeated tactical role rule'
$ProfileFactions = Get-RequiredLuaQuotedArray $CatalogScriptPath 'PROFILE_FACTIONS'
$PoweredExoChargeAssignment = Get-RequiredLuaMatch $BootstrapScriptPath 'first\.value\.power\s*=\s*100' 'powered exo charge assignment'
$PoweredExoChargeWrite = Get-RequiredLuaMatch $BootstrapScriptPath 'GA_ACTOR_EXO_WRITE_FAILED"\s*,\s*ports\.exo_set_data\s*,\s*outfit\.value\.record\.id\s*,\s*first\.value' 'powered exo charge write'
$PoweredExoChargeVerification = Get-RequiredLuaMatch $BootstrapScriptPath 'verified\.value\.power\s*~=\s*100' 'powered exo charge verification'
$CoreRngEpoch = Get-RequiredLuaInt $GeneratorScriptPath 'CORE_RNG_EPOCH'
$MedicalRngEpoch = Get-RequiredLuaInt $GeneratorScriptPath 'MEDICAL_RNG_EPOCH'
$ActorMedicalMaxItems = Get-RequiredLuaInt $MedicalGeneratorScriptPath 'ACTOR_MAX_ITEMS'
$NpcMedicalEpoch = Get-RequiredLuaInt $NpcMedicalScriptPath 'MEDICAL_EPOCH'
$ReconcileInterval = Get-RequiredLuaInt $NpcMedicalScriptPath 'RECONCILE_INTERVAL_MS'
$HealthThreshold = Get-RequiredLuaNumberText $NpcMedicalScriptPath 'HEALTH_THRESHOLD'
$BleedingThreshold = Get-RequiredLuaNumberText $NpcMedicalScriptPath 'BLEEDING_THRESHOLD'
$MedkitPulses = Get-RequiredLuaInt $NpcMedicalScriptPath 'MEDKIT_PULSES'
$MedkitHealthPerPulse = Get-RequiredLuaNumberText $NpcMedicalScriptPath 'MEDKIT_HEALTH_PER_PULSE'
$MedkitBleedingCap = Get-RequiredLuaNumberText $NpcMedicalScriptPath 'MEDKIT_BLEEDING_CAP'
$BandageBleedingCap = Get-RequiredLuaNumberText $NpcMedicalScriptPath 'BANDAGE_BLEEDING_CAP'
$EnemyMedicalBudgetRule = Get-RequiredLuaMatch $MedicalGeneratorScriptPath 'medical_cost\s*=\s*count' 'enemy medical team budget'
$DelayRanges = [ordered]@{}
foreach ($Profile in @('veteran', 'experienced', 'trainee')) {
    $Delay = Get-RequiredLuaMatch $NpcMedicalScriptPath ('string\.find\(profile,\s*"_' + $Profile + '".*?then\s+return\s+(\d+)\s*,\s*(\d+)\s+end') "$Profile medical delay"
    $DelayRanges[$Profile] = @([int]$Delay.Groups[1].Value, [int]$Delay.Groups[2].Value)
}
$NoviceDelay = Get-RequiredLuaMatch $NpcMedicalScriptPath 'return\s+(\d+)\s*,\s*(\d+)\s*\r?\nend\s*\r?\n\s*local function available_items' 'novice medical delay'
$DelayRanges['novice'] = @([int]$NoviceDelay.Groups[1].Value, [int]$NoviceDelay.Groups[2].Value)

function Test-FallbackPairAffordable($Difficulty, [string]$WeaponClass, [string]$ArmorClass) {
    foreach ($Weapon in $FallbackWeapons) {
        if ($Weapon.kind -ne $WeaponClass -or -not $FallbackAmmo.Contains($Weapon.ammo)) { continue }
        $Ammo = $FallbackAmmo[$Weapon.ammo]
        foreach ($Outfit in $FallbackOutfits) {
            if ($Outfit.armor_class -ne $ArmorClass) { continue }
            for ($Boxes = $Weapon.ammo_box_min; $Boxes -le $Weapon.ammo_box_max; $Boxes++) {
                $Cost = $Weapon.cost + ($Ammo.cost * $Boxes) + $Outfit.cost + $BandageCost
                if ($Cost -le ($Difficulty.player_gear_budget + $BandageCost)) { return $true }
            }
        }
    }
    return $false
}

$Blocks = [ordered]@{}
$Blocks['state-passport'] = @"
| Source | Version |
|---|---|
| Catalog | schema $(Get-RequiredLtxInt $Catalog 'meta' 'schema_version' $CatalogPath) / revision $(Get-RequiredLtxInt $Catalog 'meta' 'revision' $CatalogPath) / generator $(Get-RequiredLtxInt $Catalog 'meta' 'generator_version' $CatalogPath) |
| Difficulties | schema $(Get-RequiredLtxInt $Difficulties 'meta' 'schema_version' $DifficultyPath) / revision $(Get-RequiredLtxInt $Difficulties 'meta' 'revision' $DifficultyPath) |
| Layout | schema $(Get-RequiredLtxInt $Layout 'meta' 'schema_version' $LayoutPath) / revision $(Get-RequiredLtxInt $Layout 'meta' 'revision' $LayoutPath) |
| Tactics | schema $(Get-RequiredLtxInt $Tactical 'meta' 'schema_version' $TacticalPath) / revision $(Get-RequiredLtxInt $Tactical 'meta' 'revision' $TacticalPath) |
"@

$DifficultyLines = New-Object System.Collections.Generic.List[string]
$DifficultyLines.Add('| difficulty | enemy_count | enemy_budget | actor_gear_budget | actor_medical_budget | primary_share |') | Out-Null
$DifficultyLines.Add('|---|---:|---:|---:|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $DifficultyLines.Add("| $($Difficulty.id) | $($Difficulty.enemy_min)-$($Difficulty.enemy_max) | $($Difficulty.enemy_total_budget) | $($Difficulty.player_gear_budget) | $($Difficulty.player_medical_budget) | $($Difficulty.primary_share_percent)% |") | Out-Null
}
$DifficultyLines.Add('') | Out-Null
$DifficultyLines.Add('| weapon_class | rookie | stalker | veteran | master |') | Out-Null
$DifficultyLines.Add('|---|---|---|---|---|') | Out-Null
foreach ($Class in $WeaponWeightKeys.Keys) {
    $Cells = @($DifficultyModel | ForEach-Object {
        $Value = $_.weapon_weights[$Class]
        "$Value% $(Get-PercentBar $Value)"
    }) -join ' | '
    $DifficultyLines.Add("| $Class | $Cells |") | Out-Null
}
$DifficultyLines.Add('') | Out-Null
$DifficultyLines.Add('| armor_class | rookie | stalker | veteran | master |') | Out-Null
$DifficultyLines.Add('|---|---|---|---|---|') | Out-Null
foreach ($Class in $ArmorWeightKeys.Keys) {
    $Cells = @($DifficultyModel | ForEach-Object {
        $Value = $_.armor_weights[$Class]
        "$Value% $(Get-PercentBar $Value)"
    }) -join ' | '
    $DifficultyLines.Add("| $Class | $Cells |") | Out-Null
}
$Blocks['difficulty-dashboard'] = Join-MarkdownLines $DifficultyLines

$MedicalLines = New-Object System.Collections.Generic.List[string]
$MedicalLines.Add('| difficulty | tier | medical_budget | bleed | health | boost | rare |') | Out-Null
$MedicalLines.Add('|---|---:|---:|---:|---:|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $MedicalLines.Add("| $($Difficulty.id) | $($Difficulty.tier) | $($Difficulty.player_medical_budget) | $($Difficulty.medical_weights.bleed)% | $($Difficulty.medical_weights.health)% | $($Difficulty.medical_weights.boost)% | $($Difficulty.medical_weights.rare)% |") | Out-Null
}
$MedicalLines.Add('') | Out-Null
$MedicalLines.Add('| difficulty | budget policy | mandatory items | optional slots | item cap |') | Out-Null
$MedicalLines.Add('|---|---|---|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $MedicalLines.Add("| $($Difficulty.id) | independent $($Difficulty.player_medical_budget) points | bandage + health/rare healer | 3 | $ActorMedicalMaxItems |") | Out-Null
}
$MedicalLines.Add('') | Out-Null
$MedicalLines.Add('| section | category | actor_cost | npc_cost | min_tier | max_count |') | Out-Null
$MedicalLines.Add('|---|---|---:|---:|---:|---:|') | Out-Null
foreach ($Item in $MedicalItems) {
    $MedicalLines.Add("| $($Item.section) | $($Item.category) | $($Item.actor_cost) | $($Item.npc_cost) | $($Item.min_tier) | $($Item.max_count) |") | Out-Null
}
$Blocks['medical-loadouts'] = Join-MarkdownLines $MedicalLines

$NpcMedicalLines = New-Object System.Collections.Generic.List[string]
$NpcMedicalLines.Add('| runtime policy | value |') | Out-Null
$NpcMedicalLines.Add('|---|---|') | Out-Null
$NpcMedicalLines.Add("| reconciliation_period | $ReconcileInterval ms |") | Out-Null
$NpcMedicalLines.Add("| core_rng_epoch | $CoreRngEpoch |") | Out-Null
$NpcMedicalLines.Add("| loadout_medical_rng_epoch | $MedicalRngEpoch |") | Out-Null
$NpcMedicalLines.Add("| npc_action_rng_epoch | $NpcMedicalEpoch |") | Out-Null
$NpcMedicalLines.Add("| health_trigger | < $HealthThreshold |") | Out-Null
$NpcMedicalLines.Add("| bleed_trigger | > $BleedingThreshold |") | Out-Null
$NpcMedicalLines.Add("| medkit_pulses | $MedkitPulses |") | Out-Null
$NpcMedicalLines.Add("| medkit_health_per_pulse | +$MedkitHealthPerPulse |") | Out-Null
$NpcMedicalLines.Add("| medkit_bleeding_cap | $MedkitBleedingCap |") | Out-Null
$NpcMedicalLines.Add("| bandage_bleeding_cap | $BandageBleedingCap |") | Out-Null
$NpcMedicalLines.Add("| actor_item_cap | $ActorMedicalMaxItems |") | Out-Null
$NpcMedicalLines.Add('| enemy_team_medical_budget | opponent_count points |') | Out-Null
$NpcMedicalLines.Add('') | Out-Null
$NpcMedicalLines.Add('| NPC rank | deterministic action delay |') | Out-Null
$NpcMedicalLines.Add('|---|---:|') | Out-Null
foreach ($Profile in @('novice', 'trainee', 'experienced', 'veteran')) {
    $NpcMedicalLines.Add("| $Profile | $($DelayRanges[$Profile][0])-$($DelayRanges[$Profile][1]) ms |") | Out-Null
}
$Blocks['npc-medical-runtime'] = Join-MarkdownLines $NpcMedicalLines

$ActorLines = New-Object System.Collections.Generic.List[string]
$ActorLines.Add('`gear_cost = weapon + ammo_cost * ammo_boxes + outfit`; medicine uses its own budget') | Out-Null
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| installed weapon kind | Arena cost |') | Out-Null
$ActorLines.Add('|---|---:|') | Out-Null
foreach ($Kind in $WeaponClassCosts.Keys) {
    $ActorLines.Add("| $Kind | $($WeaponClassCosts[$Kind]) |") | Out-Null
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| installed outfit kind | Arena cost | emitted armor class |') | Out-Null
$ActorLines.Add('|---|---:|---|') | Out-Null
foreach ($Kind in $OutfitKindCosts.Keys) {
    $ArmorClass = $OutfitKindClasses[$Kind]
    if ($Kind -eq 'o_heavy') { $ArmorClass += '; powered_exo when exo/proto' }
    $ActorLines.Add("| $Kind | $($OutfitKindCosts[$Kind]) | $ArmorClass |") | Out-Null
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| difficulty | affordable fallback pairs | unavailable fallback pairs |') | Out-Null
$ActorLines.Add('|---|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $Eligible = 0
    foreach ($WeaponClass in $WeaponWeightKeys.Keys) {
        foreach ($ArmorClass in $ArmorWeightKeys.Keys) {
            if (Test-FallbackPairAffordable $Difficulty $WeaponClass $ArmorClass) { $Eligible++ }
        }
    }
    $ActorLines.Add("| $($Difficulty.id) | $Eligible / 25 | $(25 - $Eligible) / 25 |") | Out-Null
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| difficulty | weapon_class | affordable armor classes | unavailable armor classes |') | Out-Null
$ActorLines.Add('|---|---|---|---|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    foreach ($WeaponClass in $WeaponWeightKeys.Keys) {
        $Affordable = New-Object System.Collections.Generic.List[string]
        $Unavailable = New-Object System.Collections.Generic.List[string]
        foreach ($ArmorClass in $ArmorWeightKeys.Keys) {
            if (Test-FallbackPairAffordable $Difficulty $WeaponClass $ArmorClass) {
                $Affordable.Add($ArmorClass) | Out-Null
            }
            else {
                $Unavailable.Add($ArmorClass) | Out-Null
            }
        }
        $AffordableText = if ($Affordable.Count -eq 0) { '-' } else { @($Affordable) -join ', ' }
        $UnavailableText = if ($Unavailable.Count -eq 0) { '-' } else { @($Unavailable) -join ', ' }
        $ActorLines.Add("| $($Difficulty.id) | $WeaponClass | $AffordableText | $UnavailableText |") | Out-Null
    }
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| fallback weapon | kind | cost | ammo | boxes |') | Out-Null
$ActorLines.Add('|---|---|---:|---|---:|') | Out-Null
foreach ($Weapon in $FallbackWeapons) {
    $ActorLines.Add("| $($Weapon.section) | $($Weapon.kind) | $($Weapon.cost) | $($Weapon.ammo) | $($Weapon.ammo_box_min)-$($Weapon.ammo_box_max) |") | Out-Null
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| fallback outfit | armor_class | cost |') | Out-Null
$ActorLines.Add('|---|---|---:|') | Out-Null
foreach ($Outfit in $FallbackOutfits) {
    $ActorLines.Add("| $($Outfit.section) | $($Outfit.armor_class) | $($Outfit.cost) |") | Out-Null
}
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| ammunition | Arena cost | source mode |') | Out-Null
$ActorLines.Add('|---|---:|---|') | Out-Null
foreach ($AmmoSection in $FallbackAmmo.Keys) {
    $ActorLines.Add("| $AmmoSection | $($FallbackAmmo[$AmmoSection].cost) | fallback |") | Out-Null
}
$ActorLines.Add("| dynamic discovered ammo | $DynamicAmmoCost | runtime discovery |") | Out-Null
$ActorLines.Add('') | Out-Null
$ActorLines.Add('| extra item | Arena cost | selection |') | Out-Null
$ActorLines.Add('|---|---:|---|') | Out-Null
foreach ($Consumable in $FallbackConsumables) {
    $Selection = if ($Consumable.id -eq 'bandage') { 'medical pool: mandatory actor baseline; NPC-capable' } else { 'medical pool: NPC-capable' }
    $ActorLines.Add("| $($Consumable.section) | $($Consumable.cost) | $Selection |") | Out-Null
}
$ActorLines.Add("| knives | $($FallbackKnives.Count) | no budget cost; uniform section pick |") | Out-Null
$ActorLines.Add("| knife sections | - | $(@($FallbackKnives | ForEach-Object { $_.section }) -join ', ') |") | Out-Null
$Blocks['actor-equipment'] = Join-MarkdownLines $ActorLines

$OpponentLines = New-Object System.Collections.Generic.List[string]
$OpponentLines.Add('| difficulty | opponents | slot budgets | primary incl. leader | secondary |') | Out-Null
$OpponentLines.Add('|---|---:|---|---:|---:|') | Out-Null
$LayoutCapacity = Get-RequiredLtxInt $Layout 'ga_layout_rostok_arena_v1' 'virtual_capacity' $LayoutPath
if ($LayoutCapacity -le 0) { throw 'virtual_capacity must be positive' }
foreach ($Difficulty in $DifficultyModel) {
    $Maximum = [Math]::Min($Difficulty.enemy_max, $LayoutCapacity)
    for ($EnemyCount = $Difficulty.enemy_min; $EnemyCount -le $Maximum; $EnemyCount++) {
        $Base = [Math]::Floor($Difficulty.enemy_total_budget / $EnemyCount)
        $Remainder = $Difficulty.enemy_total_budget % $EnemyCount
        $SlotBudgets = New-Object System.Collections.Generic.List[int]
        for ($Index = 1; $Index -le $EnemyCount; $Index++) {
            $SlotBudgets.Add([int]($Base + $(if ($Index -le $Remainder) { 1 } else { 0 }))) | Out-Null
        }
        if ((($SlotBudgets | Select-Object -Unique).Count) -eq 1) {
            $BudgetText = "$($SlotBudgets[0]) x $EnemyCount"
        }
        else {
            $BudgetText = @($SlotBudgets) -join ', '
        }
        $PrimaryCount = [int][Math]::Ceiling($EnemyCount * $Difficulty.primary_share_percent / 100.0)
        $OpponentLines.Add("| $($Difficulty.id) | $EnemyCount | $BudgetText | $PrimaryCount | $($EnemyCount - $PrimaryCount) |") | Out-Null
    }
}
$OpponentLines.Add('') | Out-Null
$OpponentLines.Add('| profile rank | profile cost |') | Out-Null
$OpponentLines.Add('|---|---:|') | Out-Null
foreach ($Profile in $FallbackProfiles) {
    $OpponentLines.Add("| $($Profile.id) | $($Profile.cost) |") | Out-Null
}
$OpponentLines.Add('') | Out-Null
$OpponentLines.Add('| rule | value |') | Out-Null
$OpponentLines.Add('|---|---:|') | Out-Null
$OpponentLines.Add("| PRIMARY_BAND_PERCENT | $PrimaryBandPercent% |") | Out-Null
$OpponentLines.Add("| selection_band_threshold | ceil(maximum * $PrimaryBandPercent / 100) |") | Out-Null
$OpponentLines.Add('| max_snipers_per_fight | 1 |') | Out-Null
$OpponentLines.Add('| faction_per_fight | 1 |') | Out-Null
$OpponentLines.Add("| supported_factions | $(@($ProfileFactions) -join ', ') |") | Out-Null
$OpponentLines.Add('| opponent_total_cost | profile + gear + assigned medicine |') | Out-Null
$Blocks['opponent-budgets'] = Join-MarkdownLines $OpponentLines

$ArenaLines = New-Object System.Collections.Generic.List[string]
$ArenaLines.Add('| layout parameter | value |') | Out-Null
$ArenaLines.Add('|---|---:|') | Out-Null
$OpponentPaths = @(Get-LtxCsv $Layout 'ga_layout_rostok_arena_v1' 'opponent_spawn_paths' $LayoutPath)
if ($OpponentPaths.Count -ne 6) { throw 'opponent_spawn_paths must contain exactly 6 unique paths' }
$ActorSpawnPath = Get-RequiredLtxValue $Layout 'ga_layout_rostok_arena_v1' 'actor_spawn_path' $LayoutPath
$ActorLookPath = Get-RequiredLtxValue $Layout 'ga_layout_rostok_arena_v1' 'actor_look_path' $LayoutPath
if ($ActorSpawnPath -ceq $ActorLookPath -or $OpponentPaths -ccontains $ActorSpawnPath -or $OpponentPaths -ccontains $ActorLookPath) {
    throw 'actor and opponent layout paths must be unique'
}
$VirtualRadii = @(Get-RequiredLtxNumberList $Layout 'ga_layout_rostok_arena_v1' 'virtual_radii' $LayoutPath 2)
$ArenaLines.Add("| actor_spawn_path | $ActorSpawnPath |") | Out-Null
$ArenaLines.Add("| actor_look_path | $ActorLookPath |") | Out-Null
$ArenaLines.Add("| native_opponent_paths | $($OpponentPaths.Count) |") | Out-Null
$ArenaLines.Add("| virtual_capacity | $LayoutCapacity |") | Out-Null
$VirtualRadiiText = @($VirtualRadii | ForEach-Object { $_.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture) }) -join ', '
$ArenaLines.Add("| virtual_radii | $VirtualRadiiText m |") | Out-Null
foreach ($Key in @('max_height_delta', 'min_opponent_separation', 'min_actor_separation', 'max_base_distance')) {
    $ArenaLines.Add("| $Key | $(Get-RequiredLtxNumber $Layout 'ga_layout_rostok_arena_v1' $Key $LayoutPath) m |") | Out-Null
}
$ArenaLines.Add('') | Out-Null
$ArenaLines.Add('| tactical parameter | value |') | Out-Null
$ArenaLines.Add('|---|---|') | Out-Null
$ArenaLines.Add("| observation_interval_ms | $(Get-RequiredLtxInt $Tactical 'director' 'observation_interval_ms' $TacticalPath) ms |") | Out-Null
$ReportMinimum = Get-RequiredLtxInt $Tactical 'director' 'report_delay_min_ms' $TacticalPath
$ReportMaximum = Get-RequiredLtxInt $Tactical 'director' 'report_delay_max_ms' $TacticalPath
$ArenaLines.Add("| report_delay_ms | $ReportMinimum-$ReportMaximum ms |") | Out-Null
foreach ($Key in @('assignment_dwell_ms', 'visual_aging_ms', 'evidence_expiry_ms', 'hint_delay_ms', 'hint_cooldown_ms')) {
    $ArenaLines.Add("| $Key | $(Get-RequiredLtxInt $Tactical 'director' $Key $TacticalPath) ms |") | Out-Null
}
$ArenaLines.Add("| initial_role_order | $(@($TacticalRoleOrder) -join ' -> ') |") | Out-Null
$ArenaLines.Add('| repeated_role_rule | odd slot: pressure / even slot: flank |') | Out-Null
$ArenaLines.Add('') | Out-Null
$ArenaLines.Add('| tactical evidence | strength |') | Out-Null
$ArenaLines.Add('|---|---:|') | Out-Null
foreach ($Kind in $TacticalStrength.Keys) {
    $ArenaLines.Add("| $Kind | $($TacticalStrength[$Kind]) |") | Out-Null
}
$Blocks['arena-tactics'] = Join-MarkdownLines $ArenaLines

$MinimumFallbackLoadout = $null
foreach ($Weapon in $FallbackWeapons) {
    if (-not $FallbackAmmo.Contains($Weapon.ammo)) { continue }
    $Ammo = $FallbackAmmo[$Weapon.ammo]
    foreach ($Outfit in $FallbackOutfits) {
        $Cost = $Weapon.cost + ($Ammo.cost * $Weapon.ammo_box_min) + $Outfit.cost + $BandageCost
        if ($null -eq $MinimumFallbackLoadout -or $Cost -lt $MinimumFallbackLoadout) {
            $MinimumFallbackLoadout = $Cost
        }
    }
}
if ($null -eq $MinimumFallbackLoadout) { throw 'Fallback catalog has no complete loadout' }

$MinimumProfileCost = $null
foreach ($Profile in $FallbackProfiles) {
    if ($null -eq $MinimumProfileCost -or $Profile.cost -lt $MinimumProfileCost) { $MinimumProfileCost = $Profile.cost }
}

$DiagnosticLines = New-Object System.Collections.Generic.List[string]
$DiagnosticLines.Add('| category | diagnostic | value |') | Out-Null
$DiagnosticLines.Add('|---|---|---|') | Out-Null
$DiagnosticLines.Add("| fact | minimum_fallback_loadout | $MinimumFallbackLoadout budget points |") | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $Required = $Difficulty.enemy_max * ($MinimumProfileCost + $MinimumFallbackLoadout)
    $Margin = $Difficulty.enemy_total_budget - $Required
    $DiagnosticLines.Add("| derived | $($Difficulty.id) max-team feasibility margin | $Margin |") | Out-Null
}
foreach ($Difficulty in $DifficultyModel) {
    $ZeroWeapon = @($WeaponWeightKeys.Keys | Where-Object { $Difficulty.weapon_weights[$_] -eq 0 })
    $ZeroArmor = @($ArmorWeightKeys.Keys | Where-Object { $Difficulty.armor_weights[$_] -eq 0 })
    if ($ZeroWeapon.Count -gt 0) {
        $DiagnosticLines.Add("| fact | $($Difficulty.id) zero-weight weapon classes | $($ZeroWeapon -join ', ') |") | Out-Null
    }
    if ($ZeroArmor.Count -gt 0) {
        $DiagnosticLines.Add("| fact | $($Difficulty.id) zero-weight armor classes | $($ZeroArmor -join ', ') |") | Out-Null
    }
}
for ($Index = 1; $Index -lt $DifficultyModel.Count; $Index++) {
    $Previous = $DifficultyModel[$Index - 1]
    $CurrentDifficulty = $DifficultyModel[$Index]
    $DiagnosticLines.Add("| derived | $($Previous.id) -> $($CurrentDifficulty.id) envelope delta | enemy_budget +$($CurrentDifficulty.enemy_total_budget - $Previous.enemy_total_budget); actor_gear +$($CurrentDifficulty.player_gear_budget - $Previous.player_gear_budget); actor_medical +$($CurrentDifficulty.player_medical_budget - $Previous.player_medical_budget); enemy_max +$($CurrentDifficulty.enemy_max - $Previous.enemy_max); primary_share +$($CurrentDifficulty.primary_share_percent - $Previous.primary_share_percent) pp |") | Out-Null

    $LargestWeaponClass = $null
    $LargestWeaponDelta = 0
    foreach ($Class in $WeaponWeightKeys.Keys) {
        $Delta = $CurrentDifficulty.weapon_weights[$Class] - $Previous.weapon_weights[$Class]
        if ($null -eq $LargestWeaponClass -or [Math]::Abs($Delta) -gt [Math]::Abs($LargestWeaponDelta)) {
            $LargestWeaponClass = $Class
            $LargestWeaponDelta = $Delta
        }
    }
    $WeaponSign = if ($LargestWeaponDelta -gt 0) { '+' } else { '' }
    $DiagnosticLines.Add("| derived | $($Previous.id) -> $($CurrentDifficulty.id) largest weapon-class delta | $LargestWeaponClass $WeaponSign$LargestWeaponDelta pp |") | Out-Null

    $LargestArmorClass = $null
    $LargestArmorDelta = 0
    foreach ($Class in $ArmorWeightKeys.Keys) {
        $Delta = $CurrentDifficulty.armor_weights[$Class] - $Previous.armor_weights[$Class]
        if ($null -eq $LargestArmorClass -or [Math]::Abs($Delta) -gt [Math]::Abs($LargestArmorDelta)) {
            $LargestArmorClass = $Class
            $LargestArmorDelta = $Delta
        }
    }
    $ArmorSign = if ($LargestArmorDelta -gt 0) { '+' } else { '' }
    $DiagnosticLines.Add("| derived | $($Previous.id) -> $($CurrentDifficulty.id) largest armor-class delta | $LargestArmorClass $ArmorSign$LargestArmorDelta pp |") | Out-Null
}
$DiagnosticLines.Add("| fact | layout capacity versus configured maxima | $LayoutCapacity slots; highest configured maximum $((($DifficultyModel | Measure-Object -Property enemy_max -Maximum).Maximum)) |") | Out-Null
$ClippedDifficulties = @($DifficultyModel | Where-Object { $_.enemy_max -gt $LayoutCapacity } | ForEach-Object { $_.id })
$ClippedText = if ($ClippedDifficulties.Count -eq 0) { 'none' } else { $ClippedDifficulties -join ', ' }
$DiagnosticLines.Add("| derived | capacity-clipped difficulties | $ClippedText |") | Out-Null
$DiagnosticLines.Add('| blind_spot | installed merge item cardinality, DPS, penetration, TTK, win rate | runtime measurement |') | Out-Null
$Blocks['balance-diagnostics'] = Join-MarkdownLines $DiagnosticLines

$SourceLines = New-Object System.Collections.Generic.List[string]
$SourceLines.Add('| concern | authoritative source |') | Out-Null
$SourceLines.Add('|---|---|') | Out-Null
$SourceLines.Add('| player class weights and enemy envelopes | `gamma_arena_difficulties.ltx` |') | Out-Null
$SourceLines.Add('| fallback items and costs | `gamma_arena_catalogs.ltx` |') | Out-Null
$SourceLines.Add('| installed item classification and class costs | `gamma_arena_catalog_discovery.script` |') | Out-Null
$SourceLines.Add('| actor/opponent selection and budget allocation | `gamma_arena_generator.script` |') | Out-Null
$SourceLines.Add('| actor and enemy medical allocation | `gamma_arena_medical_generator.script` |') | Out-Null
$SourceLines.Add('| physical NPC medicine use | `gamma_arena_npc_medical.script` |') | Out-Null
$SourceLines.Add('| faction profiles and effective weapon pools | `gamma_arena_catalog.script` |') | Out-Null
$SourceLines.Add('| powered exo full-charge transaction | `gamma_arena_bootstrap.script` |') | Out-Null
$SourceLines.Add('| spawn capacity and separation | `gamma_arena_layouts.ltx` |') | Out-Null
$SourceLines.Add('| tactical timings | `gamma_arena_tactical.ltx` |') | Out-Null
$SourceLines.Add('| tactical roles and evidence strength | `gamma_arena_tactical_director.script` |') | Out-Null
$Blocks['source-map'] = Join-MarkdownLines $SourceLines

if (-not (Test-Path -LiteralPath $DocumentPath)) {
    throw "Arena balance document is missing: $DocumentPath"
}
$Current = [IO.File]::ReadAllText($DocumentPath)
$Expected = Set-GeneratedMarkdownBlocks $Current $Blocks

if ($Verify) {
    if ($Current.Replace("`r`n", "`n").Replace("`r", "`n") -cne $Expected) {
        $ToolInvocation = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$([IO.Path]::GetFullPath($PSCommandPath))`" -RepoRoot `"$RepoRoot`" -DocumentPath `"$DocumentPath`""
        throw "Arena balance document is stale: $DocumentPath. Run: $ToolInvocation"
    }
    Write-Host 'PASS: Arena balance document is current'
    return
}

[IO.File]::WriteAllText($DocumentPath, $Expected, (New-Object Text.UTF8Encoding($false)))
Write-Host "Updated Arena balance document: $DocumentPath"
