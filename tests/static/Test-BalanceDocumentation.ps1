[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$ToolPath = Join-Path $RepoRoot 'tools\Update-GammaArenaBalanceDoc.ps1'
if (-not (Test-Path -LiteralPath $ToolPath)) {
    throw 'Arena balance document generator is missing'
}

$RepositoryDocument = [IO.File]::ReadAllText((Join-Path $RepoRoot 'docs\arena-balance.md'))
if (([regex]::Matches($RepositoryDocument, '(?m)^```').Count % 2) -ne 0) {
    throw 'Arena balance document has unbalanced Markdown fences'
}
if (([regex]::Matches($RepositoryDocument, '(?m)^```mermaid$').Count) -ne 1) {
    throw 'Arena balance document must contain exactly one Mermaid diagram'
}
if ($RepositoryDocument -notmatch 'actorLoadout\s*-->\s*spec\["FightSpec v8"\]' -or $RepositoryDocument -match 'FightSpec v[1-7]') {
    throw 'Arena balance generation diagram must identify only FightSpec v8'
}
$Readme = [IO.File]::ReadAllText((Join-Path $RepoRoot 'README.md'))
if ($Readme -notmatch '\[Arena balance dashboard\]\(docs/arena-balance\.md\)') {
    throw 'README does not link the Arena balance dashboard'
}
$StandardSuite = [IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\Test-GammaArena.ps1'))
if ($StandardSuite -notmatch 'Test-BalanceDocumentation\.ps1') {
    throw 'Standard suite does not verify Arena balance documentation'
}

function New-BalanceFixture([string]$SourceRoot) {
    $FixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('gamma-arena-balance-' + [guid]::NewGuid().ToString('N'))
    foreach ($RelativePath in @(
        'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx',
        'src\gamedata\scripts\gamma_arena_catalog_discovery.script',
        'src\gamedata\scripts\gamma_arena_catalog.script',
        'src\gamedata\scripts\gamma_arena_bootstrap.script',
        'src\gamedata\scripts\gamma_arena_item_materializer.script',
        'src\gamedata\scripts\gamma_arena_generator.script',
        'src\gamedata\scripts\gamma_arena_random_generator.script',
        'src\gamedata\scripts\gamma_arena_grenade_generator.script',
        'src\gamedata\scripts\gamma_arena_entity_adapter.script',
        'src\gamedata\scripts\gamma_arena_medical_generator.script',
        'src\gamedata\scripts\gamma_arena_npc_medical.script',
        'src\gamedata\scripts\gamma_arena_tactical_director.script'
    )) {
        $Target = Join-Path $FixtureRoot $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $SourceRoot $RelativePath) -Destination $Target
    }
    $Document = Join-Path $FixtureRoot 'docs\arena-balance.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Document) | Out-Null
    [IO.File]::WriteAllText($Document, @'
# Gamma Arena balance

<!-- BEGIN GENERATED: state-passport -->
<!-- END GENERATED: state-passport -->

<!-- BEGIN GENERATED: difficulty-dashboard -->
<!-- END GENERATED: difficulty-dashboard -->

<!-- BEGIN GENERATED: medical-loadouts -->
<!-- END GENERATED: medical-loadouts -->

<!-- BEGIN GENERATED: grenade-loadouts -->
<!-- END GENERATED: grenade-loadouts -->

<!-- BEGIN GENERATED: npc-medical-runtime -->
<!-- END GENERATED: npc-medical-runtime -->

<!-- BEGIN GENERATED: actor-equipment -->
<!-- END GENERATED: actor-equipment -->

<!-- BEGIN GENERATED: opponent-budgets -->
<!-- END GENERATED: opponent-budgets -->

<!-- BEGIN GENERATED: arena-tactics -->
<!-- END GENERATED: arena-tactics -->

<!-- BEGIN GENERATED: balance-diagnostics -->
<!-- END GENERATED: balance-diagnostics -->

<!-- BEGIN GENERATED: source-map -->
<!-- END GENERATED: source-map -->
'@, (New-Object Text.UTF8Encoding($false)))
    return $FixtureRoot
}

function Get-ExpectedFailureMessage([scriptblock]$Action, [string]$Pattern) {
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return $_.Exception.Message
    }
    throw "Expected failure matching: $Pattern"
}

function Invoke-ExpectedFailure([scriptblock]$Action, [string]$Pattern) {
    Get-ExpectedFailureMessage $Action $Pattern | Out-Null
}

function Get-TestLtxValue([string]$Text, [string]$Section, [string]$Key) {
    $SectionPattern = '(?ms)^\[' + [regex]::Escape($Section) + '\]\s*\r?\n(?<body>.*?)(?=^\[|\z)'
    $SectionMatch = [regex]::Match($Text, $SectionPattern)
    if (-not $SectionMatch.Success) { throw "Test oracle cannot find LTX section: $Section" }
    $KeyPattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*(.*?)\s*$'
    $KeyMatch = [regex]::Match($SectionMatch.Groups['body'].Value, $KeyPattern)
    if (-not $KeyMatch.Success) { throw "Test oracle cannot find LTX key: [$Section] $Key" }
    return $KeyMatch.Groups[1].Value.Trim()
}

function Get-TestLtxCsv([string]$Text, [string]$Section, [string]$Key) {
    return @((Get-TestLtxValue $Text $Section $Key).Split(',') | ForEach-Object { $_.Trim() })
}

function Get-TestGeneratedBlock([string]$DocumentText, [string]$Name) {
    $Pattern = '(?s)<!-- BEGIN GENERATED: ' + [regex]::Escape($Name) + ' -->\s*(.*?)\s*<!-- END GENERATED: ' + [regex]::Escape($Name) + ' -->'
    $Match = [regex]::Match($DocumentText, $Pattern)
    if (-not $Match.Success) { throw "Test oracle cannot find generated block: $Name" }
    return $Match.Groups[1].Value
}

function Get-TestPercentBar([int]$Percent) {
    $Filled = [Math]::Min(10, [Math]::Max(0, [Math]::Floor(($Percent + 5) / 10)))
    return ('#' * $Filled) + ('.' * (10 - $Filled))
}

function Assert-DerivedBalanceInvariants([string]$FixtureRoot, [string]$DocumentText) {
    $DifficultyText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'))
    $CatalogText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'))
    $LayoutText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'))
    $TacticalText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'))
    $GeneratorText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\scripts\gamma_arena_random_generator.script'))
    $TacticalDirectorText = [IO.File]::ReadAllText((Join-Path $FixtureRoot 'src\gamedata\scripts\gamma_arena_tactical_director.script'))
    $DifficultyIds = @('rookie', 'stalker', 'veteran', 'master')
    $WeaponClasses = @('w_pistol', 'w_smg', 'w_shotgun', 'w_rifle', 'w_sniper')
    $ArmorClasses = @('light', 'medium', 'scientific', 'heavy', 'powered_exo')

    $ExpectedTableRows = [ordered]@{
        'state-passport' = 6
        'difficulty-dashboard' = 20
        'medical-loadouts' = 30
        'grenade-loadouts' = 14
        'npc-medical-runtime' = 20
        'actor-equipment' = 73
        'opponent-budgets' = 31
        'arena-tactics' = 33
        'balance-diagnostics' = 21
        'source-map' = 14
    }
    foreach ($BlockName in $ExpectedTableRows.Keys) {
        $Block = Get-TestGeneratedBlock $DocumentText $BlockName
        $Rows = @($Block -split '\r?\n' | Where-Object { $_ -match '^\|' })
        if ($Rows.Count -ne $ExpectedTableRows[$BlockName]) {
            throw "Generated table-row cardinality differs for $BlockName"
        }
    }

    $GrenadeBlock = Get-TestGeneratedBlock $DocumentText 'grenade-loadouts'
    $ActorGrenadeRows = [regex]::Matches($GrenadeBlock, '(?m)^\| actor \| (none|exactly 1|exactly 2) \| (94|5|1)% \|$').Count
    $OpponentGrenadeRows = [regex]::Matches($GrenadeBlock, '(?m)^\| each opponent \| (none|exactly 1) \| (90|10)% \|$').Count
    if ($ActorGrenadeRows -ne 3 -or $OpponentGrenadeRows -ne 2) {
        throw 'Grenade probability matrix differs from 94/5/1 and 90/10'
    }
    $ActorPoolHasSmoke = $GrenadeBlock -match '(?m)^\| actor_pool \| [^\r\n]*grenade_smoke'
    $OpponentPoolHasSmoke = $GrenadeBlock -match '(?m)^\| opponent_pool \| [^\r\n]*grenade_smoke'
    if ($ActorPoolHasSmoke -or $OpponentPoolHasSmoke) {
        throw 'Grenade participant pools do not enforce the complete smoke exclusion'
    }

    $DifficultyBlock = Get-TestGeneratedBlock $DocumentText 'difficulty-dashboard'
    $DifficultyRows = @([regex]::Matches($DifficultyBlock, '(?m)^\| (rookie|stalker|veteran|master) \| (\d+-\d+) \| (\d+) \| (\d+) \| (\d+) \| (\d+)% \|$'))
    if ($DifficultyRows.Count -ne $DifficultyIds.Count) { throw 'Difficulty summary must contain exactly four data rows' }
    $WeightRows = @([regex]::Matches($DifficultyBlock, '(?m)^\| (w_pistol|w_smg|w_shotgun|w_rifle|w_sniper|light|medium|scientific|heavy|powered_exo) \| ([^|]+) \| ([^|]+) \| ([^|]+) \| ([^|]+) \|$'))
    if ($WeightRows.Count -ne ($WeaponClasses.Count + $ArmorClasses.Count)) { throw 'Difficulty weight matrices have unexpected cardinality' }
    if (@($WeightRows | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique).Count -ne $WeightRows.Count) {
        throw 'Difficulty weight matrices contain duplicate class rows'
    }
    $WeaponWeightKeys = @('weapon_weight_pistol', 'weapon_weight_smg', 'weapon_weight_shotgun', 'weapon_weight_rifle', 'weapon_weight_sniper')
    $ArmorWeightKeys = @('armor_weight_light', 'armor_weight_medium', 'armor_weight_scientific', 'armor_weight_heavy', 'armor_weight_powered_exo')
    for ($DifficultyIndex = 0; $DifficultyIndex -lt $DifficultyIds.Count; $DifficultyIndex++) {
        $DifficultyId = $DifficultyIds[$DifficultyIndex]
        $Section = 'ga_difficulty_' + $DifficultyId
        $ExpectedSummary = "| $DifficultyId | $(Get-TestLtxValue $DifficultyText $Section 'enemy_min')-$(Get-TestLtxValue $DifficultyText $Section 'enemy_max') | $(Get-TestLtxValue $DifficultyText $Section 'enemy_total_budget') | $(Get-TestLtxValue $DifficultyText $Section 'player_gear_budget') | $(Get-TestLtxValue $DifficultyText $Section 'player_medical_budget') | $(Get-TestLtxValue $DifficultyText $Section 'primary_share_percent')% |"
        if (@($DifficultyRows | Where-Object { $_.Value -ceq $ExpectedSummary }).Count -ne 1) {
            throw "Difficulty summary differs: $DifficultyId"
        }
        $WeaponTotal = 0
        for ($ClassIndex = 0; $ClassIndex -lt $WeaponClasses.Count; $ClassIndex++) {
            $Value = [int](Get-TestLtxValue $DifficultyText $Section $WeaponWeightKeys[$ClassIndex])
            $WeaponTotal += $Value
            $Cell = "$Value% $(Get-TestPercentBar $Value)"
            $Row = @($WeightRows | Where-Object { $_.Groups[1].Value -eq $WeaponClasses[$ClassIndex] })
            if ($Row.Count -ne 1 -or $Row[0].Groups[$DifficultyIndex + 2].Value.Trim() -cne $Cell) {
                throw "Weapon weight cell differs: $DifficultyId/$($WeaponClasses[$ClassIndex])"
            }
        }
        if ($WeaponTotal -ne 100) { throw "Source weapon weights do not total 100: $DifficultyId" }
        $ArmorTotal = 0
        for ($ClassIndex = 0; $ClassIndex -lt $ArmorClasses.Count; $ClassIndex++) {
            $Value = [int](Get-TestLtxValue $DifficultyText $Section $ArmorWeightKeys[$ClassIndex])
            $ArmorTotal += $Value
            $Cell = "$Value% $(Get-TestPercentBar $Value)"
            $Row = @($WeightRows | Where-Object { $_.Groups[1].Value -eq $ArmorClasses[$ClassIndex] })
            if ($Row.Count -ne 1 -or $Row[0].Groups[$DifficultyIndex + 2].Value.Trim() -cne $Cell) {
                throw "Armor weight cell differs: $DifficultyId/$($ArmorClasses[$ClassIndex])"
            }
        }
        if ($ArmorTotal -ne 100) { throw "Source armor weights do not total 100: $DifficultyId" }
    }

    $OpponentBlock = Get-TestGeneratedBlock $DocumentText 'opponent-budgets'
    $OpponentRows = @([regex]::Matches($OpponentBlock, '(?m)^\| (rookie|stalker|veteran|master) \| (\d+) \| ([^|]+?) \| (\d+) \| (\d+) \|$'))
    $ExpectedOpponentRows = 0
    $Capacity = [int](Get-TestLtxValue $LayoutText 'ga_layout_rostok_arena_v1' 'virtual_capacity')
    foreach ($DifficultyId in $DifficultyIds) {
        $Section = 'ga_difficulty_' + $DifficultyId
        $Minimum = [int](Get-TestLtxValue $DifficultyText $Section 'enemy_min')
        $Maximum = [Math]::Min([int](Get-TestLtxValue $DifficultyText $Section 'enemy_max'), $Capacity)
        $TotalBudget = [int](Get-TestLtxValue $DifficultyText $Section 'enemy_total_budget')
        $PrimaryShare = [int](Get-TestLtxValue $DifficultyText $Section 'primary_share_percent')
        for ($EnemyCount = $Minimum; $EnemyCount -le $Maximum; $EnemyCount++) {
            $ExpectedOpponentRows++
            $Rows = @($OpponentRows | Where-Object { $_.Groups[1].Value -eq $DifficultyId -and [int]$_.Groups[2].Value -eq $EnemyCount })
            if ($Rows.Count -ne 1) { throw "Expected one generated opponent row for $DifficultyId/$EnemyCount" }
            $BudgetText = $Rows[0].Groups[3].Value.Trim()
            if ($BudgetText -match '^(\d+) x (\d+)$') {
                $Budgets = @(1..([int]$Matches[2]) | ForEach-Object { [int]$Matches[1] })
            }
            else {
                $Budgets = @($BudgetText.Split(',') | ForEach-Object { [int]$_.Trim() })
            }
            if ($Budgets.Count -ne $EnemyCount) { throw "Slot-budget cardinality differs for $DifficultyId/$EnemyCount" }
            if ((($Budgets | Measure-Object -Sum).Sum) -ne $TotalBudget) { throw "Slot budgets do not sum to the configured total for $DifficultyId/$EnemyCount" }
            if ((($Budgets | Measure-Object -Maximum).Maximum - ($Budgets | Measure-Object -Minimum).Minimum) -gt 1) {
                throw "Slot budgets differ by more than one for $DifficultyId/$EnemyCount"
            }
            $ExpectedPrimary = [int][Math]::Ceiling($EnemyCount * $PrimaryShare / 100.0)
            if ([int]$Rows[0].Groups[4].Value -ne $ExpectedPrimary -or [int]$Rows[0].Groups[5].Value -ne ($EnemyCount - $ExpectedPrimary)) {
                throw "Generated role counts differ for $DifficultyId/$EnemyCount"
            }
        }
    }
    if ($OpponentRows.Count -ne $ExpectedOpponentRows) { throw 'Generated opponent-budget table contains unexpected rows' }

    $AmmoCosts = @{}
    foreach ($Id in Get-TestLtxCsv $CatalogText 'ammo' 'ids') {
        $Section = 'ammo_' + $Id
        $AmmoCosts[(Get-TestLtxValue $CatalogText $Section 'section')] = [int](Get-TestLtxValue $CatalogText $Section 'cost')
    }
    $Weapons = @(foreach ($Id in Get-TestLtxCsv $CatalogText 'weapons' 'ids') {
        $Section = 'weapon_' + $Id
        [pscustomobject]@{
            ammo = Get-TestLtxValue $CatalogText $Section 'ammo'
            cost = [int](Get-TestLtxValue $CatalogText $Section 'cost')
            ammo_box_min = [int](Get-TestLtxValue $CatalogText $Section 'ammo_box_min')
            ammo_box_max = [int](Get-TestLtxValue $CatalogText $Section 'ammo_box_max')
            kind = Get-TestLtxValue $CatalogText $Section 'kind'
        }
    })
    $Outfits = @(foreach ($Id in Get-TestLtxCsv $CatalogText 'outfits' 'ids') {
        $Section = 'outfit_' + $Id
        [pscustomobject]@{
            cost = [int](Get-TestLtxValue $CatalogText $Section 'cost')
            armor_class = Get-TestLtxValue $CatalogText $Section 'armor_class'
        }
    })
    $BandageCost = [int](Get-TestLtxValue $CatalogText 'consumable_bandage' 'cost')
    $ActorBlock = Get-TestGeneratedBlock $DocumentText 'actor-equipment'
    $AmmoChanceTable = [regex]::Match($GeneratorText, '(?s)local\s+PLAYER_AMMO_CHANCE\s*=\s*\{(?<body>.*?)\r?\n\}')
    if (-not $AmmoChanceTable.Success) { throw 'Test oracle cannot find PLAYER_AMMO_CHANCE' }
    $AmmoChanceEntries = @([regex]::Matches($AmmoChanceTable.Groups['body'].Value, '(?m)^\s*(w_pistol|w_smg|w_shotgun|w_rifle|w_sniper)\s*=\s*(\d+)\s*,?\s*$'))
    if ($AmmoChanceEntries.Count -ne $WeaponClasses.Count) { throw 'PLAYER_AMMO_CHANCE has unexpected cardinality' }
    $AmmoScaleRows = @([regex]::Matches($ActorBlock, '(?m)^\| (w_pistol|w_smg|w_shotgun|w_rifle|w_sniper) \| (\d+)% \| 1 \| 1\.\.N\+1 \| ([\d.]+) \| ([\d.]+) \| ([\d.]+) \| ([\d.]+) \|$'))
    if ($AmmoScaleRows.Count -ne $WeaponClasses.Count) { throw 'Player ammo scaling table has unexpected cardinality' }
    foreach ($Entry in $AmmoChanceEntries) {
        $Kind = $Entry.Groups[1].Value
        $Chance = [int]$Entry.Groups[2].Value
        $Row = @($AmmoScaleRows | Where-Object { $_.Groups[1].Value -eq $Kind })
        if ($Row.Count -ne 1 -or [int]$Row[0].Groups[2].Value -ne $Chance) {
            throw "Player ammo scaling chance differs: $Kind"
        }
        for ($Index = 0; $Index -lt 4; $Index++) {
            $OpponentCount = @(1, 5, 20, 100)[$Index]
            $Actual = [double]::Parse($Row[0].Groups[$Index + 3].Value, [Globalization.CultureInfo]::InvariantCulture)
            $Expected = 1 + $OpponentCount * $Chance / 100.0
            if ([Math]::Abs($Actual - $Expected) -gt 0.000001) {
                throw "Player ammo scaling expectation differs: $Kind/N=$OpponentCount"
            }
        }
    }
    $ActorPairRows = @([regex]::Matches($ActorBlock, '(?m)^\| (rookie|stalker|veteran|master) \| (w_pistol|w_smg|w_shotgun|w_rifle|w_sniper) \| ([^|]+) \| ([^|]+) \|$'))
    if ($ActorPairRows.Count -ne ($DifficultyIds.Count * $WeaponClasses.Count)) { throw 'Fallback pair matrix has unexpected cardinality' }
    $ActorCountRows = @([regex]::Matches($ActorBlock, '(?m)^\| (rookie|stalker|veteran|master) \| (\d+) / 25 \| (\d+) / 25 \|$'))
    if ($ActorCountRows.Count -ne $DifficultyIds.Count) { throw 'Fallback pair totals have unexpected cardinality' }
    foreach ($DifficultyId in $DifficultyIds) {
        $ActorBudget = [int](Get-TestLtxValue $DifficultyText ('ga_difficulty_' + $DifficultyId) 'player_gear_budget') + $BandageCost
        $TotalAffordable = 0
        foreach ($WeaponClass in $WeaponClasses) {
            $Affordable = New-Object System.Collections.Generic.List[string]
            $Unavailable = New-Object System.Collections.Generic.List[string]
            foreach ($ArmorClass in $ArmorClasses) {
                $PairAffordable = $false
                foreach ($Weapon in @($Weapons | Where-Object { $_.kind -eq $WeaponClass -and $AmmoCosts.ContainsKey($_.ammo) })) {
                    foreach ($Outfit in @($Outfits | Where-Object { $_.armor_class -eq $ArmorClass })) {
                        for ($Boxes = $Weapon.ammo_box_min; $Boxes -le $Weapon.ammo_box_max; $Boxes++) {
                            if (($Weapon.cost + $AmmoCosts[$Weapon.ammo] * $Boxes + $Outfit.cost + $BandageCost) -le $ActorBudget) {
                                $PairAffordable = $true
                            }
                        }
                    }
                }
                if ($PairAffordable) { $Affordable.Add($ArmorClass) | Out-Null; $TotalAffordable++ }
                else { $Unavailable.Add($ArmorClass) | Out-Null }
            }
            $AffordableText = if ($Affordable.Count -eq 0) { '-' } else { @($Affordable) -join ', ' }
            $UnavailableText = if ($Unavailable.Count -eq 0) { '-' } else { @($Unavailable) -join ', ' }
            $PairRows = @($ActorPairRows | Where-Object { $_.Groups[1].Value -eq $DifficultyId -and $_.Groups[2].Value -eq $WeaponClass })
            if ($PairRows.Count -ne 1 -or $PairRows[0].Groups[3].Value.Trim() -cne $AffordableText -or $PairRows[0].Groups[4].Value.Trim() -cne $UnavailableText) {
                throw "Fallback pair matrix differs: $DifficultyId/$WeaponClass"
            }
        }
        $CountRows = @($ActorCountRows | Where-Object { $_.Groups[1].Value -eq $DifficultyId })
        if ($CountRows.Count -ne 1 -or [int]$CountRows[0].Groups[2].Value -ne $TotalAffordable -or [int]$CountRows[0].Groups[3].Value -ne (25 - $TotalAffordable)) {
            throw "Fallback pair totals differ: $DifficultyId"
        }
    }

    $ArenaBlock = Get-TestGeneratedBlock $DocumentText 'arena-tactics'
    $ExpectedArenaRows = New-Object System.Collections.Generic.List[string]
    $LayoutSection = 'ga_layout_rostok_arena_v1'
    $ExpectedArenaRows.Add("| actor_spawn_path | $(Get-TestLtxValue $LayoutText $LayoutSection 'actor_spawn_path') |") | Out-Null
    $ExpectedArenaRows.Add("| actor_look_path | $(Get-TestLtxValue $LayoutText $LayoutSection 'actor_look_path') |") | Out-Null
    $ExpectedArenaRows.Add("| native_opponent_paths | $(@(Get-TestLtxCsv $LayoutText $LayoutSection 'opponent_spawn_paths').Count) |") | Out-Null
    $ExpectedArenaRows.Add("| virtual_capacity | $(Get-TestLtxValue $LayoutText $LayoutSection 'virtual_capacity') |") | Out-Null
    $Radii = @(Get-TestLtxCsv $LayoutText $LayoutSection 'virtual_radii') -join ', '
    $ExpectedArenaRows.Add("| virtual_radii | $Radii m |") | Out-Null
    foreach ($Key in @('max_height_delta', 'min_opponent_separation', 'min_actor_separation', 'max_base_distance')) {
        $Value = [double]::Parse((Get-TestLtxValue $LayoutText $LayoutSection $Key), [Globalization.CultureInfo]::InvariantCulture)
        $ExpectedArenaRows.Add("| $Key | $($Value.ToString('0.################', [Globalization.CultureInfo]::InvariantCulture)) m |") | Out-Null
    }
    $ExpectedArenaRows.Add("| observation_interval_ms | $(Get-TestLtxValue $TacticalText 'director' 'observation_interval_ms') ms |") | Out-Null
    $ExpectedArenaRows.Add("| report_delay_ms | $(Get-TestLtxValue $TacticalText 'director' 'report_delay_min_ms')-$(Get-TestLtxValue $TacticalText 'director' 'report_delay_max_ms') ms |") | Out-Null
    foreach ($Key in @('assignment_dwell_ms', 'visual_aging_ms', 'evidence_expiry_ms', 'hint_delay_ms', 'hint_cooldown_ms')) {
        $ExpectedArenaRows.Add("| $Key | $(Get-TestLtxValue $TacticalText 'director' $Key) ms |") | Out-Null
    }
    $RoleOrderMatch = [regex]::Match($TacticalDirectorText, '(?m)^local\s+ROLE_ORDER\s*=\s*\{(?<body>.*?)\}\s*$')
    if (-not $RoleOrderMatch.Success) { throw 'Test oracle cannot find ROLE_ORDER' }
    $RoleOrder = @([regex]::Matches($RoleOrderMatch.Groups['body'].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $ExpectedArenaRows.Add("| initial_role_order | $($RoleOrder -join ' -> ') |") | Out-Null
    $ExpectedArenaRows.Add('| repeated_role_rule | odd slot: pressure / even slot: flank |') | Out-Null
    $StrengthMatch = [regex]::Match($TacticalDirectorText, '(?s)local\s+STRENGTH\s*=\s*\{(?<body>.*?)\r?\n\}')
    if (-not $StrengthMatch.Success) { throw 'Test oracle cannot find STRENGTH' }
    $StrengthEntries = @([regex]::Matches($StrengthMatch.Groups['body'].Value, '(?m)^\s*([A-Za-z0-9_]+)\s*=\s*(\d+)\s*,?\s*$'))
    foreach ($Entry in $StrengthEntries) {
        $ExpectedArenaRows.Add("| $($Entry.Groups[1].Value) | $($Entry.Groups[2].Value) |") | Out-Null
    }
    if ($ExpectedArenaRows.Count -ne 27 -or $StrengthEntries.Count -ne 9) { throw 'Arena/tactical source oracle has unexpected cardinality' }
    foreach ($ExpectedRow in $ExpectedArenaRows) {
        if ([regex]::Matches($ArenaBlock, '(?m)^' + [regex]::Escape($ExpectedRow) + '$').Count -ne 1) {
            throw "Arena/tactical row differs or is duplicated: $ExpectedRow"
        }
    }
}

$Fixture = New-BalanceFixture $RepoRoot
try {
    $Document = Join-Path $Fixture 'docs\arena-balance.md'
    & $ToolPath -RepoRoot $Fixture
    $First = [IO.File]::ReadAllText($Document)
    if ($First.Contains("`r")) {
        throw 'Generated Arena balance Markdown must use LF line endings only'
    }
    & $ToolPath -RepoRoot $RepoRoot -Verify
    foreach ($Expected in @(
        '| Catalog | schema 9 / revision 10 / generator 10 |',
        '| Difficulties | schema 4 / revision 5 |',
        '| Layout | schema 2 / revision 2 |',
        '| Tactics | schema 1 / revision 1 |',
        '| rookie | 2-3 | 25 | 7 | 4 | 50% |',
        '| master | 7-10 | 100 | 15 | 8 | 80% |',
        '| bandage | bleed | 1 | 1 | 1 | 2 |',
        '| rebirth | rare | 7 | 0 | 4 | 1 |',
        '| rookie | 1 | 4 | 35% | 50% | 15% | 0% |',
        '| reconciliation_period | 250 ms |',
        '| health_trigger | < 0.60 |',
        '| bleed_trigger | > 0.15 |',
        '| core_rng_epoch | 6 |',
        '| loadout_medical_rng_epoch | 1 |',
        '| npc_action_rng_epoch | 1 |',
        '| novice | 2000-2500 ms |',
        '| veteran | 500-1000 ms |',
        '| w_pistol | 50% #####..... | 25% ###....... | 10% #......... | 5% #......... |',
        '| powered_exo | 0% .......... | 1% .......... | 5% #......... | 5% #......... |',
        '| rookie | 4 / 25 | 21 / 25 |',
        '| master | 12 / 25 | 13 / 25 |',
        '| rookie | w_pistol | light, medium, scientific | heavy, powered_exo |',
        '| w_pistol | 2 |',
        '`gear_cost = weapon + ammo_cost * budgeted_boxes + outfit`; scaled ordinary boxes and medicine are outside this budget',
        '`scaled_boxes = 1 + independent success per opponent`; deterministic stream `actor_scaled_ammo:<index>`, range `1..N+1`, no balance ceiling',
        '`final ammo_boxes = max(budgeted_boxes, ceil(3 * magazine_size / box_size)) + scaled_boxes`; FightSpec stores only this final value',
        '| w_pistol | 40% | 1 | 1..N+1 | 1.4 | 3 | 9 | 41 |',
        '| w_smg | 25% | 1 | 1..N+1 | 1.25 | 2.25 | 6 | 26 |',
        '| w_shotgun | 25% | 1 | 1..N+1 | 1.25 | 2.25 | 6 | 26 |',
        '| w_rifle | 20% | 1 | 1..N+1 | 1.2 | 2 | 5 | 21 |',
        '| w_sniper | 10% | 1 | 1..N+1 | 1.1 | 1.5 | 3 | 11 |',
        '| o_heavy | 5 | heavy; powered_exo when exo/proto |',
        '| ammo_5.45x39_fmj | 2 | fallback |',
        '| dynamic discovered ammo | 1 | runtime discovery |',
        '| medkit | 2 | medical pool: NPC-capable |',
        '| knives | 9 | no budget cost; uniform section pick |',
        '| knife sections | - | wpn_knife, wpn_knife2, wpn_knife3, wpn_knife4, wpn_knife5, wpn_knife6, wpn_knife7, wpn_knife8, wpn_knife9 |',
        '| actor | none | 94% |',
        '| actor | exactly 1 | 5% |',
        '| actor | exactly 2 | 1% |',
        '| each opponent | none | 90% |',
        '| each opponent | exactly 1 | 10% |',
        '| actor_pool | grenade_f1, grenade_rgd5, grenade_gd-05 |',
        '| opponent_pool | grenade_f1, grenade_rgd5, grenade_gd-05 |',
        '| two_actor_picks | independent; duplicates allowed |',
        '| budget_cost | 0; outside gear and medical budgets |',
        '| NPC use | physical possession required; native AI decides whether to throw |',
        '| master | 7 | 15, 15, 14, 14, 14, 14, 14 | 6 | 1 |',
        '| master | 10 | 10 x 10 | 8 | 2 |',
        '| PRIMARY_BAND_PERCENT | 70% |',
        '| selection_band_threshold | ceil(maximum * 70 / 100) |',
        '| max_snipers_per_fight | 1 |',
        '| supported_factions | army, bandit, csky, dolg, ecolog, freedom, killer, monolith, stalker |',
        '| appearance_reproducibility | deferred; X-Ray `specific_character` is not seeded or stored in FightSpec v8 |',
        '| appearance_gameplay_effect | none; faction, rank, equipment, budget, and combat rules remain authoritative |',
        '| deterministic_appearance_follow_up | cataloged appearance aliases + fingerprint/validator membership + catalog identity advance |',
        '| native_opponent_paths | 6 |',
        '| virtual_capacity | 10 |',
        '| virtual_radii | 1.5, 2.5 m |',
        '| observation_interval_ms | 500 ms |',
        '| report_delay_ms | 1000-3000 ms |',
        '| initial_role_order | pressure -> flank -> support -> anchor |',
        '| minimum_fallback_loadout | 5 budget points |',
        '| derived | master max-team feasibility margin | 40 |',
        '| derived | rookie -> stalker largest weapon-class delta | w_pistol -25 pp |',
        '| derived | capacity-clipped difficulties | none |',
        '| blind_spot | installed merge item cardinality, DPS, penetration, TTK, win rate | runtime measurement |',
        '| player class weights and enemy envelopes | `gamma_arena_difficulties.ltx` |',
        '| grenade probabilities and participant pools | `gamma_arena_grenade_generator.script`; `gamma_arena_catalogs.ltx` |',
        '| powered exo full-charge transaction | `gamma_arena_bootstrap.script` |'
    )) {
        if (-not $First.Contains($Expected)) {
            throw "Generated state passport is missing: $Expected"
        }
    }
    Assert-DerivedBalanceInvariants $Fixture $First

    & $ToolPath -RepoRoot $Fixture
    $Second = [IO.File]::ReadAllText($Document)
    if ($First -cne $Second) { throw 'Arena balance document generation is not idempotent' }

    & $ToolPath -RepoRoot $Fixture -Verify

    $Stale = $Second.Replace('Catalog | schema 9 /', 'Catalog | schema 999 /')
    [IO.File]::WriteAllText($Document, $Stale, (New-Object Text.UTF8Encoding($false)))
    $StaleMessage = Get-ExpectedFailureMessage { & $ToolPath -RepoRoot $Fixture -Verify } 'Update-GammaArenaBalanceDoc\.ps1'
    if (-not $StaleMessage.Contains([IO.Path]::GetFullPath($Document)) -or
        -not $StaleMessage.Contains("-RepoRoot `"$([IO.Path]::GetFullPath($Fixture))`"") -or
        -not $StaleMessage.Contains("-DocumentPath `"$([IO.Path]::GetFullPath($Document))`"")) {
        throw 'Stale-document error does not include the target and exact regeneration arguments'
    }
    & $ToolPath -RepoRoot $Fixture

    $Valid = [IO.File]::ReadAllText($Document)
    [IO.File]::WriteAllText(
        $Document,
        $Valid + "<!-- BEGIN GENERATED: state-passport -->`n",
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'markers must exist exactly once'

    $Nested = @'
# Gamma Arena balance

<!-- BEGIN GENERATED: difficulty-dashboard -->
<!-- BEGIN GENERATED: state-passport -->
<!-- END GENERATED: state-passport -->
<!-- END GENERATED: difficulty-dashboard -->
<!-- BEGIN GENERATED: medical-loadouts -->
<!-- END GENERATED: medical-loadouts -->
<!-- BEGIN GENERATED: grenade-loadouts -->
<!-- END GENERATED: grenade-loadouts -->
<!-- BEGIN GENERATED: npc-medical-runtime -->
<!-- END GENERATED: npc-medical-runtime -->
<!-- BEGIN GENERATED: actor-equipment -->
<!-- END GENERATED: actor-equipment -->
<!-- BEGIN GENERATED: opponent-budgets -->
<!-- END GENERATED: opponent-budgets -->
<!-- BEGIN GENERATED: arena-tactics -->
<!-- END GENERATED: arena-tactics -->
<!-- BEGIN GENERATED: balance-diagnostics -->
<!-- END GENERATED: balance-diagnostics -->
<!-- BEGIN GENERATED: source-map -->
<!-- END GENERATED: source-map -->
'@
    [IO.File]::WriteAllText($Document, $Nested, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'overlap|nested'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Nested generated markers partially rewrote the document'
    }

    $Reversed = [regex]::Replace(
        $Valid,
        '(?s)<!-- BEGIN GENERATED: source-map -->.*?<!-- END GENERATED: source-map -->',
        "<!-- END GENERATED: source-map -->`n<!-- BEGIN GENERATED: source-map -->"
    )
    [IO.File]::WriteAllText($Document, $Reversed, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'markers are reversed'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Reversed generated markers partially rewrote the document'
    }

    [IO.File]::WriteAllText($Document, $Valid, (New-Object Text.UTF8Encoding($false)))
    $Difficulty = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
    $DifficultyOriginal = [IO.File]::ReadAllText($Difficulty)
    [IO.File]::AppendAllText($Difficulty, "`n[meta]`nrevision = 4`n")
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'duplicate section'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed balance source partially rewrote the document'
    }

    [IO.File]::WriteAllText($Difficulty, $DifficultyOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $DifficultyChanged = $DifficultyOriginal.Replace('enemy_total_budget = 100', 'enemy_total_budget = 101')
    [IO.File]::WriteAllText($Difficulty, $DifficultyChanged, (New-Object Text.UTF8Encoding($false)))
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'

    [IO.File]::WriteAllText($Difficulty, $DifficultyOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture

    $Layout = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
    $LayoutOriginal = [IO.File]::ReadAllText($Layout)
    [IO.File]::WriteAllText(
        $Layout,
        $LayoutOriginal.Replace('virtual_capacity = 10', 'virtual_capacity = 9'),
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'
    & $ToolPath -RepoRoot $Fixture
    $CapacityLimited = [IO.File]::ReadAllText($Document)
    if (-not $CapacityLimited.Contains('| derived | master max-team feasibility margin | 40 |')) {
        throw 'Configured max-team feasibility margin was incorrectly clipped by runtime capacity'
    }
    if (-not $CapacityLimited.Contains('| derived | capacity-clipped difficulties | master |')) {
        throw 'Runtime capacity clipping is not reported separately'
    }

    [IO.File]::WriteAllText($Layout, $LayoutOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $Tactical = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx'
    $TacticalOriginal = [IO.File]::ReadAllText($Tactical)
    [IO.File]::WriteAllText(
        $Tactical,
        $TacticalOriginal.Replace('observation_interval_ms = 500', 'observation_interval_ms = 501'),
        (New-Object Text.UTF8Encoding($false))
    )
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'

    [IO.File]::WriteAllText($Tactical, $TacticalOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture

    $Discovery = Join-Path $Fixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
    $DiscoveryOriginal = [IO.File]::ReadAllText($Discovery)
    $DiscoveryChanged = $DiscoveryOriginal.Replace('w_sniper = 6', 'w_sniper = 3 + 3')
    [IO.File]::WriteAllText($Discovery, $DiscoveryChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'WEAPON_COST'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed Lua balance table partially rewrote the document'
    }

    [IO.File]::WriteAllText($Discovery, $DiscoveryOriginal, (New-Object Text.UTF8Encoding($false)))
    $DynamicAmmoIdentityChanged = $DiscoveryOriginal.Replace(
        'local record = { id = variant.section, section = variant.section, cost = 1 }',
        'local record = { id = variant.section, section = ammo_section, cost = 1 }'
    )
    if ($DynamicAmmoIdentityChanged -ceq $DiscoveryOriginal) {
        throw 'Dynamic ammo identity fixture did not match production source'
    }
    [IO.File]::WriteAllText($Discovery, $DynamicAmmoIdentityChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'dynamic ammo cost'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Mismatched dynamic ammo identity partially rewrote the document'
    }

    [IO.File]::WriteAllText($Discovery, $DiscoveryOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture

    $CatalogScript = Join-Path $Fixture 'src\gamedata\scripts\gamma_arena_catalog.script'
    $CatalogScriptOriginal = [IO.File]::ReadAllText($CatalogScript)
    $ProfileRanksChanged = $CatalogScriptOriginal.Replace(
        '{ id = "veteran", cost = 4 }',
        '{ id = "veteran", cost = 5 }'
    )
    [IO.File]::WriteAllText($CatalogScript, $ProfileRanksChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'PROFILE_RANKS'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Changed profile rank costs partially rewrote the document'
    }

    [IO.File]::WriteAllText($CatalogScript, $CatalogScriptOriginal, (New-Object Text.UTF8Encoding($false)))
    $CatalogConfig = Join-Path $Fixture 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
    $CatalogConfigOriginal = [IO.File]::ReadAllText($CatalogConfig)
    $KnifeChanged = $CatalogConfigOriginal.Replace('section = wpn_knife9', '; section intentionally missing')
    [IO.File]::WriteAllText($CatalogConfig, $KnifeChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'knife_knife9'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed knife catalog partially rewrote the document'
    }

    [IO.File]::WriteAllText($CatalogConfig, $CatalogConfigOriginal, (New-Object Text.UTF8Encoding($false)))
    $LayoutMalformed = $LayoutOriginal.Replace('virtual_radii = 1.5,2.5', 'virtual_radii = 1.5,nope')
    [IO.File]::WriteAllText($Layout, $LayoutMalformed, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'virtual_radii'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Malformed virtual radii partially rewrote the document'
    }

    [IO.File]::WriteAllText($Layout, $LayoutOriginal, (New-Object Text.UTF8Encoding($false)))
    $Bootstrap = Join-Path $Fixture 'src\gamedata\scripts\gamma_arena_bootstrap.script'
    $BootstrapOriginal = [IO.File]::ReadAllText($Bootstrap)
    $BootstrapChanged = $BootstrapOriginal.Replace('first.value.power = 100', 'first.value.power = 99')
    [IO.File]::WriteAllText($Bootstrap, $BootstrapChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'powered exo charge'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Changed powered exo charge rule partially rewrote the document'
    }

    [IO.File]::WriteAllText($Bootstrap, $BootstrapOriginal, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $Generator = Join-Path $Fixture 'src\gamedata\scripts\gamma_arena_random_generator.script'
    $GeneratorText = [IO.File]::ReadAllText($Generator)

    $AmmoChanceChanged = $GeneratorText.Replace('w_pistol = 40', 'w_pistol = 41')
    [IO.File]::WriteAllText($Generator, $AmmoChanceChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture -Verify } 'document is stale'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Changed player ammo chance rewrote the document during verification'
    }
    [IO.File]::WriteAllText($Generator, $GeneratorText, (New-Object Text.UTF8Encoding($false)))

    $KnifePickChanged = $GeneratorText.Replace(
        'local choice = rng:pick(knives)',
        'local choice = knives[1]'
    )
    [IO.File]::WriteAllText($Generator, $KnifePickChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'random knife selection'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Changed knife selection partially rewrote the document'
    }

    [IO.File]::WriteAllText($Generator, $GeneratorText, (New-Object Text.UTF8Encoding($false)))

    $FormulaChanged = $GeneratorText.Replace(
        'local primary_count = math.ceil(enemy_count * difficulty.primary_share_percent / 100)',
        'local primary_count = math.floor(enemy_count * difficulty.primary_share_percent / 100)'
    )
    [IO.File]::WriteAllText($Generator, $FormulaChanged, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'primary count formula'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Changed generator formula partially rewrote the document'
    }

    [IO.File]::WriteAllText($Generator, $GeneratorText, (New-Object Text.UTF8Encoding($false)))
    & $ToolPath -RepoRoot $Fixture
    $Renamed = $GeneratorText.Replace('local PRIMARY_BAND_PERCENT = 70', 'local PRIMARY_BAND_RENAMED = 70')
    [IO.File]::WriteAllText($Generator, $Renamed, (New-Object Text.UTF8Encoding($false)))
    $BeforeFailure = [IO.File]::ReadAllText($Document)
    Invoke-ExpectedFailure { & $ToolPath -RepoRoot $Fixture } 'PRIMARY_BAND_PERCENT'
    if ($BeforeFailure -cne [IO.File]::ReadAllText($Document)) {
        throw 'Missing Lua balance symbol partially rewrote the document'
    }
}
finally {
    if (Test-Path -LiteralPath $Fixture) {
        Remove-Item -LiteralPath $Fixture -Recurse -Force
    }
}

Write-Host 'PASS: Arena balance documentation core passed'
