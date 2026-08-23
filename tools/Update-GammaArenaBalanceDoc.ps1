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
    return [string]$Ltx[$Section][$Key]
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
    foreach ($Value in (Get-RequiredLtxValue $Ltx $Section $Key $Path).Split(',')) {
        $Trimmed = $Value.Trim()
        if ($Trimmed.Length -eq 0) { throw "Empty list value [$Section] $Key`: $Path" }
        $Values.Add($Trimmed) | Out-Null
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

function Get-RequiredLuaTable([string]$Path, [string]$Symbol, [string]$ValuePattern) {
    $TablePattern = 'local\s+' + [regex]::Escape($Symbol) + '\s*=\s*\{(?<body>.*?)\r?\n\}'
    $Table = Get-RequiredLuaMatch $Path $TablePattern $Symbol
    $Values = [ordered]@{}
    $EntryPattern = '(?m)^\s*([A-Za-z0-9_]+)\s*=\s*' + $ValuePattern + '\s*,?\s*$'
    foreach ($Entry in [regex]::Matches($Table.Groups['body'].Value, $EntryPattern)) {
        $Key = $Entry.Groups[1].Value
        if ($Values.Contains($Key)) { throw "Duplicate Lua table key '$Key' in $Symbol`: $Path" }
        $Values[$Key] = $Entry.Groups[2].Value
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
        $Before = $Result.Substring(0, $BeginIndex + $Begin.Length)
        $After = $Result.Substring($EndIndex)
        $Body = ([string]$Blocks[$Name]).Trim("`r", "`n")
        $Result = $Before + "`n" + $Body + "`n" + $After
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
$GeneratorScriptPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'

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
    $DifficultyModel.Add([pscustomobject]@{
        id = $DifficultyId
        enemy_min = Get-RequiredLtxInt $Difficulties $Section 'enemy_min' $DifficultyPath
        enemy_max = Get-RequiredLtxInt $Difficulties $Section 'enemy_max' $DifficultyPath
        enemy_total_budget = Get-RequiredLtxInt $Difficulties $Section 'enemy_total_budget' $DifficultyPath
        player_loadout_budget = Get-RequiredLtxInt $Difficulties $Section 'player_loadout_budget' $DifficultyPath
        primary_share_percent = Get-RequiredLtxInt $Difficulties $Section 'primary_share_percent' $DifficultyPath
        weapon_weights = $WeaponWeights
        armor_weights = $ArmorWeights
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

$BandageCost = Get-RequiredLtxInt $Catalog 'consumable_bandage' 'cost' $CatalogPath
$WeaponClassCosts = Get-RequiredLuaTable $DiscoveryScriptPath 'WEAPON_COST' '(\d+)'
$OutfitKindCosts = Get-RequiredLuaTable $DiscoveryScriptPath 'OUTFIT_COST' '(\d+)'
$OutfitKindClasses = Get-RequiredLuaTable $DiscoveryScriptPath 'OUTFIT_CLASS' '"([^"]+)"'
$PrimaryBandPercent = Get-RequiredLuaInt $GeneratorScriptPath 'PRIMARY_BAND_PERCENT'

$PoweredExoRule = Get-RequiredLuaMatch $DiscoveryScriptPath 'armor_class\s*=\s*"powered_exo"' 'powered_exo classification'
$SniperState = Get-RequiredLuaMatch $GeneratorScriptPath 'local\s+sniper_used\s*=\s*false' 'sniper_used initialization'
$SniperFilter = Get-RequiredLuaMatch $GeneratorScriptPath 'sniper_used\s+and\s+weapon\.kind\s*==\s*"w_sniper"' 'sniper_used filter'
$SniperUpdate = Get-RequiredLuaMatch $GeneratorScriptPath 'selected_weapon\.kind\s*==\s*"w_sniper"\s+then\s+sniper_used\s*=\s*true' 'sniper_used update'

function Test-FallbackPairAffordable($Difficulty, [string]$WeaponClass, [string]$ArmorClass) {
    foreach ($Weapon in $FallbackWeapons) {
        if ($Weapon.kind -ne $WeaponClass -or -not $FallbackAmmo.Contains($Weapon.ammo)) { continue }
        $Ammo = $FallbackAmmo[$Weapon.ammo]
        foreach ($Outfit in $FallbackOutfits) {
            if ($Outfit.armor_class -ne $ArmorClass) { continue }
            for ($Boxes = $Weapon.ammo_box_min; $Boxes -le $Weapon.ammo_box_max; $Boxes++) {
                $Cost = $Weapon.cost + ($Ammo.cost * $Boxes) + $Outfit.cost + $BandageCost
                if ($Cost -le $Difficulty.player_loadout_budget) { return $true }
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
$DifficultyLines.Add('| difficulty | enemy_count | enemy_budget | actor_budget | primary_share |') | Out-Null
$DifficultyLines.Add('|---|---:|---:|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $DifficultyLines.Add("| $($Difficulty.id) | $($Difficulty.enemy_min)-$($Difficulty.enemy_max) | $($Difficulty.enemy_total_budget) | $($Difficulty.player_loadout_budget) | $($Difficulty.primary_share_percent)% |") | Out-Null
}
$DifficultyLines.Add('') | Out-Null
$DifficultyLines.Add('| difficulty | w_pistol | w_smg | w_shotgun | w_rifle | w_sniper |') | Out-Null
$DifficultyLines.Add('|---|---:|---:|---:|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $DifficultyLines.Add("| $($Difficulty.id) | $($Difficulty.weapon_weights.w_pistol)% | $($Difficulty.weapon_weights.w_smg)% | $($Difficulty.weapon_weights.w_shotgun)% | $($Difficulty.weapon_weights.w_rifle)% | $($Difficulty.weapon_weights.w_sniper)% |") | Out-Null
}
$DifficultyLines.Add('') | Out-Null
$DifficultyLines.Add('| difficulty | light | medium | scientific | heavy | powered_exo |') | Out-Null
$DifficultyLines.Add('|---|---:|---:|---:|---:|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $DifficultyLines.Add("| $($Difficulty.id) | $($Difficulty.armor_weights.light)% | $($Difficulty.armor_weights.medium)% | $($Difficulty.armor_weights.scientific)% | $($Difficulty.armor_weights.heavy)% | $($Difficulty.armor_weights.powered_exo)% |") | Out-Null
}
$DifficultyLines.Add('') | Out-Null
$DifficultyLines.Add('| difficulty | weapon weight bars (10 cells = 100%) | armor weight bars (10 cells = 100%) |') | Out-Null
$DifficultyLines.Add('|---|---|---|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $WeaponBars = @($WeaponWeightKeys.Keys | ForEach-Object { "$_ $($Difficulty.weapon_weights[$_])% $(Get-PercentBar $Difficulty.weapon_weights[$_])" }) -join '; '
    $ArmorBars = @($ArmorWeightKeys.Keys | ForEach-Object { "$_ $($Difficulty.armor_weights[$_])% $(Get-PercentBar $Difficulty.armor_weights[$_])" }) -join '; '
    $DifficultyLines.Add("| $($Difficulty.id) | $WeaponBars | $ArmorBars |") | Out-Null
}
$Blocks['difficulty-dashboard'] = Join-MarkdownLines $DifficultyLines

$ActorLines = New-Object System.Collections.Generic.List[string]
$ActorLines.Add('`loadout_cost = weapon + ammo_cost * ammo_boxes + outfit + bandage`') | Out-Null
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
$ActorLines.Add('| difficulty | affordable fallback class pairs / 25 |') | Out-Null
$ActorLines.Add('|---|---:|') | Out-Null
foreach ($Difficulty in $DifficultyModel) {
    $Eligible = 0
    foreach ($WeaponClass in $WeaponWeightKeys.Keys) {
        foreach ($ArmorClass in $ArmorWeightKeys.Keys) {
            if (Test-FallbackPairAffordable $Difficulty $WeaponClass $ArmorClass) { $Eligible++ }
        }
    }
    $ActorLines.Add("| $($Difficulty.id) | $Eligible / 25 |") | Out-Null
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
$Blocks['actor-equipment'] = Join-MarkdownLines $ActorLines

$OpponentLines = New-Object System.Collections.Generic.List[string]
$OpponentLines.Add('| difficulty | opponents | slot budgets | primary incl. leader | secondary |') | Out-Null
$OpponentLines.Add('|---|---:|---|---:|---:|') | Out-Null
$LayoutCapacity = Get-RequiredLtxInt $Layout 'ga_layout_rostok_arena_v1' 'virtual_capacity' $LayoutPath
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
foreach ($Id in Get-LtxCsv $Catalog 'profiles' 'ids' $CatalogPath) {
    $Section = 'profile_' + $Id
    $OpponentLines.Add("| $Id | $(Get-RequiredLtxInt $Catalog $Section 'cost' $CatalogPath) |") | Out-Null
}
$OpponentLines.Add('') | Out-Null
$OpponentLines.Add('| rule | value |') | Out-Null
$OpponentLines.Add('|---|---:|') | Out-Null
$OpponentLines.Add("| PRIMARY_BAND_PERCENT | $PrimaryBandPercent% |") | Out-Null
$OpponentLines.Add('| max_snipers_per_fight | 1 |') | Out-Null
$OpponentLines.Add('| faction_per_fight | 1 |') | Out-Null
$OpponentLines.Add('| opponent_total_cost | profile + weapon + ammo boxes + outfit + bandage |') | Out-Null
$Blocks['opponent-budgets'] = Join-MarkdownLines $OpponentLines

if (-not (Test-Path -LiteralPath $DocumentPath)) {
    throw "Arena balance document is missing: $DocumentPath"
}
$Current = [IO.File]::ReadAllText($DocumentPath)
$Expected = Set-GeneratedMarkdownBlocks $Current $Blocks

if ($Verify) {
    if ($Current.Replace("`r`n", "`n").Replace("`r", "`n") -cne $Expected) {
        throw "Arena balance document is stale. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Update-GammaArenaBalanceDoc.ps1"
    }
    Write-Host 'PASS: Arena balance document is current'
    exit 0
}

[IO.File]::WriteAllText($DocumentPath, $Expected, (New-Object Text.UTF8Encoding($false)))
Write-Host "Updated Arena balance document: $DocumentPath"
