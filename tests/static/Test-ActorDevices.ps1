[CmdletBinding()]
param([string]$RepoRoot)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$CatalogPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx'
$RulesPath = Join-Path $RepoRoot 'src\gamedata\configs\gamma_arena\gamma_arena_custom_rules.ltx'
$CatalogLoaderPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_catalog.script'
$DeviceGeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_device_generator.script'
$ItemCatalogPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_catalog.script'
$GeneratorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_generator.script'
$ValidatorPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_validator.script'
$EntityAdapterPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
$MaterializerPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_item_materializer.script'
$BootstrapPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_bootstrap.script'
$CompatPath = Join-Path $RepoRoot 'src\gamedata\scripts\gamma_arena_compat.script'
$GeneratorTestsPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_generator.script'
$RuntimeTestsPath = Join-Path $RepoRoot 'dev\gamedata\scripts\gamma_arena_test_runtime.script'

foreach ($Path in @($CatalogPath, $RulesPath, $CatalogLoaderPath, $DeviceGeneratorPath, $ItemCatalogPath, $GeneratorPath, $ValidatorPath, $EntityAdapterPath, $MaterializerPath, $BootstrapPath, $CompatPath, $GeneratorTestsPath, $RuntimeTestsPath)) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Actor device integration file is missing: $Path" }
}

$Catalog = Get-Content -Raw -LiteralPath $CatalogPath
$Rules = Get-Content -Raw -LiteralPath $RulesPath
$CatalogLoader = Get-Content -Raw -LiteralPath $CatalogLoaderPath
$DeviceGenerator = Get-Content -Raw -LiteralPath $DeviceGeneratorPath
$ItemCatalog = Get-Content -Raw -LiteralPath $ItemCatalogPath
$Generator = Get-Content -Raw -LiteralPath $GeneratorPath
$Validator = Get-Content -Raw -LiteralPath $ValidatorPath
$EntityAdapter = Get-Content -Raw -LiteralPath $EntityAdapterPath
$Materializer = Get-Content -Raw -LiteralPath $MaterializerPath
$Bootstrap = Get-Content -Raw -LiteralPath $BootstrapPath
$Compat = Get-Content -Raw -LiteralPath $CompatPath
$GeneratorTests = Get-Content -Raw -LiteralPath $GeneratorTestsPath
$RuntimeTests = Get-Content -Raw -LiteralPath $RuntimeTestsPath
$ControlledFailures = New-Object System.Collections.Generic.List[string]

function Test-ExactDevicePrices([string]$Text) {
    # Price validation is intentionally independent from semantic tuple validation.
    foreach ($Expected in @(
        '(?m)^device_torch_dummy\s*=\s*25\s*$', '(?m)^device_torch_nv_1\s*=\s*75\s*$',
        '(?m)^device_torch_nv_2\s*=\s*150\s*$', '(?m)^device_torch_nv_3\s*=\s*300\s*$'
    )) { if ($Text -notmatch $Expected) { return $false } }
    return $true
}
if (-not (Test-ExactDevicePrices $Rules)) { throw 'Exact device price baseline is invalid' }
$WrongPriceRules = $Rules -replace '(?m)^device_torch_nv_3\s*=\s*300\s*$', 'device_torch_nv_3 = 301'
$MissingPriceRules = $Rules -replace '(?m)^device_torch_nv_3\s*=\s*300\s*$', ''
if ((Test-ExactDevicePrices $WrongPriceRules) -or (Test-ExactDevicePrices $MissingPriceRules)) {
    throw 'Exact device price mutation gate accepted wrong or missing Gen3 price'
}
Write-Host 'PASS: exact device price mutation gate rejected 301 and missing override'

