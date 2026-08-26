[CmdletBinding()]
param([switch]$Verify, [switch]$Update)

$ErrorActionPreference = 'Stop'
if ($Verify -and $Update) { throw 'Choose either -Verify or -Update.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixturePath = Join-Path $repoRoot 'tests\fixtures\golden-fights-v8.txt'
$catalogPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$difficultyPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$layoutPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'

function Read-GaSimpleLtx {
    param([string]$Path)
    $sections = @{}; $currentSection = $null
    foreach ($rawLine in Get-Content -LiteralPath $Path) {
        $line = $rawLine.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[([^\]]+)\]$') {
            $currentSection = $Matches[1]
            if ($sections.ContainsKey($currentSection)) { throw "Duplicate LTX section $currentSection in $Path" }
            $sections[$currentSection] = @{}
            continue
        }
        if ($null -eq $currentSection -or $line -notmatch '^([^=]+?)\s*=\s*(.*?)\s*$') { throw "Unsupported LTX line '$rawLine' in $Path" }
        $key = $Matches[1].Trim()
        if ($sections[$currentSection].ContainsKey($key)) { throw "Duplicate LTX key $currentSection.$key in $Path" }
        $sections[$currentSection][$key] = $Matches[2].Trim()
    }
    return $sections
}

$catalog = Read-GaSimpleLtx $catalogPath
$difficulties = Read-GaSimpleLtx $difficultyPath
$layouts = Read-GaSimpleLtx $layoutPath
if ([int]$catalog.meta.schema_version -ne 9 -or [int]$catalog.meta.revision -ne 10 -or [int]$catalog.meta.generator_version -ne 10 -or
    [int]$difficulties.meta.schema_version -ne 4 -or [int]$difficulties.meta.revision -ne 5 -or
    [int]$layouts.meta.schema_version -ne 2 -or [int]$layouts.meta.revision -ne 2) {
    throw 'Reference oracle requires catalog identity 9/10/10, medical difficulty v5, layout v2, and FightSpec v8.'
}

$difficultyManifest = @{
    rookie = @(1,2,3,25,7,4,50,35,50,15,0,50,30,15,5,0,55,30,10,5,0)
    stalker = @(2,3,5,50,10,5,60,25,50,25,0,25,35,20,18,2,30,40,20,9,1)
    veteran = @(3,5,7,75,13,6,75,20,45,30,5,10,25,20,38,7,15,30,25,25,5)
    master = @(4,7,10,100,15,8,80,15,40,35,10,5,15,15,50,15,10,25,25,35,5)
}
$difficultyCatalog = @{}
foreach ($id in @('rookie','stalker','veteran','master')) {
    $entry = $difficulties["ga_difficulty_$id"]
    if ($null -eq $entry -or $entry.Count -ne 21) { throw "Difficulty $id must expose exactly twenty-one medical loadout fields." }
    $actual = @([int]$entry.tier,[int]$entry.enemy_min,[int]$entry.enemy_max,[int]$entry.enemy_total_budget,[int]$entry.player_gear_budget,[int]$entry.player_medical_budget,[int]$entry.primary_share_percent,[int]$entry.medical_weight_bleed,[int]$entry.medical_weight_health,[int]$entry.medical_weight_boost,[int]$entry.medical_weight_rare,[int]$entry.weapon_weight_pistol,[int]$entry.weapon_weight_smg,[int]$entry.weapon_weight_shotgun,[int]$entry.weapon_weight_rifle,[int]$entry.weapon_weight_sniper,[int]$entry.armor_weight_light,[int]$entry.armor_weight_medium,[int]$entry.armor_weight_scientific,[int]$entry.armor_weight_heavy,[int]$entry.armor_weight_powered_exo)
    if (@(Compare-Object $difficultyManifest[$id] $actual -SyncWindow 0).Count -ne 0) { throw "Difficulty $id differs from the v5 semantic manifest." }
    $difficultyCatalog[$id] = [pscustomobject]@{Id=$id;Tier=$actual[0];EnemyMin=$actual[1];EnemyMax=$actual[2];EnemyBudget=$actual[3];PlayerBudget=($actual[4]+1);PlayerGearBudget=$actual[4];PlayerMedicalBudget=$actual[5];PrimaryShare=$actual[6];MedicalWeights=@{bleed=$actual[7];health=$actual[8];boost=$actual[9];rare=$actual[10]};WeaponWeights=@{w_pistol=$actual[11];w_smg=$actual[12];w_shotgun=$actual[13];w_rifle=$actual[14];w_sniper=$actual[15]};ArmorWeights=@{light=$actual[16];medium=$actual[17];scientific=$actual[18];heavy=$actual[19];powered_exo=$actual[20]}}
}

$layout = $layouts.ga_layout_rostok_arena_v1
$routes = @($layout.opponent_spawn_paths.Split(',') | ForEach-Object { $_.Trim() })
if ($routes.Count -ne 6 -or [int]$layout.virtual_capacity -ne 10 -or $layout.virtual_radii -cne '1.5,2.5' -or
    [double]$layout.max_height_delta -ne 1.0 -or [double]$layout.min_opponent_separation -ne 1.75 -or
    [double]$layout.min_actor_separation -ne 8.0 -or [double]$layout.max_base_distance -ne 3.0) {
    throw 'Layout differs from the exact v2 virtual-capacity manifest.'
}

