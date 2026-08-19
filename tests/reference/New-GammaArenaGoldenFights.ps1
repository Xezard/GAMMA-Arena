[CmdletBinding()]
param([switch]$Verify)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixturePath = Join-Path $repoRoot 'tests\fixtures\golden-fights-v1.txt'
$catalogPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
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

$ammoCosts = @{
    'ammo_9x18_fmj' = 1; 'ammo_9x19_fmj' = 1
    'ammo_5.45x39_fmj' = 2; 'ammo_12x70_buck' = 2
}
$weaponCatalog = @(
    [pscustomobject]@{ Section='wpn_ak74'; Ammo='ammo_5.45x39_fmj'; Cost=6 }
    [pscustomobject]@{ Section='wpn_ak74u'; Ammo='ammo_5.45x39_fmj'; Cost=5 }
    [pscustomobject]@{ Section='wpn_mp5'; Ammo='ammo_9x19_fmj'; Cost=4 }
    [pscustomobject]@{ Section='wpn_pm'; Ammo='ammo_9x18_fmj'; Cost=2 }
    [pscustomobject]@{ Section='wpn_wincheaster1300'; Ammo='ammo_12x70_buck'; Cost=5 }
)
$outfitCatalog = @(
    [pscustomobject]@{ Section='banditmerc_outfit'; Cost=4 }
    [pscustomobject]@{ Section='novice_outfit'; Cost=1 }
    [pscustomobject]@{ Section='stalker_outfit'; Cost=3 }
)
$profileCatalog = @(
    [pscustomobject]@{ Section='gamma_arena_bandit_experienced'; Cost=3 }
    [pscustomobject]@{ Section='gamma_arena_bandit_novice'; Cost=1 }
    [pscustomobject]@{ Section='gamma_arena_bandit_trainee'; Cost=2 }
    [pscustomobject]@{ Section='gamma_arena_bandit_veteran'; Cost=4 }
)
$loadoutCombinations = @()
foreach ($weaponEntry in $weaponCatalog) {
    foreach ($outfitEntry in $outfitCatalog) {
        foreach ($ammoBoxCount in 1..2) {
            $loadoutCombinations += [pscustomobject]@{
                Weapon=$weaponEntry.Section; Ammo=$weaponEntry.Ammo; AmmoBoxes=$ammoBoxCount
                Outfit=$outfitEntry.Section
                Cost=$weaponEntry.Cost + $ammoCosts[$weaponEntry.Ammo] * $ammoBoxCount + $outfitEntry.Cost + 1
            }
        }
    }
}
$loadoutCombinations = @($loadoutCombinations | Sort-Object Cost, Weapon, Outfit, AmmoBoxes)
if ($loadoutCombinations.Count -ne 30) { throw "Reference catalog must construct 30 combinations, got $($loadoutCombinations.Count)." }

$difficultyCatalog = @{
    rookie=[pscustomobject]@{EnemyMin=1;EnemyMax=2;EnemyBudget=12;PlayerBudget=12}
    stalker=[pscustomobject]@{EnemyMin=2;EnemyMax=3;EnemyBudget=18;PlayerBudget=15}
    veteran=[pscustomobject]@{EnemyMin=3;EnemyMax=4;EnemyBudget=26;PlayerBudget=18}
    master=[pscustomobject]@{EnemyMin=4;EnemyMax=6;EnemyBudget=38;PlayerBudget=22}
}

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
    $request = [pscustomobject]@{SessionSeed=$SessionSeed;ModeId='skirmish';DifficultyId=$DifficultyId;LayoutId='rostok_arena_v1'}
    $difficulty = $difficultyCatalog[$DifficultyId]
    $enemyCountRng = New-GaStream -Request $request -FightIndex $FightIndex -Tag 'enemy_count'
    $enemyCount = Get-GaNextInt -Rng $enemyCountRng -Minimum $difficulty.EnemyMin -Maximum $difficulty.EnemyMax
    $spawnPaths = @('bar_arena_walk_3_1','bar_arena_walk_3_2','bar_arena_walk_6_1','bar_arena_walk_6_3','bar_arena_walk_6_6','bar_arena_monstr_walk')
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
    $normalizedSeed = ConvertTo-GaNormalizedSeed -Seed $SessionSeed
    $fields = @(
        'schema_version=1','generator_version=1','catalog_revision=1','layout_version=1',
        "fight_id=ga-$normalizedSeed-$FightIndex-g1-c1-l1",'mode_id=skirmish',"difficulty_id=$DifficultyId",
        'layout_id=rostok_arena_v1','level=l05_bar',"actor=bar_arena_walk_1_1,bar_arena_walk_attack,$actorLoadout",'opponents='
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

if ($Verify) {
    $actualLines = @(Get-Content -LiteralPath $fixturePath | Where-Object { $_ -and -not $_.StartsWith('#') })
    if (@(Compare-Object -ReferenceObject $expectedLines -DifferenceObject $actualLines -SyncWindow 0).Count -ne 0) {
        throw 'Golden fixture differs from deterministic v1 reference oracle.'
    }
    Write-Host 'PASS: golden reference oracle matches fixture'
} else {
    $expectedLines
}