function Test-ExactDeviceCatalog([string]$Text) {
    $Expected = @(
        '(?ms)^\[meta\].*?^schema_version\s*=\s*10\s*$.*?^revision\s*=\s*11\s*$.*?^generator_version\s*=\s*11\s*$',
        '(?ms)^\[devices\]\s*^ids\s*=\s*headlamp,nv_gen1,nv_gen2,nv_gen3\s*$',
        '(?ms)^\[device_headlamp\].*?^section\s*=\s*device_torch_dummy\s*$.*?^kind\s*=\s*headlamp\s*$.*?^selection_weight\s*=\s*50\s*$.*?^nv_effect\s*=\s*none\s*$',
        '(?ms)^\[device_nv_gen1\].*?^section\s*=\s*device_torch_nv_1\s*$.*?^kind\s*=\s*gen1\s*$.*?^selection_weight\s*=\s*25\s*$.*?^nv_effect\s*=\s*nightvision_1\s*$'
    )
    foreach ($Pattern in $Expected) { if ($Text -notmatch $Pattern) { return $false } }
    return $Text -notmatch '(?m)^weight\s*='
}
if (-not (Test-ExactDeviceCatalog $Catalog)) { throw 'Exact selector catalog baseline is invalid' }
$CatalogMutations = @(
    ($Catalog -replace 'headlamp,nv_gen1,nv_gen2,nv_gen3', 'headlamp,headlamp,nv_gen2,nv_gen3'),
    ($Catalog -replace 'section = device_torch_nv_1', 'section = device_torch_nv_3'),
    ($Catalog -replace 'selection_weight = 50', 'selection_weight = 49'),
    ($Catalog -replace 'nv_effect = nightvision_1', 'nv_effect = nightvision_2'),
    ($Catalog -replace 'selection_weight = 50', ('selection_weight = 50' + [Environment]::NewLine + 'weight = 50'))
)
foreach ($Mutation in $CatalogMutations) { if (Test-ExactDeviceCatalog $Mutation) { throw 'Selector catalog mutation was accepted' } }
Write-Host 'PASS: exact selector catalog mutation gate rejected forged tuples and legacy weight'

function Add-ControlledFailure([string]$Message) {
    $ControlledFailures.Add($Message)
    Write-Host "CONTROLLED RED: $Message"
}

