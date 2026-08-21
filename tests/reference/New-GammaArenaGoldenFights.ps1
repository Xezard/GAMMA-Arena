[CmdletBinding()]
param([switch]$Verify)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixturePath = Join-Path $repoRoot 'tests\fixtures\golden-fights-v1.txt'
$catalogPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$difficultyPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$layoutPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$generatorPath = Join-Path $repoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
$catalogText = Get-Content -LiteralPath $catalogPath -Raw
$generatorText = Get-Content -LiteralPath $generatorPath -Raw
if ($catalogText -notmatch '(?m)^schema_version\s*=\s*1\s*$' -or
    $catalogText -notmatch '(?m)^revision\s*=\s*1\s*$' -or
    $catalogText -notmatch '(?m)^generator_version\s*=\s*1\s*$' -or
    $generatorText -notmatch 'schema_version=' -or
    $generatorText -notmatch 'diagnostic=') {
    throw 'Reference oracle supports only FightSpec/catalog/generator v1.'
}

function Read-GaSimpleLtx {
    param([string]$Path)
    $sections = @{}; $currentSection = $null
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[([^\]]+)\]$') { $currentSection = $Matches[1]; if ($sections.ContainsKey($currentSection)) { throw "Duplicate LTX section $currentSection in $Path" }; $sections[$currentSection] = @{}; continue }
        if ($null -eq $currentSection -or $line -notmatch '^([^=]+?)\s*=\s*(.*?)\s*$') { throw "Unsupported LTX line '$rawLine' in $Path" }
        $key = $Matches[1].Trim(); if ($sections[$currentSection].ContainsKey($key)) { throw "Duplicate LTX key $currentSection.$key in $Path" }; $sections[$currentSection][$key] = $Matches[2].Trim()
    }
    return $sections
}

$catalogSections = Read-GaSimpleLtx -Path $catalogPath
$difficultySections = Read-GaSimpleLtx -Path $difficultyPath
$layoutSections = Read-GaSimpleLtx -Path $layoutPath
foreach ($metadata in @($catalogSections.meta, $difficultySections.meta, $layoutSections.meta)) {
    if ([int]$metadata.schema_version -ne 1 -or [int]$metadata.revision -ne 1) { throw 'Reference oracle supports only schema/revision v1.' }
}
if ([int]$catalogSections.meta.generator_version -ne 1) { throw 'Reference oracle supports only generator v1.' }

$difficultyManifest = @{
    rookie = @(1,2,12,12)
    stalker = @(2,3,18,15)
    veteran = @(3,4,26,18)
    master = @(4,6,38,22)
}
if ($difficultySections.Count -ne 5 -or $difficultySections.meta.Count -ne 2) { throw 'Difficulty catalog must match the exact v1 section/key manifest.' }
foreach ($difficultyId in @('rookie','stalker','veteran','master')) {
    $entry = $difficultySections["ga_difficulty_$difficultyId"]
    if ($null -eq $entry -or $entry.Count -ne 4) { throw "Difficulty $difficultyId must match the exact v1 key manifest." }
    $actual = @([int]$entry.enemy_min,[int]$entry.enemy_max,[int]$entry.enemy_total_budget,[int]$entry.player_loadout_budget)
    if (@(Compare-Object -ReferenceObject $difficultyManifest[$difficultyId] -DifferenceObject $actual -SyncWindow 0).Count -ne 0) { throw "Difficulty $difficultyId differs from the v1 semantic manifest." }
}
$expectedLayoutPaths = @('bar_arena_walk_3_1','bar_arena_walk_3_2','bar_arena_walk_6_1','bar_arena_walk_6_3','bar_arena_walk_6_6','bar_arena_monstr_walk')
$layoutManifestEntry = $layoutSections.ga_layout_rostok_arena_v1
if ($layoutSections.Count -ne 2 -or $layoutSections.meta.Count -ne 2 -or $null -eq $layoutManifestEntry -or $layoutManifestEntry.Count -ne 4 -or
    $layoutManifestEntry.level -cne 'l05_bar' -or $layoutManifestEntry.actor_spawn_path -cne 't_way' -or
    $layoutManifestEntry.actor_look_path -cne 't_look') { throw 'Layout catalog differs from the exact v1 semantic manifest.' }