$parkMillerModulus = [int64]2147483647
$parkMillerStateModulus = [int64]2147483646
function ConvertTo-GaNormalizedSeed([int64]$Seed) {
    $unsigned = $Seed % [int64]4294967296
    if ($unsigned -lt 0) { $unsigned += [int64]4294967296 }
    if ($unsigned -eq 0) { return [int64]1 }
    $normalized = $unsigned % $parkMillerStateModulus
    if ($normalized -eq 0) { return $parkMillerStateModulus }
    return $normalized
}
function Get-GaDerivedSeed([object[]]$Parts) {
    $hash = [int64]0
    foreach ($part in $Parts) {
        $prefix = if ($part -is [string]) { 'string:' } else { 'number:' }
        $text = $prefix + [Convert]::ToString($part, [Globalization.CultureInfo]::InvariantCulture)
        $encoded = ([string]$text.Length) + ':' + $text
        foreach ($byte in [Text.Encoding]::ASCII.GetBytes($encoded)) { $hash = ($hash * 131 + $byte) % $parkMillerStateModulus }
    }
    return ConvertTo-GaNormalizedSeed $hash
}
function New-GaRng([object[]]$Parts) { return @{ State = (Get-GaDerivedSeed $Parts) } }
function Get-GaNextRaw([hashtable]$Rng) {
    $next = 48271 * ($Rng.State % 44488) - 3399 * [math]::Floor($Rng.State / 44488)
    if ($next -le 0) { $next += $parkMillerModulus }
    $Rng.State = [int64]$next
    return $Rng.State
}
function Get-GaNextInt([hashtable]$Rng, [int]$Minimum, [int]$Maximum) { return $Minimum + (Get-GaNextRaw $Rng) % ($Maximum - $Minimum + 1) }
function New-GaStream([pscustomobject]$Request, [int]$FightIndex, [string]$Tag, [int]$Epoch = 6) {
    return New-GaRng @($Request.ModeId,$Request.DifficultyId,[int64]$Request.SessionSeed,$FightIndex,$Epoch,2,$Tag)
}
function Select-GaPick([hashtable]$Rng, [array]$Values) { return $Values[(Get-GaNextInt $Rng 1 $Values.Count) - 1] }
function Select-GaWeightedPair {
    param([hashtable]$Rng, [array]$Pairs)
    $total = ($Pairs | Measure-Object Weight -Sum).Sum
    $draw = Get-GaNextInt $Rng 1 $total
    $cumulative = 0
    foreach ($pair in $Pairs) {
        $cumulative += $pair.Weight
        if ($draw -le $cumulative) { return $pair }
    }
    throw 'Weighted pair selection exhausted its range.'
}
function Select-GaBand([hashtable]$Rng, [array]$Values, [int]$Maximum) {
    $affordable = @($Values | Where-Object { $_.Cost -le $Maximum })
    if ($affordable.Count -eq 0) { throw "No affordable reference candidate for budget $Maximum." }
    $threshold = [math]::Ceiling($Maximum * 70 / 100)
    $band = @($affordable | Where-Object { $_.Cost -ge $threshold })
    if ($band.Count -eq 0) {
        $highest = ($affordable | Measure-Object Cost -Maximum).Maximum
        $band = @($affordable | Where-Object { $_.Cost -eq $highest })
    }
    return Select-GaPick $Rng $band
}
function Get-GaShuffled([hashtable]$Rng, [array]$Values) {
    $copy = @($Values)
    for ($index = $copy.Count - 1; $index -ge 1; $index--) {
        $target = (Get-GaNextInt $Rng 1 ($index + 1)) - 1
        $swap = $copy[$index]; $copy[$index] = $copy[$target]; $copy[$target] = $swap
    }
    return $copy
}

