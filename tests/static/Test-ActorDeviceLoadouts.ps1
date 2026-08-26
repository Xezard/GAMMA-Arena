[CmdletBinding()]
param([string]$RepoRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$CatalogLoaderPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
$DeviceGeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_device_generator.script'
$GeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
$ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
$BootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
$GeneratorTestsPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script'
$RuntimeTestsPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script'

foreach ($Path in @($CatalogPath, $CatalogLoaderPath, $DeviceGeneratorPath, $GeneratorPath, $ValidatorPath, $BootstrapPath, $CompatPath, $GeneratorTestsPath, $RuntimeTestsPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Actor device integration file is missing: $Path" }
}

$Catalog = Get-Content -Raw -LiteralPath $CatalogPath
$CatalogLoader = Get-Content -Raw -LiteralPath $CatalogLoaderPath
$DeviceGenerator = Get-Content -Raw -LiteralPath $DeviceGeneratorPath
$Generator = Get-Content -Raw -LiteralPath $GeneratorPath
$Validator = Get-Content -Raw -LiteralPath $ValidatorPath
$Bootstrap = Get-Content -Raw -LiteralPath $BootstrapPath
$Compat = Get-Content -Raw -LiteralPath $CompatPath
$GeneratorTests = Get-Content -Raw -LiteralPath $GeneratorTestsPath
$RuntimeTests = Get-Content -Raw -LiteralPath $RuntimeTestsPath

if ($Catalog -notmatch '(?ms)^\[meta\].*?^schema_version\s*=\s*9\s*$.*?^revision\s*=\s*10\s*$.*?^generator_version\s*=\s*10\s*$') {
    throw 'Actor device catalog must use schema/revision/generator 9/10/10'
}
if ($Catalog -notmatch '(?ms)^\[devices\]\s*^ids\s*=\s*headlamp,nv_gen1,nv_gen2,nv_gen3\s*$') {
    throw 'Actor device catalog exact id allowlist is missing'
}
foreach ($Expected in @(
    '(?ms)^\[device_headlamp\].*?^section\s*=\s*device_torch_dummy\s*$.*?^kind\s*=\s*headlamp\s*$.*?^weight\s*=\s*50\s*$.*?^nv_effect\s*=\s*none\s*$',
    '(?ms)^\[device_nv_gen1\].*?^section\s*=\s*device_torch_nv_1\s*$.*?^kind\s*=\s*gen1\s*$.*?^weight\s*=\s*25\s*$.*?^nv_effect\s*=\s*nightvision_1\s*$',
    '(?ms)^\[device_nv_gen2\].*?^section\s*=\s*device_torch_nv_2\s*$.*?^kind\s*=\s*gen2\s*$.*?^weight\s*=\s*18\s*$.*?^nv_effect\s*=\s*nightvision_2\s*$',
    '(?ms)^\[device_nv_gen3\].*?^section\s*=\s*device_torch_nv_3\s*$.*?^kind\s*=\s*gen3\s*$.*?^weight\s*=\s*7\s*$.*?^nv_effect\s*=\s*nightvision_3\s*$'
)) {
    if ($Catalog -notmatch $Expected) { throw 'Actor device exact catalog record is missing or malformed' }
}
foreach ($Marker in @('device_list','GA_DEVICE_EFFECTIVE_INVALID','TORCH_S','nightvision_1','nightvision_2','nightvision_3')) {
    if (-not $CatalogLoader.Contains($Marker)) { throw "Actor device catalog loader contract is missing: $Marker" }
}
if ($CatalogLoader -notmatch '(?s)if\s+configured_effect\s*==\s*"none"\s+then\s+item\.nv_effect\s*=\s*nil\s+else\s+item\.nv_effect\s*=\s*configured_effect\s+end') {
    throw 'Headlamp nv_effect marker must normalize to nil through an explicit branch'
}
if ($CatalogLoader -match 'configured_effect\s*==\s*"none"\s+and\s+nil\s+or\s+configured_effect') {
    throw 'Headlamp nv_effect normalization must not use the falsey Lua and/or idiom'
}
if ($CatalogLoader -notmatch 'effective_slot\s*~=\s*9') {
    throw 'Actor device catalog validation must accept raw Anomaly device slot 9'
}
if ($Compat -notmatch 'slot\s*~=\s*9') {
    throw 'Actor device compatibility preflight must accept raw Anomaly device slot 9'
}
if ($Bootstrap -notmatch 'return\s+engine_inventory_slot\(configured\.value\)') {
    throw 'Actor device runtime must retain the LTX-to-Lua slot translation'
}
if ($Bootstrap -notmatch 'role\s*==\s*"device"\s+and\s+slot\.value\s*~=\s*10') {
    throw 'Actor device runtime must retain Lua inventory slot 10'
}
if (-not $GeneratorTests.Contains('device_torch_dummy={class="TORCH_S",slot="9"}')) {
    throw 'Actor device catalog fixture must model raw Anomaly device slot 9'
}
if (-not $GeneratorTests.Contains('device_torch_nv_2={class="TORCH_S",slot="10",nv_effect="nightvision_2"}')) {
    throw 'Actor device catalog mismatch fixture must reject raw slot 10'
}
if (-not $RuntimeTests.Contains('sections[device.section] = { class = "TORCH_S", slot = 9, nv_effect = device.nv_effect }')) {
    throw 'Actor device runtime preflight fixture must model raw Anomaly device slot 9'
}
if (-not $RuntimeTests.Contains('{ label = "device", ltx_slot = 9, lua_slot = 10 }')) {
    throw 'Actor device runtime regression must prove raw slot 9 translates to Lua slot 10'
}
foreach ($Marker in @('function select','function generate','actor_device','GA_DEVICE_ARGUMENT_INVALID','GA_DEVICE_SELECTION_INVALID','next_int(1, 100)')) {
    if (-not $DeviceGenerator.Contains($Marker)) { throw "Actor device generator contract is missing: $Marker" }
}
foreach ($CaseName in @('device_catalog_and_probability_boundaries','device_generator_rejects_malformed_arguments','device_catalog_rejects_effective_mismatch')) {
    if (-not $GeneratorTests.Contains($CaseName)) { throw "Actor device regression case is missing: $CaseName" }
}
foreach ($Assertion in @(
    'snapshot.devices.headlamp.nv_effect, nil, "headlamp effect marker normalizes to nil"',
    'snapshot.devices.nv_gen1.nv_effect, "nightvision_1", "Gen 1 effect remains exact"',
    'snapshot.devices.nv_gen2.nv_effect, "nightvision_2", "Gen 2 effect remains exact"',
    'snapshot.devices.nv_gen3.nv_effect, "nightvision_3", "Gen 3 effect remains exact"'
)) {
    if (-not $GeneratorTests.Contains($Assertion)) { throw "Actor device effect normalization regression is missing: $Assertion" }
}

foreach ($Marker in @('gamma_arena_device_generator.generate','schema_version = 8','FightSpecV8','device:')) {
    if (-not $Generator.Contains($Marker)) { throw "FightSpec v8 actor device generator contract is missing: $Marker" }
}
foreach ($Marker in @('GA_LOADOUT_DEVICE_INVALID','gamma_arena_device_generator.generate','spec.schema_version ~= 8','copy_device')) {
    if (-not $Validator.Contains($Marker)) { throw "FightSpec v8 actor device validator contract is missing: $Marker" }
}
foreach ($CaseName in @('actor_device_is_difficulty_independent_and_stable','validator_rejects_forged_actor_devices','validator_copies_actor_device')) {
    if (-not $GeneratorTests.Contains($CaseName)) { throw "FightSpec v8 actor device regression case is missing: $CaseName" }
}

foreach ($Marker in @('GA_ACTOR_DEVICE_CHARGE_FAILED','"outfit", "knife", "device", "weapon"','CHARGE_DEVICE','set_item_condition','item_condition','shutdown_device','device_neutralized','device_condition')) {
    if (-not $Bootstrap.Contains($Marker)) { throw "Actor device runtime contract is missing: $Marker" }
}
foreach ($Marker in @('item_device.is_nv_active','item_device.set_nightvision','item_device.is_torch_active','item_device.toggle_torch','game_object.set_condition','game_object.enable_torch')) {
    if (-not $Compat.Contains($Marker) -and -not $Bootstrap.Contains($Marker)) { throw "Actor device compatibility contract is missing: $Marker" }
}
foreach ($CaseName in @('actor_device_is_equipped_and_fully_charged','actor_device_charge_failure_rolls_back','actor_device_cleanup_neutralizes_active_effects','actor_device_cleanup_retains_unconfirmed_effect','actor_device_cleanup_neutralizes_absent_and_offline_state','actor_device_cleanup_reprobes_deferred_release')) {
    if (-not $RuntimeTests.Contains($CaseName)) { throw "Actor device runtime regression case is missing: $CaseName" }
}
if ($Bootstrap -notmatch '(?s)elseif\s+resolved\.value\s*==\s*nil\s+then\s+local\s+neutralized\s*=\s*neutralize_device\(record\)') {
    throw 'Absent actor devices must clear global Beef device state before record retirement'
}
if ($Bootstrap -match 'record\.device_neutralized\s*==\s*true\s+then\s+return') {
    throw 'Pending actor device release must re-probe global state on every cleanup pass'
}
if ($Bootstrap -notmatch '(?s)shutdown_device\s*=\s*function\(item,\s*id,\s*section\).*?if\s+item\s*~=\s*nil\s+then\s+item:enable_torch\(false\)\s+end') {
    throw 'Actor device shutdown must support global-only cleanup when the item is absent or offline'
}
if ($Bootstrap -notmatch 'if\s+item_device\.is_torch_active\(\)\s+then\s+return\s+gamma_arena_result\.ok\(false\)\s+end') {
    throw 'Actor device shutdown must confirm that global torch state is fully inactive'
}

Write-Host 'PASS: actor lighting device static contract passed'