$actualLayoutPaths = @($layoutManifestEntry.opponent_spawn_paths.Split(',') | ForEach-Object { $_.Trim() })
if (@(Compare-Object -ReferenceObject $expectedLayoutPaths -DifferenceObject $actualLayoutPaths -SyncWindow 0).Count -ne 0) { throw 'Layout opponent paths differ from the ordered v1 semantic manifest.' }

$parkMillerModulus = [int64]2147483647
$parkMillerStateModulus = [int64]2147483646

function ConvertTo-GaNormalizedSeed {
    param([int64]$Seed)
    $unsignedValue = $Seed % [int64]4294967296
    if ($unsignedValue -lt 0) { $unsignedValue += [int64]4294967296 }
    if ($unsignedValue -eq 0) { return [int64]1 }
    $normalizedValue = $unsignedValue % $parkMillerStateModulus
    if ($normalizedValue -eq 0) { return $parkMillerStateModulus }
    return $normalizedValue
}

function Get-GaDerivedSeed {
    param([object[]]$Parts)
    $hashValue = [int64]0
    foreach ($part in $Parts) {
        $partPrefix = if ($part -is [string]) { 'string:' } else { 'number:' }
        $partText = $partPrefix + [Convert]::ToString($part, [Globalization.CultureInfo]::InvariantCulture)
        $encodedPart = ([string]$partText.Length) + ':' + $partText
        foreach ($encodedByte in [Text.Encoding]::ASCII.GetBytes($encodedPart)) {
            $hashValue = ($hashValue * 131 + $encodedByte) % $parkMillerStateModulus
        }
    }
    return ConvertTo-GaNormalizedSeed -Seed $hashValue
}

function New-GaReferenceRng {
    param([object[]]$Parts)
    return @{ State = (Get-GaDerivedSeed -Parts $Parts) }
}

function Get-GaNextRaw {
    param([hashtable]$Rng)
    $nextValue = 48271 * ($Rng.State % 44488) - 3399 * [math]::Floor($Rng.State / 44488)
    if ($nextValue -le 0) { $nextValue += $parkMillerModulus }
    $Rng.State = [int64]$nextValue
    return $Rng.State
}

function Get-GaNextInt {
    param([hashtable]$Rng, [int]$Minimum, [int]$Maximum)
    return $Minimum + (Get-GaNextRaw -Rng $Rng) % ($Maximum - $Minimum + 1)
}

function New-GaStream {
    param([pscustomobject]$Request, [int]$FightIndex, [string]$Tag)
    $streamParts = @($Request.ModeId, $Request.DifficultyId, [int64]$Request.SessionSeed,
        $FightIndex, 1, 1, 1, $Tag)
    return New-GaReferenceRng -Parts $streamParts
}