$ammoCosts = @{}
foreach ($id in @($catalog.ammo.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object)) { $entry=$catalog["ammo_$id"]; $ammoCosts[$entry.section]=[int]$entry.cost }
$referenceMagazineSizes = @{wpn_pm=8;wpn_mp5=30;wpn_ak74u=30;wpn_ak74=30;wpn_wincheaster1300=8}
$referenceBoxSizes = @{ammo_9x18_fmj=30;ammo_9x19_fmj=30;'ammo_5.45x39_fmj'=30;ammo_12x70_buck=10}
$weapons = @($catalog.weapons.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object {
    $entry=$catalog["weapon_$_"]
    if (-not $referenceMagazineSizes.ContainsKey($entry.section) -or -not $referenceBoxSizes.ContainsKey($entry.ammo)) { throw "Reference capacity is unavailable for $($entry.section)." }
    [pscustomobject]@{Section=$entry.section;Ammo=$entry.ammo;MagazineSize=[int]$referenceMagazineSizes[$entry.section];BoxSize=[int]$referenceBoxSizes[$entry.ammo];Cost=[int]$entry.cost;AmmoBoxMin=[int]$entry.ammo_box_min;AmmoBoxMax=[int]$entry.ammo_box_max;Kind=$entry.kind;Slot=[int]$entry.slot}
})
$outfits = @($catalog.outfits.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalog["outfit_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost;ArmorClass=$entry.armor_class} })
$profiles = @($catalog.profiles.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalog["profile_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost} })
$knives = @($catalog.knives.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $catalog["knife_$_"].section })
$actorGrenadeIds = @($catalog.grenades.ids.Split(',') | ForEach-Object { $_.Trim() })
$npcGrenadeIds = @($catalog.grenades.npc_ids.Split(',') | ForEach-Object { $_.Trim() })
$actorGrenadePool = @($actorGrenadeIds | ForEach-Object { $catalog["grenade_$_"].section })
$npcGrenadePool = @($npcGrenadeIds | ForEach-Object { $catalog["grenade_$_"].section })
if ($actorGrenadePool.Count -ne 3 -or $npcGrenadePool.Count -ne 3 -or $actorGrenadePool -contains 'grenade_smoke' -or $npcGrenadePool -contains 'grenade_smoke') {
    throw 'Reference grenade pools differ from the FightSpec v7 contract.'
}
$bandageCost = [int]$catalog.consumable_bandage.cost
$medicalItems = @($catalog.medical_items.ids.Split(',') | ForEach-Object { $_.Trim() } | ForEach-Object {
    $entry = $catalog["medical_$_"]
    [pscustomobject]@{Id=$_;Section=$entry.section;Category=$entry.category;ActorCost=[int]$entry.actor_cost;NpcCost=[int]$entry.npc_cost;MinTier=[int]$entry.min_tier;MaxCount=[int]$entry.max_count}
} | Sort-Object Section)
$medicalBySection = @{}; foreach ($item in $medicalItems) { $medicalBySection[$item.Section] = $item }
$combinations = @()
foreach ($weapon in $weapons) { foreach ($outfit in $outfits) { foreach ($boxes in $weapon.AmmoBoxMin..$weapon.AmmoBoxMax) {
    $combinations += [pscustomobject]@{Weapon=$weapon.Section;Ammo=$weapon.Ammo;AmmoBoxes=$boxes;Outfit=$outfit.Section;Cost=$weapon.Cost+$ammoCosts[$weapon.Ammo]*$boxes+$outfit.Cost+$bandageCost;Kind=$weapon.Kind}
} } }
$combinations = @($combinations | Sort-Object Cost,Weapon,Outfit,AmmoBoxes)
$primaryWeapons = @($weapons | Where-Object Kind -ne 'w_pistol')
$secondaryWeapons = @($weapons | Where-Object Kind -eq 'w_pistol')

function Get-GaRoleCombinations([string]$Role) {
    $sections = @{}
    foreach ($weapon in $(if ($Role -eq 'secondary') { $secondaryWeapons } else { $primaryWeapons })) { $sections[$weapon.Section]=$true }
    return @($combinations | Where-Object { $sections.ContainsKey($_.Weapon) })
}

function Select-GaMedicalCategory([hashtable]$Rng, [hashtable]$Weights, [hashtable]$Available) {
    $categories = @('bleed','health','boost','rare')
    $total = 0
    foreach ($category in $categories) { if ($Available[$category] -and [int]$Weights[$category] -gt 0) { $total += [int]$Weights[$category] } }
    if ($total -le 0) { return $null }
    $draw = Get-GaNextInt $Rng 1 $total; $cumulative = 0
    foreach ($category in $categories) {
        if ($Available[$category] -and [int]$Weights[$category] -gt 0) {
            $cumulative += [int]$Weights[$category]
            if ($draw -le $cumulative) { return $category }
        }
    }
    throw 'Medical category draw exhausted its range.'
}

function New-GaActorMedical([pscustomobject]$Request, [int]$FightIndex, [pscustomobject]$Difficulty) {
    $sections = [Collections.Generic.List[string]]::new(); $sections.Add('bandage')
    $cost = [int]$medicalBySection.bandage.ActorCost
    $sectionCounts = @{bandage=1}; $categoryCounts = @{bleed=1}
    for ($stage = 0; $stage -le 3; $stage++) {
        $required = $stage -eq 0
        $remaining = $Difficulty.PlayerMedicalBudget - $cost
        $byCategory = @{bleed=@();health=@();boost=@();rare=@()}; $available = @{}
        foreach ($item in $medicalItems) {
            $count = if ($sectionCounts.ContainsKey($item.Section)) { [int]$sectionCounts[$item.Section] } else { 0 }
            $categoryCount = if ($categoryCounts.ContainsKey($item.Category)) { [int]$categoryCounts[$item.Category] } else { 0 }
            $categoryCap = switch ($item.Category) { health {2} boost {1} rare {1} default {999} }
            $healing = $item.Category -eq 'health' -or $item.Category -eq 'rare'
            if ($item.MinTier -le $Difficulty.Tier -and $item.ActorCost -le $remaining -and $count -lt $item.MaxCount -and $categoryCount -lt $categoryCap -and (-not $required -or $healing)) {
                $byCategory[$item.Category] = @($byCategory[$item.Category]) + $item
                $available[$item.Category] = $true
            }
        }
        $categoryTag = if ($required) { 'actor_medical_required_category' } else { "actor_medical_optional_category:$stage" }
        $sectionTag = if ($required) { 'actor_medical_required_section' } else { "actor_medical_optional_section:$stage" }
        $category = Select-GaMedicalCategory (New-GaStream $Request $FightIndex $categoryTag 1) $Difficulty.MedicalWeights $available
        if ($null -eq $category) { if ($required) { throw 'No required reference healer fits.' }; break }
        $item = Select-GaPick (New-GaStream $Request $FightIndex $sectionTag 1) @($byCategory[$category] | Sort-Object Section)
        $sections.Add($item.Section); $cost += $item.ActorCost
        $sectionCounts[$item.Section] = $(if ($sectionCounts.ContainsKey($item.Section)) { [int]$sectionCounts[$item.Section] + 1 } else { 1 })
        $categoryCounts[$item.Category] = $(if ($categoryCounts.ContainsKey($item.Category)) { [int]$categoryCounts[$item.Category] + 1 } else { 1 })
        if ($sections.Count -ge 5) { break }
    }
    return [pscustomobject]@{Sections=@($sections);Cost=$cost}
}

function New-GaEnemyMedical([pscustomobject]$Request, [int]$FightIndex, [array]$Records) {
    $count = $Records.Count
    $medkitCap = [math]::Min([math]::Floor($count / 2), [math]::Ceiling($count / 4))
    $medkitCount = Get-GaNextInt (New-GaStream $Request $FightIndex 'enemy_medical_mix' 1) 1 $medkitCap
    $bandageCount = $count - 2 * $medkitCount
    $allocations = @(); for ($index = 0; $index -lt $count; $index++) { $allocations += [pscustomobject]@{Sections=[Collections.Generic.List[string]]::new();Cost=0} }
    foreach ($pair in @([pscustomobject]@{Section='medkit';Count=$medkitCount},[pscustomobject]@{Section='bandage';Count=$bandageCount})) {
        $item = $medicalBySection[$pair.Section]
        for ($itemIndex = 1; $itemIndex -le $pair.Count; $itemIndex++) {
            $eligible = @(); $total = 0
            for ($index = 0; $index -lt $count; $index++) {
                if ($allocations[$index].Sections -contains $pair.Section) { continue }
                $weight = switch ($Records[$index].Role) { leader {4} primary {2} secondary {1} default {0} }
                if ($weight -gt 0) { $total += $weight; $eligible += [pscustomobject]@{Index=$index;Weight=$weight} }
            }
            $draw = Get-GaNextInt (New-GaStream $Request $FightIndex "enemy_medical_recipient:$($pair.Section):$itemIndex" 1) 1 $total
            $cumulative = 0; $recipient = -1
            foreach ($candidate in $eligible) { $cumulative += $candidate.Weight; if ($draw -le $cumulative) { $recipient = $candidate.Index; break } }
            if ($recipient -lt 0) { throw 'Enemy medical recipient draw exhausted its range.' }
            $allocations[$recipient].Sections.Add($pair.Section)
            $allocations[$recipient].Cost += $item.NpcCost
        }
    }
    return $allocations
}

function New-GaLoadout([hashtable]$Rng, [int]$Budget, [array]$Candidates, [string]$Knife) {
    $choice = Select-GaBand $Rng $Candidates $Budget
    return [pscustomobject]@{Weapon=$choice.Weapon;Ammo=$choice.Ammo;AmmoBoxes=$choice.AmmoBoxes;Outfit=$choice.Outfit;Knife=$Knife;GearCost=[int]$choice.Cost-$bandageCost;Kind=$choice.Kind}
}
$playerAmmoChance = @{w_pistol=40;w_smg=25;w_shotgun=25;w_rifle=20;w_sniper=10}
foreach ($entry in $playerAmmoChance.GetEnumerator()) {
    if ([int]$entry.Value -lt 1 -or [int]$entry.Value -gt 100) { throw "Player-ammo chance is invalid for $($entry.Key)." }
}
function New-GaScaledAmmoBoxes([pscustomobject]$Request, [int]$FightIndex, [string]$WeaponKind, [int]$OpponentCount) {
    if ($OpponentCount -lt 1 -or -not $playerAmmoChance.ContainsKey($WeaponKind)) { throw 'Reference player-ammo scaling inputs are invalid.' }
    $boxes = 1
    for ($index = 1; $index -le $OpponentCount; $index++) {
        $draw = Get-GaNextInt (New-GaStream $Request $FightIndex "actor_scaled_ammo:$index") 1 100
        if ($draw -le [int]$playerAmmoChance[$WeaponKind]) { $boxes++ }
    }
    return $boxes
}
function New-GaActorGrenades([pscustomobject]$Request, [int]$FightIndex) {
    $draw = Get-GaNextInt (New-GaStream $Request $FightIndex 'actor_grenade_count') 1 100
    $count = if ($draw -eq 1) { 2 } elseif ($draw -le 6) { 1 } else { 0 }
    $values = [Collections.Generic.List[string]]::new()
    for ($index = 1; $index -le $count; $index++) {
        $values.Add((Select-GaPick (New-GaStream $Request $FightIndex "actor_grenade_section:$index") $actorGrenadePool))
    }
    return @($values)
}
function New-GaEnemyGrenades([pscustomobject]$Request, [int]$FightIndex, [int]$Slot) {
    if ((Get-GaNextInt (New-GaStream $Request $FightIndex "enemy_grenade_presence:$Slot") 1 100) -gt 10) { return @() }
    return @(Select-GaPick (New-GaStream $Request $FightIndex "enemy_grenade_section:$Slot") $npcGrenadePool)
}
function New-GaPlayerLoadout([pscustomobject]$Request, [int]$FightIndex, [pscustomobject]$Difficulty, [string]$Knife, [int]$OpponentCount) {
    $pairs = @()
    foreach ($weaponClass in @('w_pistol','w_smg','w_shotgun','w_rifle','w_sniper')) {
        foreach ($armorClass in @('light','medium','scientific','heavy','powered_exo')) {
            $available = $false
            foreach ($weapon in $weapons) {
                if ($weapon.Kind -ne $weaponClass) { continue }
                foreach ($boxes in $weapon.AmmoBoxMin..$weapon.AmmoBoxMax) {
                    foreach ($outfit in $outfits) {
                        if ($outfit.ArmorClass -eq $armorClass -and $weapon.Cost + $ammoCosts[$weapon.Ammo] * $boxes + $outfit.Cost + $bandageCost -le $Difficulty.PlayerBudget) { $available = $true; break }
                    }
                    if ($available) { break }
                }
                if ($available) { break }
            }
            $weight = $Difficulty.WeaponWeights[$weaponClass] * $Difficulty.ArmorWeights[$armorClass]
            if ($available -and $weight -gt 0) { $pairs += [pscustomobject]@{WeaponClass=$weaponClass;ArmorClass=$armorClass;Weight=$weight} }
        }
    }
    if ($pairs.Count -eq 0) { throw 'No valid player class pair fits the budget.' }
    $pair = Select-GaWeightedPair (New-GaStream $Request $FightIndex 'actor_class_pair') $pairs
    $eligibleWeapons = @($weapons | Where-Object {
        $weapon = $_
        $weapon.Kind -eq $pair.WeaponClass -and @($weapon.AmmoBoxMin..$weapon.AmmoBoxMax | Where-Object {
            $boxes = $_
            @($outfits | Where-Object { $_.ArmorClass -eq $pair.ArmorClass -and $weapon.Cost + $ammoCosts[$weapon.Ammo] * $boxes + $_.Cost + $bandageCost -le $Difficulty.PlayerBudget }).Count -gt 0
        }).Count -gt 0
    })
    $weapon = Select-GaPick (New-GaStream $Request $FightIndex 'actor_weapon') $eligibleWeapons
    $eligibleBoxes = @($weapon.AmmoBoxMin..$weapon.AmmoBoxMax | Where-Object {
        $boxes = $_
        @($outfits | Where-Object { $_.ArmorClass -eq $pair.ArmorClass -and $weapon.Cost + $ammoCosts[$weapon.Ammo] * $boxes + $_.Cost + $bandageCost -le $Difficulty.PlayerBudget }).Count -gt 0
    })
    $ammoBoxes = Select-GaPick (New-GaStream $Request $FightIndex 'actor_ammo_boxes') $eligibleBoxes
    $eligibleOutfits = @($outfits | Where-Object { $_.ArmorClass -eq $pair.ArmorClass -and $weapon.Cost + $ammoCosts[$weapon.Ammo] * $ammoBoxes + $_.Cost + $bandageCost -le $Difficulty.PlayerBudget })
    $outfit = Select-GaPick (New-GaStream $Request $FightIndex 'actor_outfit') $eligibleOutfits
    $cost = $weapon.Cost + $ammoCosts[$weapon.Ammo] * $ammoBoxes + $outfit.Cost + $bandageCost
    $bonusDraw=Get-GaNextInt (New-GaStream $Request $FightIndex 'actor_bonus_ammo_category') 1 100
    $requestedCategory=$(if($bonusDraw -le 60){'standard'}elseif($bonusDraw -le 75){'special'}else{'armor_piercing'})
    $bonusSection=$weapon.Ammo
    if($requestedCategory-eq'standard'){ $bonusSection=(Select-GaPick (New-GaStream $Request $FightIndex 'actor_bonus_ammo_section') @($weapon.Ammo)) }
    $bonus="bonus:${bonusSection}:${requestedCategory}:standard:1"
    $gearCost = [int]$cost - $bandageCost
    $medical = New-GaActorMedical $Request $FightIndex $Difficulty
    $totalCost = $gearCost + $medical.Cost
    $minimumBoxes = [int][Math]::Ceiling(3.0 * $weapon.MagazineSize / $weapon.BoxSize)
    $scaledBoxes = New-GaScaledAmmoBoxes $Request $FightIndex $weapon.Kind $OpponentCount
    $finalAmmoBoxes = [int][Math]::Max($ammoBoxes, $minimumBoxes) + $scaledBoxes
    $grenades = @(New-GaActorGrenades $Request $FightIndex)
    return [pscustomobject]@{Encoded="$($weapon.Section),$($weapon.Ammo),$finalAmmoBoxes,$($outfit.Section),$Knife,medical:$($medical.Sections -join '+'),grenades:$($grenades -join '+'),$gearCost,$($medical.Cost),$totalCost,$bonus";Weapon=$weapon.Section;Ammo=$weapon.Ammo;Outfit=$outfit.Section;Knife=$Knife;Medicine=@($medical.Sections);BonusSection=$bonusSection;Cost=$totalCost;GearCost=$gearCost;MedicalCost=$medical.Cost;Kind=$weapon.Kind;BudgetedAmmoBoxes=$ammoBoxes;AmmoBoxes=$finalAmmoBoxes;ScaledAmmoBoxes=$scaledBoxes;Grenades=$grenades}
}

$resolvedSlots = @()
for ($index=1; $index -le 10; $index++) {
    $route=$routes[($index-1)%$routes.Count]
    $resolvedSlots += [pscustomobject]@{Id=$(if($index -le 6){"native:$route"}else{"virtual:$($index-6)"});BaseRoute=$route;Native=($index -le 6);X=$index*4;Y=0;Z=$(if($index%2 -eq 0){4}else{-4});Lvid=1000+$index;Gvid=77}
}
function Get-GaSelectedSlots([hashtable]$Rng,[int]$Count) {
    $native=Get-GaShuffled $Rng @($resolvedSlots | Where-Object Native)
    $virtual=Get-GaShuffled $Rng @($resolvedSlots | Where-Object { -not $_.Native })
    if($Count -le $native.Count){return @($native[0..($Count-1)])}
    return @($native + $virtual[0..($Count-$native.Count-1)])
}
function Get-GaDistanceSquared($Left,$Right){$dx=$Left.X-$Right.X;$dy=$Left.Y-$Right.Y;$dz=$Left.Z-$Right.Z;return $dx*$dx+$dy*$dy+$dz*$dz}
function Get-GaAssignedRoutes([array]$Slots){
    $assigned=@();$used=@{}
    for($index=0;$index -lt $Slots.Count;$index++){
        $route=$null
        if(-not $used.ContainsKey($Slots[$index].BaseRoute)){$route=$Slots[$index].BaseRoute}
        if($null -eq $route){foreach($candidate in $routes){if(-not $used.ContainsKey($candidate)){$route=$candidate;break}}}
        if($null -eq $route){
            $farthest=-1;$farthestDistance=-1
            for($prior=0;$prior -lt $index;$prior++){
                $distance=Get-GaDistanceSquared $Slots[$index] $Slots[$prior]
                if($distance -gt $farthestDistance -or ($distance -eq $farthestDistance -and ($farthest -lt 0 -or $assigned[$prior] -clt $assigned[$farthest]))){$farthest=$prior;$farthestDistance=$distance}
            }
            $route=$assigned[$farthest]
        }
        $assigned += $route;$used[$route]=$true
    }
    return $assigned
}
function ConvertTo-GaNumber([double]$Value){return $Value.ToString('G17',[Globalization.CultureInfo]::InvariantCulture)}

function Add-GaCanonicalItem([hashtable]$Items,[string]$Section,[int]$Quantity,[string]$EquippedSlot,[string]$Category) {
    if ($Items.ContainsKey($Section)) {
        $Items[$Section].Quantity += $Quantity
        if (-not $Items[$Section].EquippedSlot) { $Items[$Section].EquippedSlot = $EquippedSlot }
    } else {
        $Items[$Section] = [pscustomobject]@{Section=$Section;Quantity=$Quantity;EquippedSlot=$EquippedSlot;Category=$Category}
    }
}
function Get-GaCanonicalItems([hashtable]$Items) {
    $slotOrder=@{outfit=1;helmet=2;knife=3;weapon_1=4;weapon_2=5}
    $categoryOrder=@{outfit=1;helmet=2;knife=3;weapon=4;ammo=5;medicine=6;grenade=7}
    return @($Items.Values | Sort-Object @{Expression={if($_.EquippedSlot){$slotOrder[$_.EquippedSlot]}else{999}}},@{Expression={$categoryOrder[$_.Category]}},Section)
}
function ConvertTo-GaScalar([string]$Key,$Value) {
    $text=[Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture)
    return "$Key=$($text.Length):$text"
}
function ConvertTo-GaItemsEncoding([array]$Items) {
    $parts=@(ConvertTo-GaScalar 'count' $Items.Count)
    foreach($item in $Items){$parts+=ConvertTo-GaScalar 'section' $item.Section;$parts+=ConvertTo-GaScalar 'quantity' $item.Quantity;$parts+=ConvertTo-GaScalar 'equipped_slot' $(if($item.EquippedSlot){$item.EquippedSlot}else{''})}
    return $parts -join '|'
}
function Get-GaContentHash([string]$Payload) {
    $first=Get-GaDerivedSeed @('ga-fightspec-v8-a',$Payload)
    $second=Get-GaDerivedSeed @('ga-fightspec-v8-b',$Payload)
    return ('{0:x8}{1:x8}' -f $first,$second)
}
$catalogFingerprint='ga-catalog-v9-'+('{0:x8}' -f (Get-GaDerivedSeed @('ga-catalog-v9',[int]$catalog.meta.schema_version,[int]$catalog.meta.revision,[int]$catalog.meta.generator_version)))
$rankBands=@{novice=@(0,9999);trainee=@(10000,19999);experienced=@(20000,29999);veteran=@(40000,49999)}

function ConvertTo-GaFightEncoding($Fight,[bool]$IncludeChecksum) {
    $identity=$Fight.Identity
    $parts=@()
    $parts+=ConvertTo-GaScalar 'schema_version' 8;$parts+=ConvertTo-GaScalar 'session_seed' $identity.SessionSeed;$parts+=ConvertTo-GaScalar 'fight_index' $identity.FightIndex;$parts+=ConvertTo-GaScalar 'generator_version' 10;$parts+=ConvertTo-GaScalar 'catalog_fingerprint' $catalogFingerprint;$parts+=ConvertTo-GaScalar 'layout_version' 2
    if($IncludeChecksum){$parts+=ConvertTo-GaScalar 'content_hash' $identity.ContentHash;$parts+=ConvertTo-GaScalar 'fight_id' $identity.FightId}
    $parts+=ConvertTo-GaScalar 'layout_id' 'rostok_arena_v1';$parts+=ConvertTo-GaScalar 'level' $layout.level;$parts+=ConvertTo-GaScalar 'route_count' $routes.Count
    foreach($route in $routes){$parts+=ConvertTo-GaScalar 'route' $route}
    $parts+=ConvertTo-GaScalar 'actor_spawn_path' $layout.actor_spawn_path;$parts+=ConvertTo-GaScalar 'actor_look_path' $layout.actor_look_path;$parts+=ConvertTo-GaItemsEncoding $Fight.ActorItems
    $parts+=ConvertTo-GaScalar 'opponent_count' $Fight.Opponents.Count
    foreach($opponent in $Fight.Opponents){$parts+=ConvertTo-GaScalar 'slot' $opponent.Slot;$parts+=ConvertTo-GaScalar 'faction' $opponent.Faction;$parts+=ConvertTo-GaScalar 'rank_id' $opponent.RankId;$parts+=ConvertTo-GaScalar 'rank_value' $opponent.RankValue;$parts+=ConvertTo-GaScalar 'profile' $opponent.Profile;$parts+=ConvertTo-GaScalar 'role' $opponent.Role;$parts+=ConvertTo-GaScalar 'spawn_slot_id' $opponent.Physical.Id;$parts+=ConvertTo-GaScalar 'position_x' (ConvertTo-GaNumber $opponent.Physical.X);$parts+=ConvertTo-GaScalar 'position_y' (ConvertTo-GaNumber $opponent.Physical.Y);$parts+=ConvertTo-GaScalar 'position_z' (ConvertTo-GaNumber $opponent.Physical.Z);$parts+=ConvertTo-GaScalar 'level_vertex_id' $opponent.Physical.Lvid;$parts+=ConvertTo-GaScalar 'game_vertex_id' $opponent.Physical.Gvid;$parts+=ConvertTo-GaScalar 'tactical_route' $opponent.Route;$parts+=ConvertTo-GaItemsEncoding $opponent.Items}
    return $parts -join '|'
}

function New-GaEncodedFight([int64]$SessionSeed,[string]$DifficultyId,[int]$FightIndex){
    $normalized=ConvertTo-GaNormalizedSeed $SessionSeed
    $request=[pscustomobject]@{SessionSeed=$normalized;ModeId='skirmish';DifficultyId=$DifficultyId;LayoutId='rostok_arena_v1'}
    $difficulty=$difficultyCatalog[$DifficultyId]
    $count=Get-GaNextInt (New-GaStream $request $FightIndex 'enemy_count') $difficulty.EnemyMin $difficulty.EnemyMax
    $slots=Get-GaSelectedSlots (New-GaStream $request $FightIndex 'spawn_slot') $count
    $assigned=Get-GaAssignedRoutes $slots
    $actorKnife=Select-GaPick (New-GaStream $request $FightIndex 'actor_knife') $knives
    $actor=New-GaPlayerLoadout $request $FightIndex $difficulty $actorKnife $count
    $primaryCount=[math]::Ceiling($count*$difficulty.PrimaryShare/100)
    $base=[math]::Floor($difficulty.EnemyBudget/$count);$remainder=$difficulty.EnemyBudget%$count
    $records=@()
    for($zero=0;$zero -lt $count;$zero++){
        $index=$zero+1;$role=$(if($index-eq 1){'leader'}elseif($index-le $primaryCount){'primary'}else{'secondary'})
        $weaponRole=$(if($role-eq'secondary'){'secondary'}else{'primary'})
        $roleCombinations=Get-GaRoleCombinations $weaponRole
        $slotBudget=[int]$base+$(if($index-le$remainder){1}else{0})
        $minimumLoadout=($roleCombinations|Measure-Object Cost -Minimum).Minimum
        $eligibleProfiles=@($profiles|Where-Object{$_.Cost+$minimumLoadout-le$slotBudget})
        $profileMaximum=($eligibleProfiles|Measure-Object Cost -Maximum).Maximum
        $profile=Select-GaBand (New-GaStream $request $FightIndex "enemy_profile:$index") $eligibleProfiles $profileMaximum
        $knife=Select-GaPick (New-GaStream $request $FightIndex "enemy_knife:$index") $knives
        $gear=New-GaLoadout (New-GaStream $request $FightIndex "enemy_loadout:$index") ($slotBudget-$profile.Cost) $roleCombinations $knife
        $grenades = @(New-GaEnemyGrenades $request $FightIndex $index)
        $records += [pscustomobject]@{Index=$index;Role=$role;Profile=$profile;Gear=$gear;Grenades=$grenades;Physical=$slots[$zero];Route=$assigned[$zero]}
    }
    $medicalAllocations = New-GaEnemyMedical $request $FightIndex $records
    $opponents=@()
    for ($zero=0; $zero -lt $records.Count; $zero++) {
        $record=$records[$zero]; $medical=$medicalAllocations[$zero]; $physical=$record.Physical
        if($record.Profile.Section-notmatch'^gamma_arena_([^_]+)_([^_]+)$'){throw 'Profile does not encode exact faction and rank.'}
        $faction=$Matches[1];$rankId=$Matches[2];$band=$rankBands[$rankId]
        $rankValue=Get-GaNextInt (New-GaStream $request $FightIndex "enemy_numeric_rank:$($record.Index)") $band[0] $band[1]
        $items=@{};$weaponDefinition=@($weapons|Where-Object Section -eq $record.Gear.Weapon)[0]
        Add-GaCanonicalItem $items $record.Gear.Outfit 1 'outfit' 'outfit';Add-GaCanonicalItem $items $record.Gear.Knife 1 'knife' 'knife';Add-GaCanonicalItem $items $record.Gear.Weapon 1 "weapon_$($weaponDefinition.Slot)" 'weapon';Add-GaCanonicalItem $items $record.Gear.Ammo $record.Gear.AmmoBoxes $null 'ammo'
        foreach($section in $medical.Sections){Add-GaCanonicalItem $items $section 1 $null 'medicine'};foreach($section in $record.Grenades){Add-GaCanonicalItem $items $section 1 $null 'grenade'}
        $opponents += [pscustomobject]@{Slot=$record.Index;Faction=$faction;RankId=$rankId;RankValue=$rankValue;Profile=$record.Profile.Section;Role=$record.Role;Physical=$physical;Route=$record.Route;Items=Get-GaCanonicalItems $items}
    }
    $actorItems=@{};$actorWeapon=@($weapons|Where-Object Section -eq $actor.Weapon)[0]
    Add-GaCanonicalItem $actorItems $actor.Outfit 1 'outfit' 'outfit';Add-GaCanonicalItem $actorItems $actor.Knife 1 'knife' 'knife';Add-GaCanonicalItem $actorItems $actor.Weapon 1 "weapon_$($actorWeapon.Slot)" 'weapon';Add-GaCanonicalItem $actorItems $actor.Ammo $actor.AmmoBoxes $null 'ammo';Add-GaCanonicalItem $actorItems $actor.BonusSection 1 $null 'ammo'
    foreach($section in $actor.Medicine){Add-GaCanonicalItem $actorItems $section 1 $null 'medicine'};foreach($section in $actor.Grenades){Add-GaCanonicalItem $actorItems $section 1 $null 'grenade'}
    $identitySeed=$SessionSeed%[int64]4294967296;if($identitySeed-lt0){$identitySeed += [int64]4294967296}
    $fight=[pscustomobject]@{Identity=[pscustomobject]@{SessionSeed=$identitySeed;FightIndex=$FightIndex;ContentHash=$null;FightId=$null};ActorItems=Get-GaCanonicalItems $actorItems;Opponents=$opponents}
    $payload=ConvertTo-GaFightEncoding $fight $false;$fight.Identity.ContentHash=Get-GaContentHash $payload;$fight.Identity.FightId='ga8-'+$fight.Identity.ContentHash
    return ConvertTo-GaFightEncoding $fight $true
}

for($seed=0;$seed-lt 10000;$seed++){
    $id=@('rookie','stalker','veteran','master')[$seed%4];$difficulty=$difficultyCatalog[$id]
    $request=[pscustomobject]@{SessionSeed=(ConvertTo-GaNormalizedSeed $seed);ModeId='skirmish';DifficultyId=$id;LayoutId='rostok_arena_v1'}
    $count=Get-GaNextInt (New-GaStream $request ($seed%32) 'enemy_count') $difficulty.EnemyMin $difficulty.EnemyMax
    $primary=[math]::Ceiling($count*$difficulty.PrimaryShare/100)
    if($count-lt$difficulty.EnemyMin-or$count-gt$difficulty.EnemyMax-or$primary*100-lt$count*$difficulty.PrimaryShare){throw '10k count/share oracle failed'}
}

$requests=@(
    [pscustomobject]@{Seed=[int64]0;Difficulty='rookie';Fight=0},
    [pscustomobject]@{Seed=[int64]1;Difficulty='stalker';Fight=0},
    [pscustomobject]@{Seed=[int64]3735928559;Difficulty='veteran';Fight=7},
    [pscustomobject]@{Seed=[int64]4294967295;Difficulty='master';Fight=31}
)
$expected=@($requests|ForEach-Object{"seed=$($_.Seed),difficulty=$($_.Difficulty),fight=$($_.Fight),stable_encode=$(New-GaEncodedFight $_.Seed $_.Difficulty $_.Fight)"})
if($Verify){
    if(-not(Test-Path -LiteralPath $fixturePath)){throw 'Golden FightSpec v8 fixture is missing'}
    $actual=@(Get-Content -LiteralPath $fixturePath|Where-Object{$_-and-not$_.StartsWith('#')})
    if(@(Compare-Object $expected $actual -SyncWindow 0).Count-ne0){throw 'Golden fixture differs from deterministic v8 reference oracle.'}
    Write-Host 'PASS: golden reference oracle matches fixture'
}elseif($Update){
    $lines = @('# Gamma Arena FightSpec v8 deterministic golden encodings.') + $expected
    [IO.File]::WriteAllText($fixturePath, (@($lines) -join "`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "Updated golden fixture: $fixturePath"
}else{$expected}
