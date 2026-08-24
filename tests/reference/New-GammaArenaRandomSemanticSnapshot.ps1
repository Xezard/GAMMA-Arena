[CmdletBinding()]
param([switch]$Verify, [switch]$Update)

$ErrorActionPreference = 'Stop'
if ($Verify -and $Update) { throw 'Choose either -Verify or -Update.' }
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$snapshotPath = Join-Path $repoRoot 'tests\fixtures\golden-random-selections-v7.txt'
$v5Path = Join-Path $repoRoot 'tests\fixtures\golden-fights-v5.txt'

function Read-GaLtx([string]$Path) {
    $sections = @{}; $current = $null
    foreach ($raw in Get-Content -LiteralPath $Path) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith(';')) { continue }
        if ($line -match '^\[([^\]]+)\]$') {
            $current = $Matches[1]
            if ($sections.ContainsKey($current)) { throw "Duplicate LTX section $current in $Path" }
            $sections[$current] = @{}
        } elseif ($null -ne $current -and $line -match '^([^=]+?)\s*=\s*(.*?)\s*$') {
            $key = $Matches[1].Trim()
            if ($sections[$current].ContainsKey($key)) { throw "Duplicate LTX key $current.$key in $Path" }
            $sections[$current][$key] = $Matches[2].Trim()
        } else { throw "Unsupported LTX line '$raw' in $Path" }
    }
    return $sections
}