if ($Catalog -notmatch '(?ms)^\[meta\].*?^schema_version\s*=\s*10\s*$.*?^revision\s*=\s*11\s*$.*?^generator_version\s*=\s*11\s*$') {
    throw 'Actor device catalog must use schema/revision/generator 10/11/11'
}
if ($Catalog -notmatch '(?ms)^\[devices\]\s*^ids\s*=\s*headlamp,nv_gen1,nv_gen2,nv_gen3\s*$') {
    throw 'Actor device catalog exact id allowlist is missing'
}
foreach ($Expected in @(
    '(?ms)^\[device_headlamp\].*?^section\s*=\s*device_torch_dummy\s*$.*?^kind\s*=\s*headlamp\s*$.*?^selection_weight\s*=\s*50\s*$.*?^nv_effect\s*=\s*none\s*$',
    '(?ms)^\[device_nv_gen1\].*?^section\s*=\s*device_torch_nv_1\s*$.*?^kind\s*=\s*gen1\s*$.*?^selection_weight\s*=\s*25\s*$.*?^nv_effect\s*=\s*nightvision_1\s*$',
    '(?ms)^\[device_nv_gen2\].*?^section\s*=\s*device_torch_nv_2\s*$.*?^kind\s*=\s*gen2\s*$.*?^selection_weight\s*=\s*18\s*$.*?^nv_effect\s*=\s*nightvision_2\s*$',
    '(?ms)^\[device_nv_gen3\].*?^section\s*=\s*device_torch_nv_3\s*$.*?^kind\s*=\s*gen3\s*$.*?^selection_weight\s*=\s*7\s*$.*?^nv_effect\s*=\s*nightvision_3\s*$'
)) {
    if ($Catalog -notmatch $Expected) { throw 'Actor device exact catalog record is missing or malformed' }
}
foreach ($Expected in @(
    '(?m)^device_torch_dummy\s*=\s*25\s*$',
    '(?m)^device_torch_nv_1\s*=\s*75\s*$',
    '(?m)^device_torch_nv_2\s*=\s*150\s*$',
    '(?m)^device_torch_nv_3\s*=\s*300\s*$'
)) {
    if ($Rules -notmatch $Expected) { throw 'Actor device exact price override is missing or malformed' }
}
if ($CatalogLoader -notmatch 'selection_weight' -or $CatalogLoader -match 'item\.weight\s*=\s*integer') {
    throw 'Actor device semantics must normalize selection_weight and erase legacy weight'
}
if ($ItemCatalog -notmatch 'category\s*=\s*"device"' -or $ItemCatalog -notmatch 'ga-catalog-v10') {
    throw 'Physical devices must enter the v10 universal catalog fingerprint as category device'
}
if (-not $ItemCatalog.Contains('GA_ITEM_CATALOG_DEVICE_PRICE_INVALID') -or $ItemCatalog -notmatch 'override\s*~=\s*expected\.price') {
    throw 'Physical device prices must reject missing and mismatched exact overrides'
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
if ((-not $DeviceGenerator.Contains('DEVICE_MANIFEST')) -or
    ($DeviceGenerator -notmatch 'catalogs\.schema_version\s*~=\s*10') -or
    ($DeviceGenerator -notmatch 'catalogs\.revision\s*~=\s*11') -or
    ($DeviceGenerator -notmatch 'catalogs\.generator_version\s*~=\s*11') -or
    ($DeviceGenerator -notmatch 'item\.weight\s*~=\s*nil')) {
    throw 'Selector must require catalog 10/11/11 and exact device tuples without legacy weight'
}
if (-not $GeneratorTests.Contains('device_selector_rejects_forged_exact_catalogs')) { throw 'Forged selector regression case is missing' }
if (-not $DeviceGenerator.Contains('random_actor_device_v11')) { throw 'Mode-free device seed epoch is missing' }
if (-not $DeviceGenerator.Contains('identity.generator_version')) { throw 'Device generator identity version is missing' }
if ($DeviceGenerator -match 'identity\.mode_id' -or $DeviceGenerator -notmatch 'generator_version\s*~=\s*11') {
    throw 'Actor device generator must require version 11 without mode_id'
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

$UniversalLifecycleCase = 'runtime_universal_actor_items_shutdown_precedes_cleanup_and_rollback'
if (-not $RuntimeTests.Contains($UniversalLifecycleCase)) {
    throw "Universal actor-device lifecycle runtime regression is missing: $UniversalLifecycleCase"
}
$UniversalItemPortStart = $Bootstrap.IndexOf('function new_actor_item_port')
$UniversalItemPortEnd = if ($UniversalItemPortStart -ge 0) { $Bootstrap.IndexOf('function new_actor_loadout_port', $UniversalItemPortStart) } else { -1 }
if ($UniversalItemPortStart -lt 0 -or $UniversalItemPortEnd -le $UniversalItemPortStart) {
    throw 'Universal actor-item port must remain structurally testable'
}
$UniversalItemPort = $Bootstrap.Substring($UniversalItemPortStart, $UniversalItemPortEnd - $UniversalItemPortStart)
if ($UniversalItemPort -notmatch '(?s)shutdown_device.*?ports\.release_item') {
    Add-ControlledFailure 'Universal actor-item cleanup/rollback must shut down global actor-device state before owned release'
}
if (([regex]::Matches($Bootstrap, 'shutdown_device\s*=\s*shutdown_actor_device')).Count -lt 2) {
    Add-ControlledFailure 'Legacy and universal actor-item ports must share the production actor-device shutdown seam'
}
Write-Host 'PASS: independent universal lifecycle preservation checks executed'

$ExactUniversalCleanupCase = 'runtime_universal_actor_device_cleanup_uses_exact_shared_shutdown'
if (-not $RuntimeTests.Contains($ExactUniversalCleanupCase) -or $UniversalItemPort -notmatch 'local\s+function\s+shutdown_device\(record,\s*entity,\s*require_active_transaction\)') {
    throw 'Universal actor-device cleanup must call the shared shutdown seam with exact owned device context'
}
foreach ($CaseName in @(
    'runtime_universal_actor_device_cleanup_accepts_online_actor_parent_proof',
    'runtime_universal_actor_device_cleanup_runtime_parent_never_replaces_token',
    'runtime_universal_actor_device_cleanup_rejects_foreign_runtime_parent'
)) {
    if (-not $RuntimeTests.Contains($CaseName)) {
        throw "Universal actor-device runtime ownership regression is missing: $CaseName"
    }
}
if ($UniversalItemPort -notmatch 'ports\.item_parent_id' -or
    $UniversalItemPort -notmatch 'server_parent_matches' -or
    $UniversalItemPort -notmatch 'runtime_parent_matches') {
    throw 'Universal actor-item cleanup must support exact online actor-parent proof'
}

$UniversalDeviceReadyCase = 'runtime_universal_actor_device_is_exact_equipped_charged_and_ready'
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_faults_rollback_all_actor_state')) {
    throw 'Universal actor-device condition faults must rollback all Arena-owned actor state'
}
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_rollback_neutralizes_once_before_any_release') -or
    $Materializer -notmatch 'prepare_rollback' -or $UniversalItemPort -notmatch 'prepare_rollback') {
    throw 'Universal rollback must confirm one exact transaction-level device shutdown before any release'
}
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_provisional_tag_failures_wait_for_exact_shutdown') -or
    $UniversalItemPort -notmatch 'transaction\.provisional_by_entity\[entry\.entity\]') {
    throw 'Provisional device rollback must recover the exact active transaction record'
}
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_timeout_is_bounded_and_rolls_back') -or
    $Materializer -notmatch 'GA_ACTOR_DEVICE_EQUIP_TIMEOUT' -or $Materializer -notmatch 'timeout_ms') {
    throw 'Universal actor-device online/equip timeout must be bounded, diagnosed, and rolled back'
}
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_timeout_boundary_and_wrap') -or
    $Materializer -notmatch 'elapsed_ms\([^\r\n]+\)\s*>=\s*pending\.timeout_ms') {
    throw 'Universal actor-device timeout must fire at the exact deadline across uint32 wrap'
}
if (-not $RuntimeTests.Contains('runtime_universal_actor_device_cleanup_covers_absent_offline_pending_reprobe')) {
    throw 'Universal actor-device cleanup must cover absent, offline, pending, reprobed, idempotent, and no-device paths'
}
if (-not $RuntimeTests.Contains('runtime_composed_non_device_items_reach_ready_cross_frame') -or
    $RuntimeTests -notmatch 'items:update\(\)') {
    throw 'Production universal items must prove non-device readiness through the cross-frame update protocol'
}
if (-not $RuntimeTests.Contains($UniversalDeviceReadyCase)) {
    throw ('Universal actor-device READY runtime regression is missing: ' + $UniversalDeviceReadyCase)
}
if (-not $RuntimeTests.Contains('runtime_composed_all_exact_actor_devices_reach_ready_cross_frame')) {
    throw 'Production cross-frame runtime must materialize and verify all four exact actor devices'
}
if (-not $RuntimeTests.Contains('item_ports.move_to_slot = nil') -or
    -not $RuntimeTests.Contains('item_ports.item_in_slot = nil') -or
    -not $RuntimeTests.Contains('move_slots[1], 10')) {
    throw 'All-four production device regression must exercise raw LTX slot 9 translation at the engine adapter boundary'
}
if ($Materializer -notmatch 'CATEGORIES\.device\s*=\s*true') {
    throw 'Universal actor-device materializer must own the device category'
}
Write-Host 'PASS: universal actor-device READY contract is owned by the materializer'

$OpponentDeviceCase = 'runtime_entity_rejects_opponent_device_before_actor_mutation'
if (-not $RuntimeTests.Contains($OpponentDeviceCase) -or -not $EntityAdapter.Contains('GA_ENTITY_OPPONENT_DEVICE_FORBIDDEN')) {
    throw 'Universal runtime must reject opponent devices before actor mutation'
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
if ($Bootstrap -notmatch '(?s)local\s+function\s+shutdown_actor_device\(item,\s*id,\s*section\).*?if\s+item\s*~=\s*nil\s+then\s+item:enable_torch\(false\)\s+end') {
    throw 'Actor device shutdown must support global-only cleanup when the item is absent or offline'
}
if ($Bootstrap -notmatch 'if\s+item_device\.is_torch_active\(\)\s+then\s+return\s+gamma_arena_result\.ok\(false\)\s+end') {
    throw 'Actor device shutdown must confirm that global torch state is fully inactive'
}

Write-Host 'PASS: independent legacy shutdown preservation checks executed'

if ($ControlledFailures.Count -gt 0) {
    Write-Host ("CONTROLLED RED SUMMARY: " + ($ControlledFailures -join ' | '))
}

Write-Host 'PASS: actor lighting device static contract passed'
