[CmdletBinding()]
param([switch]$Verify)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixturePath = Join-Path $repoRoot 'tests\fixtures\golden-fights-v3.txt'
$catalogPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$difficultyPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx'
$layoutPath = Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx'
$generatorPath = Join-Path $repoRoot 'src\gamedata\scripts\gamma_arena_generator.script'

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
$generatorText = Get-Content -Raw -LiteralPath $generatorPath
if ([int]$catalog.meta.schema_version -ne 4 -or [int]$catalog.meta.revision -ne 4 -or [int]$catalog.meta.generator_version -ne 5 -or
    [int]$difficulties.meta.schema_version -ne 3 -or [int]$difficulties.meta.revision -ne 3 -or
    [int]$layouts.meta.schema_version -ne 2 -or [int]$layouts.meta.revision -ne 2 -or
    $generatorText -notmatch 'schema_version\s*=\s*3' -or $generatorText -notmatch 'FightSpecV3') {
    throw 'Reference oracle requires catalog v4, generator v5, difficulty v3, layout v2, and FightSpec v3.'
}

$difficultyManifest = @{
    rookie = @(2,3,25,8,50,50,30,15,5,0,55,30,10,5,0)
    stalker = @(3,5,50,11,60,25,35,20,18,2,30,40,20,9,1)
    veteran = @(5,7,75,14,75,10,25,20,38,7,15,30,25,25,5)
    master = @(7,10,100,16,80,5,15,15,50,15,5,20,20,35,20)
}
$difficultyCatalog = @{}
foreach ($id in @('rookie','stalker','veteran','master')) {
    $entry = $difficulties["ga_difficulty_$id"]
    if ($null -eq $entry -or $entry.Count -ne 15) { throw "Difficulty $id must expose exactly fifteen v3 fields." }
    $actual = @([int]$entry.enemy_min,[int]$entry.enemy_max,[int]$entry.enemy_total_budget,[int]$entry.player_loadout_budget,[int]$entry.primary_share_percent,[int]$entry.weapon_weight_pistol,[int]$entry.weapon_weight_smg,[int]$entry.weapon_weight_shotgun,[int]$entry.weapon_weight_rifle,[int]$entry.weapon_weight_sniper,[int]$entry.armor_weight_light,[int]$entry.armor_weight_medium,[int]$entry.armor_weight_scientific,[int]$entry.armor_weight_heavy,[int]$entry.armor_weight_powered_exo)
    if (@(Compare-Object $difficultyManifest[$id] $actual -SyncWindow 0).Count -ne 0) { throw "Difficulty $id differs from the v3 semantic manifest." }
    $difficultyCatalog[$id] = [pscustomobject]@{Id=$id;EnemyMin=$actual[0];EnemyMax=$actual[1];EnemyBudget=$actual[2];PlayerBudget=$actual[3];PrimaryShare=$actual[4];WeaponWeights=@{w_pistol=$actual[5];w_smg=$actual[6];w_shotgun=$actual[7];w_rifle=$actual[8];w_sniper=$actual[9]};ArmorWeights=@{light=$actual[10];medium=$actual[11];scientific=$actual[12];heavy=$actual[13];powered_exo=$actual[14]}}
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
function New-GaStream([pscustomobject]$Request, [int]$FightIndex, [string]$Tag) {
    return New-GaRng @($Request.ModeId,$Request.DifficultyId,[int64]$Request.SessionSeed,$FightIndex,5,4,2,$Tag)
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
$weapons = @($catalog.weapons.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object {
    $entry=$catalog["weapon_$_"]
    [pscustomobject]@{Section=$entry.section;Ammo=$entry.ammo;Cost=[int]$entry.cost;AmmoBoxMin=[int]$entry.ammo_box_min;AmmoBoxMax=[int]$entry.ammo_box_max;Kind=$entry.kind;Slot=[int]$entry.slot}
})
$outfits = @($catalog.outfits.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalog["outfit_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost;ArmorClass=$entry.armor_class} })
$profiles = @($catalog.profiles.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $entry=$catalog["profile_$_"]; [pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost} })
$knives = @($catalog.knives.ids.Split(',') | ForEach-Object { $_.Trim() } | Sort-Object | ForEach-Object { $catalog["knife_$_"].section })
$bandageCost = [int]$catalog.consumable_bandage.cost
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
function New-GaLoadout([hashtable]$Rng, [int]$Budget, [array]$Candidates, [string]$Knife) {
    $choice = Select-GaBand $Rng $Candidates $Budget
    return [pscustomobject]@{Encoded="$($choice.Weapon),$($choice.Ammo),$($choice.AmmoBoxes),$($choice.Outfit),$Knife,bandage,$($choice.Cost)";Cost=[int]$choice.Cost;Kind=$choice.Kind}
}
function New-GaPlayerLoadout([pscustomobject]$Request, [int]$FightIndex, [pscustomobject]$Difficulty, [string]$Knife) {
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
    return [pscustomobject]@{Encoded="$($weapon.Section),$($weapon.Ammo),$ammoBoxes,$($outfit.Section),$Knife,bandage,$cost";Cost=[int]$cost;Kind=$weapon.Kind}
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

function New-GaEncodedFight([int64]$SessionSeed,[string]$DifficultyId,[int]$FightIndex){
    $normalized=ConvertTo-GaNormalizedSeed $SessionSeed
    $request=[pscustomobject]@{SessionSeed=$normalized;ModeId='skirmish';DifficultyId=$DifficultyId;LayoutId='rostok_arena_v1'}
    $difficulty=$difficultyCatalog[$DifficultyId]
    $count=Get-GaNextInt (New-GaStream $request $FightIndex 'enemy_count') $difficulty.EnemyMin $difficulty.EnemyMax
    $slots=Get-GaSelectedSlots (New-GaStream $request $FightIndex 'spawn_slot') $count
    $assigned=Get-GaAssignedRoutes $slots
    $actorKnife=Select-GaPick (New-GaStream $request $FightIndex 'actor_knife') $knives
    $actor=New-GaPlayerLoadout $request $FightIndex $difficulty $actorKnife
    $primaryCount=[math]::Ceiling($count*$difficulty.PrimaryShare/100)
    $base=[math]::Floor($difficulty.EnemyBudget/$count);$remainder=$difficulty.EnemyBudget%$count
    $opponents=@()
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
        $physical=$slots[$zero]
        $position="$(ConvertTo-GaNumber $physical.X),$(ConvertTo-GaNumber $physical.Y),$(ConvertTo-GaNumber $physical.Z)"
        $opponents += "${index}:$index,$($physical.Id),$position,$($physical.Lvid),$($physical.Gvid),$($assigned[$zero]),$role,$($profile.Section),$($profile.Cost),$($gear.Encoded),$($profile.Cost+$gear.Cost)"
    }
    $fields=@('schema_version=3','generator_version=5','catalog_revision=4','layout_version=2',"session_seed=$normalized","fight_index=$FightIndex","fight_id=ga-$normalized-$FightIndex-g5-c4-l2",'mode_id=skirmish',"difficulty_id=$DifficultyId",'layout_id=rostok_arena_v1',"level=$($layout.level)","actor=$($layout.actor_spawn_path),$($layout.actor_look_path),$($actor.Encoded)",'opponents=')+$opponents+"diagnostic=FightSpecV3 skirmish $DifficultyId #$FightIndex"
    return $fields -join '|'
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
if((New-GaEncodedFight 0 veteran 7)-cne(New-GaEncodedFight 1 veteran 7)){throw 'Normalized seed aliases must match'}
if($Verify){
    if(-not(Test-Path -LiteralPath $fixturePath)){throw 'Golden FightSpec v3 fixture is missing'}
    $actual=@(Get-Content -LiteralPath $fixturePath|Where-Object{$_-and-not$_.StartsWith('#')})
    if(@(Compare-Object $expected $actual -SyncWindow 0).Count-ne0){throw 'Golden fixture differs from deterministic v3 reference oracle.'}
    Write-Host 'PASS: golden reference oracle matches fixture'
}else{$expected}