$catalog = Read-GaLtx (Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx')
$difficultyLtx = Read-GaLtx (Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx')
$layoutLtx = Read-GaLtx (Join-Path $repoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx')
if ([int]$catalog.meta.schema_version -ne 6 -or [int]$catalog.meta.revision -ne 7 -or [int]$catalog.meta.generator_version -ne 7 -or
    [int]$difficultyLtx.meta.schema_version -ne 4 -or [int]$difficultyLtx.meta.revision -ne 5 -or
    [int]$layoutLtx.meta.schema_version -ne 2 -or [int]$layoutLtx.meta.revision -ne 2) {
    throw 'Random semantic reference requires catalog 7, difficulty 5, and layout 2 LTX inputs.'
}

$difficultyManifest = @{
    rookie = @(1,2,3,25,7,4,50,35,50,15,0,50,30,15,5,0,55,30,10,5,0)
    stalker = @(2,3,5,50,10,5,60,25,50,25,0,25,35,20,18,2,30,40,20,9,1)
    veteran = @(3,5,7,75,13,6,75,20,45,30,5,10,25,20,38,7,15,30,25,25,5)
    master = @(4,7,10,100,15,8,80,15,40,35,10,5,15,15,50,15,10,25,25,35,5)
}
$difficulties = @{}
foreach ($id in @('rookie','stalker','veteran','master')) {
    $entry = $difficultyLtx["ga_difficulty_$id"]
    $values = @([int]$entry.tier,[int]$entry.enemy_min,[int]$entry.enemy_max,[int]$entry.enemy_total_budget,[int]$entry.player_gear_budget,[int]$entry.player_medical_budget,[int]$entry.primary_share_percent,[int]$entry.medical_weight_bleed,[int]$entry.medical_weight_health,[int]$entry.medical_weight_boost,[int]$entry.medical_weight_rare,[int]$entry.weapon_weight_pistol,[int]$entry.weapon_weight_smg,[int]$entry.weapon_weight_shotgun,[int]$entry.weapon_weight_rifle,[int]$entry.weapon_weight_sniper,[int]$entry.armor_weight_light,[int]$entry.armor_weight_medium,[int]$entry.armor_weight_scientific,[int]$entry.armor_weight_heavy,[int]$entry.armor_weight_powered_exo)
    if (@(Compare-Object $difficultyManifest[$id] $values -SyncWindow 0).Count -ne 0) { throw "Difficulty $id differs from the reviewed semantic manifest." }
    $difficulties[$id] = [pscustomobject]@{ Tier=$values[0]; EnemyMin=$values[1]; EnemyMax=$values[2]; EnemyBudget=$values[3]; PlayerBudget=$values[4]+1; PlayerMedicalBudget=$values[5]; PrimaryShare=$values[6]; MedicalWeights=@{bleed=$values[7];health=$values[8];boost=$values[9];rare=$values[10]}; WeaponWeights=@{w_pistol=$values[11];w_smg=$values[12];w_shotgun=$values[13];w_rifle=$values[14];w_sniper=$values[15]}; ArmorWeights=@{light=$values[16];medium=$values[17];scientific=$values[18];heavy=$values[19];powered_exo=$values[20]} }
}

$layout = $layoutLtx.ga_layout_rostok_arena_v1
$routes = @($layout.opponent_spawn_paths.Split(',') | ForEach-Object { $_.Trim() })
if ($routes.Count -ne 6 -or [int]$layout.virtual_capacity -ne 10) { throw 'Layout differs from the reviewed semantic manifest.' }

$pmModulus = [int64]2147483647; $pmStateModulus = [int64]2147483646
function ConvertTo-GaSeed([int64]$Seed) {
    $unsigned = $Seed % [int64]4294967296; if ($unsigned -lt 0) { $unsigned += [int64]4294967296 }
    if ($unsigned -eq 0) { return [int64]1 }
    $value = $unsigned % $pmStateModulus; if ($value -eq 0) { return $pmStateModulus }; return $value
}
function Get-GaDerivedSeed([object[]]$Parts) {
    $hash = [int64]0
    foreach ($part in $Parts) {
        $prefix = if ($part -is [string]) { 'string:' } else { 'number:' }
        $text = $prefix + [Convert]::ToString($part, [Globalization.CultureInfo]::InvariantCulture)
        $encoded = ([string]$text.Length) + ':' + $text
        foreach ($byte in [Text.Encoding]::ASCII.GetBytes($encoded)) { $hash = ($hash * 131 + $byte) % $pmStateModulus }
    }
    return ConvertTo-GaSeed $hash
}
function New-GaRng([object[]]$Parts) { return @{State=(Get-GaDerivedSeed $Parts)} }
function Get-GaRaw([hashtable]$Rng) { $next=48271*($Rng.State%44488)-3399*[math]::Floor($Rng.State/44488); if($next-le0){$next+=$pmModulus}; $Rng.State=[int64]$next; return $Rng.State }
function Get-GaInt([hashtable]$Rng,[int]$Minimum,[int]$Maximum) { return $Minimum+(Get-GaRaw $Rng)%($Maximum-$Minimum+1) }
function New-GaStream($Request,[int]$FightIndex,[string]$Tag,[int]$Epoch=6) { return New-GaRng @($Request.ModeId,$Request.DifficultyId,[int64]$Request.SessionSeed,$FightIndex,$Epoch,2,$Tag) }
function Select-GaPick([hashtable]$Rng,[array]$Values) { return $Values[(Get-GaInt $Rng 1 $Values.Count)-1] }
function Select-GaBand([hashtable]$Rng,[array]$Values,[int]$Maximum) {
    $affordable=@($Values|Where-Object{$_.Cost-le$Maximum}); if($affordable.Count-eq0){throw "No affordable semantic candidate for $Maximum."}
    $threshold=[math]::Ceiling($Maximum*70/100); $band=@($affordable|Where-Object{$_.Cost-ge$threshold})
    if($band.Count-eq0){$highest=($affordable|Measure-Object Cost -Maximum).Maximum;$band=@($affordable|Where-Object{$_.Cost-eq$highest})}
    return Select-GaPick $Rng $band
}
function Get-GaShuffle([hashtable]$Rng,[array]$Values) { $copy=@($Values);for($i=$copy.Count-1;$i-ge1;$i--){$target=(Get-GaInt $Rng 1 ($i+1))-1;$swap=$copy[$i];$copy[$i]=$copy[$target];$copy[$target]=$swap};return $copy }

$ammoCosts=@{}; foreach($id in @($catalog.ammo.ids.Split(',')|ForEach-Object{$_.Trim()}|Sort-Object)){$entry=$catalog["ammo_$id"];$ammoCosts[$entry.section]=[int]$entry.cost}
$weapons=@($catalog.weapons.ids.Split(',')|ForEach-Object{$_.Trim()}|Sort-Object|ForEach-Object{$entry=$catalog["weapon_$_"];[pscustomobject]@{Section=$entry.section;Ammo=$entry.ammo;Cost=[int]$entry.cost;Min=[int]$entry.ammo_box_min;Max=[int]$entry.ammo_box_max;Kind=$entry.kind}})
$outfits=@($catalog.outfits.ids.Split(',')|ForEach-Object{$_.Trim()}|Sort-Object|ForEach-Object{$entry=$catalog["outfit_$_"];[pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost;Armor=$entry.armor_class}})
$profiles=@($catalog.profiles.ids.Split(',')|ForEach-Object{$_.Trim()}|Sort-Object|ForEach-Object{$entry=$catalog["profile_$_"];[pscustomobject]@{Section=$entry.section;Cost=[int]$entry.cost}})
$knives=@($catalog.knives.ids.Split(',')|ForEach-Object{$_.Trim()}|Sort-Object|ForEach-Object{$catalog["knife_$_"].section})
$bandageCost=[int]$catalog.consumable_bandage.cost
$medical=@($catalog.medical_items.ids.Split(',')|ForEach-Object{$_.Trim()}|ForEach-Object{$entry=$catalog["medical_$_"];[pscustomobject]@{Section=$entry.section;Category=$entry.category;ActorCost=[int]$entry.actor_cost;NpcCost=[int]$entry.npc_cost;MinTier=[int]$entry.min_tier;MaxCount=[int]$entry.max_count}}|Sort-Object Section)
$medicalBySection=@{};foreach($item in $medical){$medicalBySection[$item.Section]=$item}
$combinations=@();foreach($weapon in $weapons){foreach($outfit in $outfits){foreach($boxes in $weapon.Min..$weapon.Max){$combinations += [pscustomobject]@{Weapon=$weapon.Section;Ammo=$weapon.Ammo;AmmoBoxes=$boxes;Outfit=$outfit.Section;Cost=$weapon.Cost+$ammoCosts[$weapon.Ammo]*$boxes+$outfit.Cost+$bandageCost;Kind=$weapon.Kind}}}}
$combinations=@($combinations|Sort-Object Cost,Weapon,Outfit,AmmoBoxes)

function Get-GaRoleCombinations([string]$Role) { return @($combinations|Where-Object{if($Role-eq'secondary'){$_.Kind-eq'w_pistol'}else{$_.Kind-ne'w_pistol'}}) }
function Select-GaWeighted($Request,[int]$FightIndex,$Difficulty,[array]$Pairs) {
    $total=($Pairs|Measure-Object Weight -Sum).Sum;$draw=Get-GaInt (New-GaStream $Request $FightIndex 'actor_class_pair') 1 $total;$sum=0
    foreach($pair in $Pairs){$sum+=$pair.Weight;if($draw-le$sum){return $pair}};throw 'Weighted pair selection exhausted its range.'
}
function New-GaActorGear($Request,[int]$FightIndex,$Difficulty) {
    $pairs=@();foreach($weaponClass in @('w_pistol','w_smg','w_shotgun','w_rifle','w_sniper')){foreach($armorClass in @('light','medium','scientific','heavy','powered_exo')){
        $available=$false;foreach($weapon in $weapons){if($weapon.Kind-ne$weaponClass){continue};foreach($boxes in $weapon.Min..$weapon.Max){if(@($outfits|Where-Object{$_.Armor-eq$armorClass-and$weapon.Cost+$ammoCosts[$weapon.Ammo]*$boxes+$_.Cost+$bandageCost-le$Difficulty.PlayerBudget}).Count-gt0){$available=$true;break}};if($available){break}}
        $weight=$Difficulty.WeaponWeights[$weaponClass]*$Difficulty.ArmorWeights[$armorClass];if($available-and$weight-gt0){$pairs += [pscustomobject]@{WeaponClass=$weaponClass;ArmorClass=$armorClass;Weight=$weight}}
    }}
    $pair=Select-GaWeighted $Request $FightIndex $Difficulty $pairs
    $eligibleWeapons=@($weapons|Where-Object{$weapon=$_;$weapon.Kind-eq$pair.WeaponClass-and@($weapon.Min..$weapon.Max|Where-Object{$boxes=$_;@($outfits|Where-Object{$_.Armor-eq$pair.ArmorClass-and$weapon.Cost+$ammoCosts[$weapon.Ammo]*$boxes+$_.Cost+$bandageCost-le$Difficulty.PlayerBudget}).Count-gt0}).Count-gt0})
    $weapon=Select-GaPick (New-GaStream $Request $FightIndex 'actor_weapon') $eligibleWeapons
    $boxes=Select-GaPick (New-GaStream $Request $FightIndex 'actor_ammo_boxes') @($weapon.Min..$weapon.Max|Where-Object{$count=$_;@($outfits|Where-Object{$_.Armor-eq$pair.ArmorClass-and$weapon.Cost+$ammoCosts[$weapon.Ammo]*$count+$_.Cost+$bandageCost-le$Difficulty.PlayerBudget}).Count-gt0})
    $outfit=Select-GaPick (New-GaStream $Request $FightIndex 'actor_outfit') @($outfits|Where-Object{$_.Armor-eq$pair.ArmorClass-and$weapon.Cost+$ammoCosts[$weapon.Ammo]*$boxes+$_.Cost+$bandageCost-le$Difficulty.PlayerBudget})
    $bonusDraw=Get-GaInt (New-GaStream $Request $FightIndex 'actor_bonus_ammo_category') 1 100
    $requestedCategory=if($bonusDraw-le60){'standard'}elseif($bonusDraw-le75){'special'}else{'armor_piercing'}
    $bonusSection=$weapon.Ammo;$resolvedCategory='standard'
    if($requestedCategory-eq'standard'){$bonusSection=Select-GaPick (New-GaStream $Request $FightIndex 'actor_bonus_ammo_section') @($weapon.Ammo)}
    return [pscustomobject]@{Weapon=$weapon.Section;Ammo=$weapon.Ammo;AmmoBoxes=$boxes;Outfit=$outfit.Section;BonusSection=$bonusSection;BonusRequestedCategory=$requestedCategory;BonusResolvedCategory=$resolvedCategory;BonusBoxes=1}
}
function Select-GaMedicalCategory([hashtable]$Rng,[hashtable]$Weights,[hashtable]$Available) { $total=0;foreach($id in @('bleed','health','boost','rare')){if($Available[$id]-and$Weights[$id]-gt0){$total+=$Weights[$id]}};if($total-le0){return $null};$draw=Get-GaInt $Rng 1 $total;$sum=0;foreach($id in @('bleed','health','boost','rare')){if($Available[$id]-and$Weights[$id]-gt0){$sum+=$Weights[$id];if($draw-le$sum){return $id}}} }
function New-GaActorMedical($Request,[int]$FightIndex,$Difficulty) {
    $sections=[Collections.Generic.List[string]]::new();$sections.Add('bandage');$cost=$medicalBySection.bandage.ActorCost;$sectionCounts=@{bandage=1};$categoryCounts=@{bleed=1}
    for($stage=0;$stage-le3;$stage++){$required=$stage-eq0;$remaining=$Difficulty.PlayerMedicalBudget-$cost;$byCategory=@{bleed=@();health=@();boost=@();rare=@()};$available=@{}
        foreach($item in $medical){$count=if($sectionCounts.ContainsKey($item.Section)){$sectionCounts[$item.Section]}else{0};$categoryCount=if($categoryCounts.ContainsKey($item.Category)){$categoryCounts[$item.Category]}else{0};$cap=switch($item.Category){health{2}boost{1}rare{1}default{999}};$healing=$item.Category-eq'health'-or$item.Category-eq'rare';if($item.MinTier-le$Difficulty.Tier-and$item.ActorCost-le$remaining-and$count-lt$item.MaxCount-and$categoryCount-lt$cap-and(-not$required-or$healing)){$byCategory[$item.Category]=@($byCategory[$item.Category])+$item;$available[$item.Category]=$true}}
        $categoryTag=if($required){'actor_medical_required_category'}else{"actor_medical_optional_category:$stage"};$sectionTag=if($required){'actor_medical_required_section'}else{"actor_medical_optional_section:$stage"};$category=Select-GaMedicalCategory (New-GaStream $Request $FightIndex $categoryTag 1) $Difficulty.MedicalWeights $available
        if($null-eq$category){if($required){throw 'No required healer fits.'};break};$item=Select-GaPick (New-GaStream $Request $FightIndex $sectionTag 1) @($byCategory[$category]|Sort-Object Section);$sections.Add($item.Section);$cost+=$item.ActorCost;$sectionCounts[$item.Section]=$count=if($sectionCounts.ContainsKey($item.Section)){$sectionCounts[$item.Section]+1}else{1};$categoryCounts[$item.Category]=if($categoryCounts.ContainsKey($item.Category)){$categoryCounts[$item.Category]+1}else{1};if($sections.Count-ge5){break}
    };return @($sections)
}

$slots=@();for($index=1;$index-le10;$index++){$route=$routes[($index-1)%$routes.Count];$slots += [pscustomobject]@{Id=if($index-le6){"native:$route"}else{"virtual:$($index-6)"};BaseRoute=$route;Native=$index-le6;X=$index*4;Z=if($index%2-eq0){4}else{-4}}}
function Get-GaSlots([hashtable]$Rng,[int]$Count){$native=Get-GaShuffle $Rng @($slots|Where-Object Native);$virtual=Get-GaShuffle $Rng @($slots|Where-Object{-not$_.Native});if($Count-le$native.Count){return @($native[0..($Count-1)])};return @($native+$virtual[0..($Count-$native.Count-1)])}
function Get-GaRoutes([array]$Selected){$assigned=@();$used=@{};for($i=0;$i-lt$Selected.Count;$i++){$route=$null;if(-not$used.ContainsKey($Selected[$i].BaseRoute)){$route=$Selected[$i].BaseRoute};if($null-eq$route){foreach($candidate in $routes){if(-not$used.ContainsKey($candidate)){$route=$candidate;break}}};if($null-eq$route){$far=-1;$distance=-1;for($prior=0;$prior-lt$i;$prior++){$dx=$Selected[$i].X-$Selected[$prior].X;$dz=$Selected[$i].Z-$Selected[$prior].Z;$value=$dx*$dx+$dz*$dz;if($value-gt$distance-or($value-eq$distance-and($far-lt0-or$assigned[$prior]-clt$assigned[$far]))){$far=$prior;$distance=$value}};$route=$assigned[$far]};$assigned+=$route;$used[$route]=$true};return $assigned}
function New-GaEnemyMedical($Request,[int]$FightIndex,[array]$Records){$count=$Records.Count;$medkitCount=Get-GaInt (New-GaStream $Request $FightIndex 'enemy_medical_mix' 1) 1 ([math]::Min([math]::Floor($count/2),[math]::Ceiling($count/4)));$bandageCount=$count-2*$medkitCount;$allocations=@();for($i=0;$i-lt$count;$i++){$allocations+=,[Collections.Generic.List[string]]::new()};foreach($pair in @(@('medkit',$medkitCount),@('bandage',$bandageCount))){for($itemIndex=1;$itemIndex-le$pair[1];$itemIndex++){$eligible=@();$total=0;for($i=0;$i-lt$count;$i++){if($allocations[$i]-contains$pair[0]){continue};$weight=switch($Records[$i].Role){leader{4}primary{2}secondary{1}};$total+=$weight;$eligible += [pscustomobject]@{Index=$i;Weight=$weight}};$draw=Get-GaInt (New-GaStream $Request $FightIndex "enemy_medical_recipient:$($pair[0]):$itemIndex" 1) 1 $total;$sum=0;foreach($candidate in $eligible){$sum+=$candidate.Weight;if($draw-le$sum){$allocations[$candidate.Index].Add($pair[0]);break}}}};return $allocations}

function New-GaSemantic([int64]$Seed,[string]$DifficultyId,[int]$FightIndex){
    $request=[pscustomobject]@{SessionSeed=(ConvertTo-GaSeed $Seed);ModeId='skirmish';DifficultyId=$DifficultyId};$difficulty=$difficulties[$DifficultyId]
    $count=Get-GaInt (New-GaStream $request $FightIndex 'enemy_count') $difficulty.EnemyMin $difficulty.EnemyMax;$selected=Get-GaSlots (New-GaStream $request $FightIndex 'spawn_slot') $count;$assigned=Get-GaRoutes $selected
    $actor=New-GaActorGear $request $FightIndex $difficulty;$actorKnife=Select-GaPick (New-GaStream $request $FightIndex 'actor_knife') $knives;$actorMedical=New-GaActorMedical $request $FightIndex $difficulty
    $primary=[math]::Ceiling($count*$difficulty.PrimaryShare/100);$base=[math]::Floor($difficulty.EnemyBudget/$count);$remainder=$difficulty.EnemyBudget%$count;$records=@()
    for($zero=0;$zero-lt$count;$zero++){$index=$zero+1;$role=if($index-eq1){'leader'}elseif($index-le$primary){'primary'}else{'secondary'};$roleCombinations=Get-GaRoleCombinations $(if($role-eq'secondary'){'secondary'}else{'primary'});$budget=$base+$(if($index-le$remainder){1}else{0});$minimum=($roleCombinations|Measure-Object Cost -Minimum).Minimum;$eligible=@($profiles|Where-Object{$_.Cost+$minimum-le$budget});$profile=Select-GaBand (New-GaStream $request $FightIndex "enemy_profile:$index") $eligible (($eligible|Measure-Object Cost -Maximum).Maximum);$gear=Select-GaBand (New-GaStream $request $FightIndex "enemy_loadout:$index") $roleCombinations ($budget-$profile.Cost);$knife=Select-GaPick (New-GaStream $request $FightIndex "enemy_knife:$index") $knives;$records += [pscustomobject]@{Index=$index;Role=$role;Profile=$profile;Gear=$gear;Knife=$knife;Slot=$selected[$zero];Route=$assigned[$zero]}}
    $enemyMedical=New-GaEnemyMedical $request $FightIndex $records;$opponents=@();for($i=0;$i-lt$records.Count;$i++){$record=$records[$i];if($record.Profile.Section-notmatch'^gamma_arena_([^_]+)_'){throw 'Reviewed profile does not encode faction.'};$opponents += "$($record.Index):$($Matches[1]),$($record.Profile.Section),$($record.Gear.Weapon),$($record.Gear.Ammo),$($record.Gear.AmmoBoxes),$($record.Gear.Outfit),$($record.Knife),medical:$($enemyMedical[$i]-join'+'),$($record.Slot.Id),$($record.Route)"}
    return "seed=$Seed,difficulty=$DifficultyId,fight=$FightIndex|actor=$($actor.Weapon),$($actor.Ammo),$($actor.AmmoBoxes),$($actor.Outfit),$actorKnife,medical:$($actorMedical-join'+'),bonus:$($actor.BonusSection):$($actor.BonusRequestedCategory):$($actor.BonusResolvedCategory):$($actor.BonusBoxes)|opponents=|$($opponents-join'|')"
}

function ConvertFrom-GaV5Projection([string]$Line){
    if($Line-notmatch'^seed=([^,]+),difficulty=([^,]+),fight=([^,]+),stable_encode=(.*)$'){throw 'Malformed v5 fixture line.'};$seed=$Matches[1];$difficulty=$Matches[2];$fight=$Matches[3];$encoded=$Matches[4]
    if($encoded-notmatch'\|actor=([^|]+)\|opponents=\|(.*)\|diagnostic='){throw 'Malformed v5 semantic payload.'};$actorFields=$Matches[1].Split(',');$opponentText=$Matches[2];$actor="$($actorFields[2]),$($actorFields[3]),$($actorFields[4]),$($actorFields[5]),$($actorFields[6]),$($actorFields[7]),$($actorFields[11])"
    $projected=@();foreach($encodedOpponent in $opponentText.Split('|')){$fields=($encodedOpponent-replace'^\d+:','').Split(',');$profile=$fields[9];$cursor=10;$faction=$null;if($fields[$cursor]-notmatch'^\d+$'){$faction=$fields[$cursor];$cursor++};if($null-eq$faction){if($profile-notmatch'^gamma_arena_([^_]+)_'){throw 'v5 profile does not encode faction.'};$faction=$Matches[1]};$cursor++;$projected += "$($fields[0]):$faction,$profile,$($fields[$cursor]),$($fields[$cursor+1]),$($fields[$cursor+2]),$($fields[$cursor+3]),$($fields[$cursor+4]),$($fields[$cursor+5]),$($fields[1]),$($fields[7])"}
    return "seed=$seed,difficulty=$difficulty,fight=$fight|actor=$actor|opponents=|$($projected-join'|')"
}

$requests=@(@([int64]0,'rookie',0),@([int64]1,'stalker',0),@([int64]3735928559,'veteran',7),@([int64]4294967295,'master',31))
$expected=@($requests|ForEach-Object{New-GaSemantic $_[0] $_[1] $_[2]})
if(Test-Path -LiteralPath $v5Path){$v5Projection=@(Get-Content -LiteralPath $v5Path|Where-Object{$_-and-not$_.StartsWith('#')}|ForEach-Object{ConvertFrom-GaV5Projection $_});if(@(Compare-Object $expected $v5Projection -SyncWindow 0).Count-ne0){throw 'Independent LTX semantics differ from the reviewed v5 projection.'}}
if($Verify){if(-not(Test-Path -LiteralPath $snapshotPath)){throw 'Frozen random semantic snapshot is missing.'};$actual=@(Get-Content -LiteralPath $snapshotPath|Where-Object{$_-and-not$_.StartsWith('#')});if(@(Compare-Object $expected $actual -SyncWindow 0).Count-ne0){throw 'Frozen random semantic snapshot differs from independent LTX semantics.'};Write-Host 'PASS: frozen random semantics match independent LTX reference'}elseif($Update){$lines=@('# Gamma Arena format-neutral random semantic selections v7.')+$expected;[IO.File]::WriteAllText($snapshotPath,($lines-join"`n")+"`n",(New-Object Text.UTF8Encoding($false)));Write-Host "Updated random semantic snapshot: $snapshotPath"}else{$expected}