$ammoCosts = @{}; foreach ($ammoId in @($catalogSections.ammo.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object)) { $ammoCosts[$catalogSections["ammo_$ammoId"].section] = [int]$catalogSections["ammo_$ammoId"].cost }
$weaponCatalog = @($catalogSections.weapons.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalogSections["weapon_$_"]; [pscustomobject]@{Section=$entry.section;Ammo=$entry.ammo;Cost=[int]$entry.cost;AmmoBoxMin=[int]$entry.ammo_box_min;AmmoBoxMax=[int]$entry.ammo_box_max} })
$outfitCatalog = @($catalogSections.outfits.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalogSections["outfit_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost} })
$profileCatalog = @($catalogSections.profiles.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalogSections["profile_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost} })
$bandageCost = [int]$catalogSections.consumable_bandage.cost
$loadoutCombinations = @()
foreach ($weaponEntry in $weaponCatalog) {
    foreach ($outfitEntry in $outfitCatalog) {
        foreach ($ammoBoxCount in $weaponEntry.AmmoBoxMin..$weaponEntry.AmmoBoxMax) {
            $loadoutCombinations += [pscustomobject]@{
                Weapon=$weaponEntry.Section; Ammo=$weaponEntry.Ammo; AmmoBoxes=$ammoBoxCount
                Outfit=$outfitEntry.Section
                Cost=$weaponEntry.Cost + $ammoCosts[$weaponEntry.Ammo] * $ammoBoxCount + $outfitEntry.Cost + $bandageCost
            }
        }
    }
}
$loadoutCombinations = @($loadoutCombinations | Sort-Object Cost, Weapon, Outfit, AmmoBoxes)
if ($loadoutCombinations.Count -ne 30) { throw "Reference catalog must construct 30 combinations, got $($loadoutCombinations.Count)." }

$difficultyCatalog = @{}; foreach ($difficultyId in @('rookie','stalker','veteran','master')) { $entry=$difficultySections["ga_difficulty_$difficultyId"]; $difficultyCatalog[$difficultyId]=[pscustomobject]@{EnemyMin=[int]$entry.enemy_min;EnemyMax=[int]$entry.enemy_max;EnemyBudget=[int]$entry.enemy_total_budget;PlayerBudget=[int]$entry.player_loadout_budget} }
$layoutEntry = $layoutSections.ga_layout_rostok_arena_v1
$layoutOpponentPaths = @($layoutEntry.opponent_spawn_paths.Split(',') | ForEach-Object { $_.Trim() })

function Select-GaAffordable {
    param([hashtable]$Rng, [array]$Values, [int]$Budget)
    $affordableValues = @($Values | Where-Object { $_.Cost -le $Budget })
    if ($affordableValues.Count -eq 0) { throw "Reference candidate set is empty for budget $Budget." }
    $selectedIndex = (Get-GaNextInt -Rng $Rng -Minimum 1 -Maximum $affordableValues.Count) - 1
    return $affordableValues[$selectedIndex]
}

function New-GaEncodedLoadout {
    param([hashtable]$Rng, [int]$Budget)
    $selectedLoadout = Select-GaAffordable -Rng $Rng -Values $loadoutCombinations -Budget $Budget
    return "$($selectedLoadout.Weapon),$($selectedLoadout.Ammo),$($selectedLoadout.AmmoBoxes),$($selectedLoadout.Outfit),bandage,$($selectedLoadout.Cost)"
}

function New-GaEncodedFight {
    param([int64]$SessionSeed, [string]$DifficultyId, [int]$FightIndex)
    $normalizedSeed = ConvertTo-GaNormalizedSeed -Seed $SessionSeed
    $request = [pscustomobject]@{SessionSeed=$normalizedSeed;ModeId='skirmish';DifficultyId=$DifficultyId;LayoutId='rostok_arena_v1'}
    $difficulty = $difficultyCatalog[$DifficultyId]
    $enemyCountRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag 'enemy_count'
    $enemyCount = Get-GaNextInt -Rng $enemyCountRng -Minimum $difficulty.EnemyMin -Maximum $difficulty.EnemyMax
    $spawnPaths = @($layoutOpponentPaths)
    $spawnRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag 'spawn_path'
    for ($pathIndex = $spawnPaths.Count - 1; $pathIndex -ge 1; $pathIndex--) {
        $targetIndex = (Get-GaNextInt -Rng $spawnRng -Minimum 1 -Maximum ($pathIndex + 1)) - 1
        $swapPath = $spawnPaths[$pathIndex]; $spawnPaths[$pathIndex] = $spawnPaths[$targetIndex]; $spawnPaths[$targetIndex] = $swapPath
    }
    $actorRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag 'actor_loadout'
    $actorLoadout = New-GaEncodedLoadout -Rng $actorRng -Budget $difficulty.PlayerBudget
    $slotBaseBudget = [math]::Floor($difficulty.EnemyBudget / $enemyCount)
    $slotRemainder = $difficulty.EnemyBudget % $enemyCount
    $encodedOpponents = @()
    for ($opponentIndex = 1; $opponentIndex -le $enemyCount; $opponentIndex++) {
        $slotBudget = [int]$slotBaseBudget + $(if ($opponentIndex -le $slotRemainder) { 1 } else { 0 })
        $profileRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag ('enemy_profile:' + $opponentIndex)
        $selectedProfile = Select-GaAffordable -Rng $profileRng -Values $profileCatalog -Budget ($slotBudget - $loadoutCombinations[0].Cost)
        $loadoutRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag ('enemy_loadout:' + $opponentIndex)
        $encodedLoadout = New-GaEncodedLoadout -Rng $loadoutRng -Budget ($slotBudget - $selectedProfile.Cost)
        $loadoutCost = [int]$encodedLoadout.Split(',')[-1]
        $totalCost = $selectedProfile.Cost + $loadoutCost
        $encodedOpponents += "${opponentIndex}:$opponentIndex,$($spawnPaths[$opponentIndex-1]),$($selectedProfile.Section),$($selectedProfile.Cost),$encodedLoadout,$totalCost"
    }
    $fields = @(
        'schema_version=1','generator_version=1','catalog_revision=1','layout_version=1',
        "session_seed=$normalizedSeed","fight_index=$FightIndex","fight_id=ga-$normalizedSeed-$FightIndex-g1-c1-l1",'mode_id=skirmish',"difficulty_id=$DifficultyId",
        'layout_id=rostok_arena_v1',"level=$($layoutEntry.level)","actor=$($layoutEntry.actor_spawn_path),$($layoutEntry.actor_look_path),$actorLoadout",'opponents='
    ) + $encodedOpponents + "diagnostic=FightSpecV1 skirmish $DifficultyId #$FightIndex"
    return $fields -join '|'
}

$goldenRequests = @(
    [pscustomobject]@{Seed=[int64]0;Difficulty='rookie';Fight=0}
    [pscustomobject]@{Seed=[int64]1;Difficulty='stalker';Fight=0}
    [pscustomobject]@{Seed=[int64]3735928559;Difficulty='veteran';Fight=7}
    [pscustomobject]@{Seed=[int64]4294967295;Difficulty='master';Fight=31}
)
$expectedLines = @($goldenRequests | ForEach-Object {
    $encoding = New-GaEncodedFight -SessionSeed $_.Seed -DifficultyId $_.Difficulty -FightIndex $_.Fight
    "seed=$($_.Seed),difficulty=$($_.Difficulty),fight=$($_.Fight),stable_encode=$encoding"
})
if ($expectedLines.Count -ne 4) { throw 'Reference oracle must produce exactly four golden records.' }

$zeroAlias = New-GaEncodedFight -SessionSeed 0 -DifficultyId veteran -FightIndex 7
$oneAlias = New-GaEncodedFight -SessionSeed 1 -DifficultyId veteran -FightIndex 7
if ($zeroAlias -cne $oneAlias) { throw 'Normalized seed aliases 0 and 1 must produce the same canonical FightSpec.' }

if ($Verify) {
    $actualLines = @(Get-Content -LiteralPath $fixturePath | Where-Object { $_ -and -not $_.StartsWith('#') })
    if (@(Compare-Object -ReferenceObject $expectedLines -DifferenceObject $actualLines -SyncWindow 0).Count -ne 0) {
        throw 'Golden fixture differs from deterministic v1 reference oracle.'
    }
    Write-Host 'PASS: golden reference oracle matches fixture'
} else {
    $expectedLines
}
