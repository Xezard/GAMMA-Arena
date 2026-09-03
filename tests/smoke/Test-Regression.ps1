[CmdletBinding()]
param(
    [switch]$PositiveFixtureOnly,
    [switch]$StaticFixturesOnly,
    [switch]$ToolFixturesOnly
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Failures = New-Object System.Collections.Generic.List[string]
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gamma-arena-regression-" + [Guid]::NewGuid().ToString('N'))

if (-not $ToolFixturesOnly) {
    & (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1') -Verify
    if (-not $?) { exit 1 }
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        $script:Failures.Add($Message)
    }
}

function Write-FixtureFile([string]$Root, [string]$RelativePath, [string]$Content = '') {
    $Path = Join-Path $Root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Write-FixtureFileEncoded([string]$Root, [string]$RelativePath, [string]$Content, [Text.Encoding]$Encoding) {
    $Path = Join-Path $Root $RelativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function New-StaticFixture([string]$Name) {
    $Root = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $Root 'src\gamedata') -Force | Out-Null
    foreach ($File in @('VERSION', '.gitattributes', '.gitignore', 'README.md', 'CHANGELOG.md')) {
        Write-FixtureFile $Root $File 'fixture'
    }
    return $Root
}

function New-Task7Fixture([string]$Name) {
    $Root = New-StaticFixture $Name
    foreach ($File in @('VERSION', '.gitattributes', '.gitignore', 'README.md', 'CHANGELOG.md')) {
        Copy-Item -LiteralPath (Join-Path $RepoRoot $File) -Destination (Join-Path $Root $File) -Force
    }
    foreach ($Directory in @('src\gamedata', 'dev\gamedata', 'schemas', 'docs', 'tests\fixtures')) {
        $Source = Join-Path $RepoRoot $Directory
        $Destination = Join-Path $Root $Directory
        if (Test-Path -LiteralPath $Source) {
            $null = New-Item -ItemType Directory -Path $Destination -Force
            Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
        }
    }
    Write-FixtureFile $Root 'tools\Test-GammaArena.ps1' ([IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\Test-GammaArena.ps1')))
    return $Root
}

function Add-Task2ContractFixture([string]$Root) {
    Write-FixtureFile $Root 'README.md' @'
dev_test_autorun = false
dev_test_autorun = true
'@
    Write-FixtureFile $Root '.gitattributes' @'
* text=auto eol=lf
*.xml text eol=lf
src/gamedata/configs/text/rus/st_gamma_arena.xml -text
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_assert.script' @'
function equals() end
function is_true() end
function is_false() end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_runner.script' @'
local function autorun_enabled()
    return axr_main.config:r_value("gamma_arena", "dev_test_autorun", 1, false)
end
function run_case() end
function run_all()
    return pcall(function()
        return gamma_arena_test_domain.run(run_case)
    end)
end
function on_game_start()
    if not autorun_enabled() then return end
    return run_all()
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_domain.script' @'
function run(run_case_fn)
    gamma_arena_test_tactical_director.run(run_case_fn)
    gamma_arena_test_tactical_adapter.run(run_case_fn)
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_result.script' @'
function ok() end
function err() end
function is_ok() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_log.script' @'
local function canonical_key(key)
    local key_type = type(key)
    if key_type == "string" then return "string:" .. key end
    if key_type == "number" then return "number:" .. key end
    if key_type == "boolean" then return "boolean:" .. key end
end
local entries = {}
local seen_keys = {}
for key, value in pairs({}) do
    local canonical = canonical_key(key)
    local existing_index = canonical and seen_keys[canonical]
    if existing_index then
        entries[existing_index].value = "<canonical-key-collision>"
    elseif canonical then
        seen_keys[canonical] = #entries + 1
        entries[#entries + 1] = { key = canonical, value = value }
    end
end
table.sort(entries, function(left, right)
    return left.key < right.key
end)
pcall(printf, "fixture")
function info() end
function warn() end
function error() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_rng.script' @'
function normalize_uint32(seed)
    local value = tonumber(seed) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        return 1
    end
    return 1
end
function derive_seed() end
function new()
    local function next_int(minimum, maximum)
        if minimum ~= minimum or maximum ~= maximum or minimum == math.huge or maximum == math.huge then
            return nil
        end
        local span = maximum - minimum + 1
        return span
    end
    return { next_int = next_int }
end
function random_session_seed() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_state_machine.script' @'
states = { PREPARING = "PREPARING" }
events = { PREFLIGHT_SUCCEEDED = "PREFLIGHT_SUCCEEDED" }
local state_values = states
local event_values = events
local transitions = { [event_values.PREFLIGHT_SUCCEEDED] = state_values.PREPARING }
function transition() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_number.script' @'
function is_finite() end
function is_integer() end
function is_positive_integer() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_catalog.script' @'
local v1_difficulty_manifest = {}
local v1_layout_manifest = {}
local function load_impl() end
function load()
    local ok, result = pcall(load_impl)
    local markers = "GA_DIFFICULTY_BUDGET_INFEASIBLE GA_CATALOG_SECTION_CHECK_FAILED GA_CATALOG_UNKNOWN_SECTION GA_CATALOG_MANIFEST_INVALID section_for_each line_count r_line"
    gamma_arena_number.is_integer(1)
    return markers
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_catalog_discovery.script' 'function discover() end'
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_mode_skirmish.script' @'
function id() end
function difficulty_envelope() end
function next_fight_index() end
function validate_session() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_generator.script' @'
function generate()
    local fight_index = 0
    local normalized_seed = gamma_arena_rng.normalize_uint32(1)
    local normalized_request = { session_seed = normalized_seed }
    gamma_arena_number.is_integer(fight_index)
    stream(normalized_request)
    local actor_knife = "actor_knife"
    return { schema_version = 2, session_seed = normalized_seed, fight_index = fight_index, knife = actor_knife }
end
function stable_encode()
    local value = { knife = "wpn_knife" }
    return "session_seed=" .. "fight_index=" .. value.knife
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_validator.script' @'
function validate()
    local expected_fight_id = "ga-1-0-g1-c1-l1"
    local difficulty = { enemy_total_budget = 1 }
    local opponent_count = 1
    local slot_base = math.floor(difficulty.enemy_total_budget / opponent_count)
    gamma_arena_number.is_integer(1)
    local effective_profile = { class = "AI_STL_S", community = "bandit" }
    return "GA_MODE_INVALID GA_LEVEL_INVALID GA_LAYOUT_VERSION_INVALID GA_OPPONENT_SLOT_INVALID GA_FIGHT_ID_INVALID GA_FIGHTSPEC_TYPE_INVALID GA_LOADOUT_COMBINATION_INVALID GA_LOADOUT_KNIFE_INVALID GA_ENEMY_SLOT_BUDGET_INVALID GA_ENEMY_EFFECTIVE_CLASS_INVALID GA_ENEMY_EFFECTIVE_COMMUNITY_INVALID"
end
function validate_runtime() return "effective_profile GA_ENEMY_EFFECTIVE_PROFILE_API_MISSING" end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_generator.script' 'function run() end'
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_catalog_discovery.script' 'function run() end'
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx' @'
[meta]
schema_version = 2
revision = 2
generator_version = 2
gamma_arena_bandit_novice
gamma_arena_bandit_trainee
gamma_arena_bandit_experienced
gamma_arena_bandit_veteran
[knife]
section = wpn_knife
[knife_2]
section = wpn_knife2
[knife_3]
section = wpn_knife3
[knife_4]
section = wpn_knife4
[knife_5]
section = wpn_knife5
[knife_6]
section = wpn_knife6
[knife_7]
section = wpn_knife7
[knife_8]
section = wpn_knife8
[knife_9]
section = wpn_knife9
[outfit_novice]
section = novice_outfit
cost = 1
'@
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx' @'
[ga_difficulty_rookie]
[ga_difficulty_stalker]
[ga_difficulty_veteran]
[ga_difficulty_master]
'@
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx' @'
[ga_layout_rostok_arena_v1]
level = l05_bar
actor_spawn_path = t_way
actor_look_path = t_look
opponent_spawn_paths = bar_arena_walk_3_1,bar_arena_walk_3_2,bar_arena_walk_6_1,bar_arena_walk_6_3,bar_arena_walk_6_6,bar_arena_walk_1_1
'@
    $ArenaFactions = @('army','bandit','csky','dolg','ecolog','freedom','killer','monolith','stalker')
    $ArenaProfileBases = @{ army='military'; bandit='bandit'; csky='csky'; dolg='duty'; ecolog='ecolog'; freedom='freedom'; killer='killer'; monolith='monolith'; stalker='stalker' }
    $ArenaRanks = @('novice','trainee','experienced','veteran')
    $NpcAliases = @()
    $SkipAliases = @('![skip_npcs]')
    foreach ($Faction in $ArenaFactions) {
        for ($RankIndex = 0; $RankIndex -lt $ArenaRanks.Count; $RankIndex++) {
            $Alias = "gamma_arena_${Faction}_$($ArenaRanks[$RankIndex])"
            $NpcAliases += "[$Alias]:sim_default_$($ArenaProfileBases[$Faction])_$RankIndex"
            $SkipAliases += "$Alias = $Faction"
        }
    }
    Write-FixtureFile $Root 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx' ($NpcAliases -join "`n")
    Write-FixtureFile $Root 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx' ($SkipAliases -join "`n")
    Write-FixtureFile $Root 'tests\fixtures\effective-arena-npcs-v1.ini' @'
[one]
section = gamma_arena_bandit_novice
class = AI_STL_S
community = bandit
[two]
section = gamma_arena_bandit_trainee
class = AI_STL_S
community = bandit
[three]
section = gamma_arena_bandit_experienced
class = AI_STL_S
community = bandit
[four]
section = gamma_arena_bandit_veteran
class = AI_STL_S
community = bandit
'@
    Write-FixtureFile $Root 'tests\fixtures\golden-fights-v9.txt' @'
seed=0,difficulty=rookie,fight=0,stable_encode=schema_version=9|session_seed=1|fight_index=0|diagnostic=FightSpecV9 rookie
seed=1,difficulty=stalker,fight=0,stable_encode=schema_version=9|session_seed=1|fight_index=0|diagnostic=FightSpecV9 stalker
seed=3735928559,difficulty=veteran,fight=7,stable_encode=schema_version=9|session_seed=1588444913|fight_index=7|diagnostic=FightSpecV9 veteran
seed=4294967295,difficulty=master,fight=31,stable_encode=schema_version=9|session_seed=3|fight_index=31|diagnostic=FightSpecV9 master
'@
    Write-FixtureFile $Root 'schemas\fight-spec-v9.md' 'fixture'
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_config_tx.script' @'
local function _snapshot_unchecked()
    local value = nil
    if value == nil then value = "" end
    return "line_exist r_string_ex"
end
function snapshot(config, section, keys)
    if is_quarantined(config) then return "GA_CONFIG_QUARANTINED" end
    return _snapshot_unchecked(config, section, keys)
end
local function synchronize_cache() end
function run()
    local markers = "commit_write_keys commit_remove_keys fail_closed_keys recover GA_CONFIG_QUARANTINED GA_CONFIG_RECOVERY_FAILED boolean_returns"
    local raw = config.ini
    local cache = config.cache
    local remove = config.remove_line
    synchronize_cache()
    return markers
end
function recover() synchronize_cache() end
function is_quarantined() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_migrations.script' @'
function migrate()
    gamma_arena_session_store.reconcile_character_creation(config)
    gamma_arena_session_store.reconcile_character_creation(config)
    gamma_arena_config_tx.run()
    return { ok = true, value = { events = {} } }
end
function read_settings()
    local gamma_arena_boolean_returns = true
    gamma_arena_config_tx.is_quarantined()
    return "GA_SETTINGS_SCHEMA_NEWER settings_schema_version events"
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_session_store.script' @'
local LAUNCH_TOKEN_TTL = 600
local volatile_launch_permits = {}
local gamma_arena_boolean_returns = true
local markers = "ga1: launch_pending launch_token launch_mode_id launch_difficulty_id launch_seed_mode launch_session_seed launch_stage launch_deferred_level launch_target_level resume_pending resume_session_id resume_session_nonce resume_next_fight_index resume_checkpoint_name resume_schema_version new_game_difficulty new_game_economy new_game_economy_treasure new_game_character_name new_game_faction new_game_map new_game_money new_game_loadout new_game_story_mode new_game_icon new_game_hardcore_mode new_game_hardcore_mode_lives new_game_hardcore_mode_regenerate new_game_survival_mode new_game_azazel_mode new_game_warfare new_game_campfire_mode new_game_conditions_mode new_game_timer_mode new_game_opened_routes new_game_test GA_RESUME_ALREADY_PENDING GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_LAUNCH_STALE_CLEARED GA_RESUME_CHECKPOINT_MISMATCH GA_RESUME_FIGHT_INDEX_MISMATCH GA_SESSION_GENERATOR_VERSION_INVALID GA_SESSION_UNKNOWN_FIELD bridge_pending bridge_schema_version present launch_handoff GA_LAUNCH_HANDOFF_REQUIRED GA_LAUNCH_HANDOFF_INVALID"
local function remove(config, section, key) config:remove_line(section, key) end
local function validate_expected_session() end
local function validate_persisted_launch_request() end
local function normalize_present_empty(value) if value == nil then value = "" end return value end
gamma_arena_config_tx.run()
function new_store() end
function parse_manual_seed() end
function validate_start_request() end
function random_session_seed() end
function save_preferences() end
function issue_launch() end
function parse_launch_token() end
function validate_launch_handoff() end
function reconcile_character_creation() end
local function validate_character_creation_lease() end
function Store:mark_launch_deferred() end
function Store:validate_launch_activation() end
function consume_launch() return restore_character_creation() end
function Store:consume_launch() return self:restore_character_creation() end
function Store:inspect_intents() end
function Store:prepare_resume() return normalize_prepare_session_result(validate_expected_session()), "GA_CHECKPOINT_RECOVERY_MISMATCH" end
function Store:consume_resume(config, expected, prepared) return prepared end
function Store:clear_resume_if_matches() end
function inspect_intents() end
function issue_resume() end
function prepare_resume() end
function consume_resume(intent, session)
    if intent.value.next_fight_index < session.value.fight_index then return "GA_RESUME_FIGHT_INDEX_MISMATCH" end
end
function write_character_creation() end
function Store:restore_character_creation() end
function Store:clear_transient() return self:restore_character_creation() end
function restore_character_creation() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_bootstrap.script' @'
local callback_names = { "on_game_load", "actor_on_first_update", "actor_on_update", "actor_on_before_death", "npc_on_net_spawn", "npc_on_death_callback", "save_state", "load_state", "on_before_save_input", "on_before_load_input", "actor_on_net_destroy", "on_before_level_changing" }
local current_level = true
local rollback = "GA_BOOTSTRAP_REGISTRATION_POISONED"
local function invoke_callback(result, callback)
    pcall(callback)
    if result.ok == false then return callback() end
end
local function guarded(active)
    if not active then return end
end
local function teardown_adapter_method(adapter, method_name) return adapter[method_name](adapter) end
local function teardown_fixture(entity_adapter, actor_adapter)
    teardown_adapter_method(entity_adapter, "cleanup")
    teardown_adapter_method(entity_adapter, "update")
    teardown_adapter_method(actor_adapter, "cleanup")
end
local function expected_created_quantity(descriptor, index, entity_count, box_size) return box_size end
local function entity_ammo_quantity(entity, is_ammo)
    if not is_ammo then return 1 end
    return nil
end
function engine_inventory_slot(ltx_slot) return { ok = true, value = ltx_slot + 1 } end
local MAX_TEARDOWN_UPDATES = 256
local task6 = "gamma_arena_actor_adapter.new gamma_arena_entity_adapter.new gamma_arena_tactical_adapter.new gamma_arena_ui_result.new() actor.set_invulnerable level.disable_input level.enable_input level.object_by_id safe_release_manager.release step_entity_cleanup step_actor_cleanup last_update_at pending = true entity_teardown_max_updates actor_teardown_max_updates MAX_TEARDOWN_UPDATES teardown_clock teardown_timeout_ms teardown_max_updates GA_ENTITY_TEARDOWN_TIMEOUT GA_ENTITY_TEARDOWN_EXHAUSTED GA_ACTOR_TEARDOWN_TIMEOUT GA_ACTOR_TEARDOWN_EXHAUSTED se_load_var force_set_goodwill apply_actor_hostility game_object.enemy game_object.friend new_actor_loadout_port new_runtime_entity_exists_port entity_exists GA_ACTOR_LOADOUT_OWNERSHIP_PROOF_INVALID ownership_token save_owner_tag load_owner_tag resolve_entity GA_ACTOR_LOADOUT_OWNERSHIP_MISMATCH Current actor item parent proof is malformed Current actor item section proof is malformed hold_entity_offline request_entity_online set_switch_online set_switch_offline switch_online apply_actor_activation_hold set_enemy make_item_active active_item effective_ammo_box_size system.r_u32 ammo_box_size box_size bonus_ammo bonus_ammo_rounds bonus_ammo_box_size WAIT_ACTOR_LOADOUT WAIT_SLOT_VERIFY WAIT_MAGAZINE_VERIFY WAIT_ACTIVE_VERIFY move_to_slot item_in_slot set_ammo_elapsed get_ammo_in_magazine ammo_mag_size update_loadout GA_ACTOR_LOADOUT_EQUIP_TIMEOUT"
local body_health = "zzz_player_injuries BHS_PARTS bhs.health bhs.maxhp bhs.timedhp bhs.save_state bhs.load_state utils.save_var utils.load_var mod_body_health_reset lam2.abort ClearWounds ClearAllBoosters WoundForEach BoosterForEach ChangeAlcohol remove_all_psy_ppe_effects RemoveTimeEvent set_stage_two 655808 655820 99123 99133 8053 reset_transient_state"
local function clear_engine_actor_transients_fixture(wound_count, booster_count)
    if wound_count ~= 0 then return "GA_ACTOR_TRANSIENT_VERIFY_FAILED" end
    if booster_count ~= 0 then return "GA_ACTOR_BOOSTER_READBACK_STALE" end
end
local TacticalProxy = {}
function TacticalProxy:begin() return self:ensure_adapter() end
function TacticalProxy:stop()
    local adapter = self.active
    local stopped = adapter:stop()
    if stopped.ok then self.active = nil end
    return stopped
end
function apply_actor_hostility(npc, actor)
    npc:set_relation(game_object.enemy, actor)
    npc:force_set_goodwill(-5000, actor)
end
local function apply_actor_activation_hold(npc, actor) npc:set_enemy(nil) end
local function save_and_verify_tag(record) return record end
local function actor_cleanup_fixture(current)
    local created, entry = {}, {}
    created[#created + 1] = entry
    save_and_verify_tag(entry)
    if type(current.parent_id) ~= "number" then return "GA_ACTOR_LOADOUT_OWNERSHIP_PROOF_INVALID" end
    if current.owner ~= "arena" then return "GA_ACTOR_LOADOUT_OWNERSHIP_MISMATCH" end
end
local function death_flag(id, value) return se_save_var(id, nil, "death_dropped", value) end
local function create_item_fixture(section, parent, count, is_ammo)
    if is_ammo then return alife_create_item(section, parent, { ammo = count }) end
    return alife_create_item(section, parent)
end
local function bound(max_updates) return max_updates > MAX_TEARDOWN_UPDATES end
local function compose_fixture(overrides)
    local store = overrides.store or gamma_arena_session_store.new_store()
    local deps = { reconcile = overrides.reconcile or function(config) return gamma_arena_migrations.migrate(config) end }
    return deps
end
function make_callbacks() end
local Registrar = {}
function Registrar:runtime_status() return "GA_BOOTSTRAP_NOT_READY GA_BOOTSTRAP_COMPOSE_FAILED" end
function new_registrar() return setmetatable({ last_result = nil, register_all = function() local result = { ok = false, error = { code = "GA_BOOTSTRAP_REGISTRATION_FAILED", message = "fixture" } }; if type(result.error) ~= "table" or type(result.error.code) ~= "string" or type(result.error.message) ~= "string" then return nil end; UnregisterScriptCallback("x", guarded); return result end }, { __index = Registrar }) end
function runtime_status() return "GA_BOOTSTRAP_NOT_READY" end
function on_game_start() return new_registrar():register_all() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_compat.script' @'
local function engine_callable_present(value) return value ~= nil end
local markers = "RegisterScriptCallback UnregisterScriptCallback ini_file system_ini system_ini.r_u32 alife alife().get_children alife().object alife().set_switch_online alife().set_switch_offline alife_create alife_create_item alife_release_id se_save_var se_load_var level.patrol_path_exists level.object_by_id patrol db.actor db.zone_by_name game_object.friend game_object.enemy axr_main.config safe_release_manager.release l05_bar AI_STL_S bandit point level_vertex_id game_vertex_id 4294967295 GA_PREFLIGHT_PATROL_MISSING GA_PREFLIGHT_PATROL_INVALID GA_PREFLIGHT_SECTION_MISSING GA_NPC_CLASS_API_MISSING GA_NPC_CLASS_MISSING GA_NPC_CLASS_READ_FAILED GA_NPC_CLASS_INVALID GA_NPC_COMMUNITY_API_MISSING GA_NPC_COMMUNITY_MISSING GA_NPC_COMMUNITY_READ_FAILED GA_NPC_COMMUNITY_INVALID GA_AMMO_BOX_SIZE_INVALID"
local task6_markers = "time_global level.disable_input level.enable_input db.actor.iterate_inventory db.actor.power db.actor.radiation db.actor.bleeding db.actor.psy_health db.actor.set_actor_position db.actor.position db.actor.set_invulnerable/invulnerable db.actor.move_to_slot db.actor.item_in_slot db.actor.make_item_active db.actor.active_item db.actor.activate_slot db.actor.active_slot GA_PREFLIGHT_DIRECTOR_API_MISSING GA_PREFLIGHT_DIRECTOR_CONFIG_INVALID GA_PREFLIGHT_DIRECTOR_SECTION_MISSING GA_PREFLIGHT_DIRECTOR_LOOK_PATH_MISSING xr_logic.configure_schemes xr_logic.activate_by_section xr_logic.switch_to_section"
function preflight() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_orchestrator.script' @'
local markers = "inspect_intents consume_launch gamma_arena_session st_gamma_arena_manual_save_disabled GA_INTENT_CONFLICT GA_RESUME_UNSUPPORTED GA_LAUNCH_REQUIRES_NEW_GAME disconnect pending_load_state awaiting_activation on_callback_result_error GA_DISCONNECT_FAILED main_menu_executed normalize_for_arena verify_inventory_empty runtime_stage GA_RUNTIME_CLEANUP_PENDING cleanup_ready_for_disconnect entities on_npc_death living_opponent_count GA_ENTITY_COUNT_UNAVAILABLE GA_ENTITY_COUNT_STATE_INVALID death_latched pending_result ret_value hold_after_logical_death release_logical_death_hold show_defeat defeat_next_action NEXT_AFTER_DEFEAT drive_continuation GA_FIGHT_INDEX_EXHAUSTED GA_LAUNCH_DEFERRED GA_LAUNCH_HANDOFF_ACCEPTED GA_RUNTIME_STAGE_CHANGED GA_ACTOR_POSITIONED GA_ACTOR_LOADOUT_APPLIED GA_OPPONENTS_ACTIVATED mark_launch_deferred validate_launch_activation"
local deferred_level_logged = nil
local function teardown_retry(result, pending) if result.ok and not pending then self.teardown_done = true end end
local function new_cycle() self.teardown_cycle = self.teardown_cycle + 1 end
function new() self.cleanup_required = true; return markers end
function update_runtime()
    if not self:is_active() and self.cleanup_required then
        local began = call_method("GA_ACTOR_UPDATE_FAILED", self.deps.actor, "begin_update")
        if not began.ok then return began end
        return self:drive_runtime()
    end
end
function drive_runtime() if self.cleanup_required then return self:cleanup_ready_for_disconnect() end end
local function countdown() return call_method("GA_COUNTDOWN_UI_FAILED", self.deps.result_ui, "show_countdown", { value = 3, on_main_menu = function() end }) end
local function call_method(code)
    return fail('GA_DEPENDENCY_METHOD_UNAVAILABLE', 'dependency missing', { requested_code = code })
end
function Orchestrator:enter_fatal()
    self.activation_attempted = true
    self.awaiting_activation = false
end
function Orchestrator:on_callback_error() end
function Orchestrator:reconcile_active_victory() return self:living_opponent_count() end
function Orchestrator:activate_once()
    local reconciled = safe_result_call("GA_SETTINGS_RECONCILIATION_FAILED", self.deps.reconcile, self.deps.config)
    local intents = self.deps.store:inspect_intents(self.deps.config)
    self.deps.store:mark_launch_deferred(self.deps.config, "fake_start", "l05_bar")
    self.deps.store:validate_launch_activation(self.deps.config, { serialized = true, current_level = "l05_bar", expected_level = "l05_bar" })
    if state.resume_pending then return fail("GA_RESUME_UNSUPPORTED") end
    if not state.launch_pending then
        self.activation_attempted = true
        self.awaiting_activation = false
    end
    if current.value ~= expected then
        deferred_level_logged = current.value
        return { route = "deferred" }
    end
    self.activation_attempted = true
    return reconciled, intents
end
function Orchestrator:layout_snapshot() end
local function callback_route(was_active) if was_active == true or self:is_active() then return self:enter_fatal() end end
function Orchestrator:defeat_next_action()
    self.pending_continuation_kind = "defeat_retry"
end
function Orchestrator:drive_continuation()
    local continuation_kind = self.pending_continuation_kind
    if continuation_kind == "defeat_retry" then
        self.deps.entities:begin_apply(self.fight_spec, self.session.session_id)
    end
end
function Orchestrator:drive_runtime()
    if self.runtime_stage == "WAIT_INVENTORY" then self:set_runtime_stage("PREPARING") end
end
function Orchestrator:observe_entity_activation()
    self.deps.actor:release_logical_death_hold()
    self.deps.actor:release_input()
    self.death_latched = false
    self.result_action_locked = false
end
function Orchestrator:show_victory()
    return self.deps.result_ui:show_result({ kind = "victory" })
end
function Orchestrator:show_defeat()
    self.deps.actor:release_input()
    return self.deps.result_ui:show_result({ kind = "defeat" })
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_actor_adapter.script' @'
local markers = "normalize_for_arena verify_inventory_empty apply_loadout update_loadout reset_for_rematch hold_after_logical_death cleanup_loadout_for_restore release_logical_death_hold begin_update iterate_inventory release_item_id set_health_ex set_actor_condition power radiation bleeding psy_health give_money disable_effects_timer set_actor_position set_actor_direction input_owned GA_ACTOR_INACTIVE reset_transient_state inventory_drain last_progress_at submitted_ids remaining_ids poll_count last_count = 0 inventory_drain_timeout_ms elapsed_since_progress_ms total_elapsed_ms item_section snapshot_inventory parent_id_matches_actor owned_actor_id requested_actor_id interrupt_item_use acquire_input loadout.cleanup"
local parent_method = "parent"
local effects = { "bleeding", 1 }
local function set_actor_condition(actor, field_name, value) actor[field_name] = value end
function ActorAdapter:normalize_for_arena() end
function ActorAdapter:reset_for_rematch() end
function ActorAdapter:begin_rematch_boundary() return interrupt_item_use(), self:acquire_input() end
function ActorAdapter:reset_transient_state() return loadout.cleanup() end
function ActorAdapter:begin_update()
    local reconciled = update_transient_services()
    if not reconciled.ok then return reconciled end
    self.update_tick = self.update_tick + 1
end
function ActorAdapter:discard_transient_services(reason) return reason end
function ActorAdapter:observe_transient_state(phase) return phase end
function new() return markers, effects end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_entity_adapter.script' @'
local markers = "begin_apply update on_npc_death living_opponent_count cleanup registry_snapshot gamma_arena_owner se_load_var get_children parent_id safe_release_manager set_relation game_object.enemy game_object.friend -5000 AI_STL_S bandit persist_death_dropped GA_ENTITY_DEATH_DROPPED_VERIFY_FAILED hold_offline request_online online_requested held_offline staged_friendly set_actor_hold GA_ENTITY_ACTIVATION_HOLD_FAILED GA_ENTITY_ONLINE_REQUEST_FAILED GA_ENTITY_ONLINE_TIMEOUT GA_ENTITY_RELEASE_TIMEOUT GA_ENTITY_PARENT_RELEASE_BLOCKED GA_ENTITY_CHILD_PARENT_UNPROVEN register_and_tag_created_item profile_runtime ammo_box_size ammo_rounds GA_ENTITY_AMMO_BOX_SIZE_INVALID expected_created_quantity stable_encode deps.tactical tactical_disabled GA_DIRECTOR_RUNTIME_DISABLED record_death stop_tactical STOPPING GA_EARLY_SELF_DEATH_DIAGNOSTIC spawn_position observed_position displacement queries server_available online_available finite_displacement early_self_death_diagnostic_builder self.integrity_fault == nil Diagnostic builder must return a plain table runtime_entity_early_self_death_is_integrity runtime_entity_early_self_death_diagnostic_failures_do_not_suppress_integrity"
local iterator_shape = type(children) == "function"
local participant_copy = { community = participant.community }
function EntityAdapter:stage_ready() self.tactical_started = true; self:set_state("READY") end
function EntityAdapter:activate_ready() self.deps.set_actor_hostile(); self:set_state("ACTIVE") end
function EntityAdapter:update_ready_fixture()
    if self.state_value == "WAIT_ACTOR_LOADOUT" then self:set_state("SPAWNING") end
    if self.state_value == "READY" then return self:opponent_gate_open() end
end
function EntityAdapter:verify_npc_has_no_current_children(record)
    if entity.value == nil then return "GA_ENTITY_CHILD_PARENT_UNPROVEN" end
    if parent_id == nil then return "GA_ENTITY_CHILD_PARENT_UNPROVEN" end
end
function EntityAdapter:register_and_tag_created_item(entity)
    local registered = self:register_record("item", entity:id(), {})
    local tagged = self:tag_record(registered.value)
end
function EntityAdapter:create_descriptor(descriptor)
    for index, entity in ipairs(entities) do
        local authorized = self:register_and_tag_created_item(entity, descriptor, index)
    end
end
function EntityAdapter:on_npc_death(id)
    local owner = self:load_owner_tag(id)
    if not owner.ok then return owner end
end
function EntityAdapter:reconcile_active_deaths() return self.deps.online_object end
function EntityAdapter:activate()
    local routes = validated_spec.tactical_routes()
    local tactical = self.deps.tactical:begin({})
    self.deps.set_actor_hostile()
    self:set_state("ACTIVE")
    return tactical
end
function EntityAdapter:stop_tactical() return self.deps.tactical:stop() end
function new() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_tactical_director.script' @'
local Director = {}
function Director:begin() end
function Director:observe() end
function Director:update() end
function Director:accept_hint() end
function Director:stop() end
function Director:snapshot() end
local function is_modular_newer() end
local function deadline_reached() end
local local_evidence, evidence_sequence = {}, 0
function new() return gamma_arena_rng.derive_seed({ "fixture" }), local_evidence, evidence_sequence end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_tactical_adapter.script' @'
local Adapter = {}
local markers = "best_danger best_enemy get_enemy memory_position grenade see xr_logic.configure_schemes xr_logic.activate_by_section xr_logic.switch_to_section hint_requested actor.position pcall"
local combat_owned = sees_actor.value == true
function Adapter:begin() end
function Adapter:update() end
function Adapter:record_death() end
function Adapter:stop() end
function Adapter:snapshot() end
function new() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx' @'
[meta]
schema_version = 1
[director]
observation_interval_ms = 500
look_path = bar_arena_walk_attack
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_tactical_director.script' 'function run() end'
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_tactical_adapter.script' 'function run() end'
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_checkpoint_adapter.script' @'
local CHECKPOINT_NAME = "_gamma_arena_checkpoint"
local markers = "WAITING_STABLE HIDING READY UNHIDING LOADING REHIDING CLEANING ERROR .scop .scoc .dds .gamma_arena_hidden GA_CHECKPOINT_TIMEOUT GA_CHECKPOINT_UNSAFE_PATH issue_resume consume_resume clear_resume_if_matches pending_or_timeout elapsed_ms engine_fs_port canonicalize_engine_path engine_device_namespace update_path file_rename file_delete GA_CHECKPOINT_LOAD_TIMEOUT last_mutation_cause mutation_attempt begin_resume_recovery GA_CHECKPOINT_RECOVERY_MISSING GA_CHECKPOINT_RECOVERY_INCONSISTENT GA_CHECKPOINT_RECOVERY_MISMATCH GA_CHECKPOINT_RECOVERY_TIMEOUT prepared_resume late_dds_started GA_CHECKPOINT_DDS_TIMEOUT pending_late_dds_or_timeout"
local mode = "rb"
local save_command = "save " .. CHECKPOINT_NAME
local load_command = "load " .. CHECKPOINT_NAME
local function checkpoint_exists(fs, relative_name)
    return pcall(fs.exist, fs, "$game_saves$", relative_name)
end
local function keep_required_target_pending(target_info, required)
    if target_info.value.exists then
        if required and target_info.value.size <= 0 then return false end
    end
end
function new() return markers end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_runtime.script' @'
local markers = "runtime_preflight_aggregates_in_stable_order runtime_preflight_requires_community_for_every_custom_profile runtime_preflight_requires_human_class_for_every_custom_profile runtime_preflight_rejects_missing_profile_value_apis runtime_preflight_normalizes_effective_arena_enemy_community runtime_wrong_level_skips_patrol_resolution runtime_launch_consumes_before_preflight_once runtime_activation_requires_game_load_boundary runtime_launch_defers_on_fake_start_then_activates_on_rostok runtime_ordinary_no_intent_activation_latches_once runtime_first_activation_failure_routes_fatal runtime_activation_reconciles_before_intent_inspection_once runtime_activation_version_changes_clear_resume_before_checkpoint_routing runtime_activation_reconciliation_failures_are_fatal_before_inspection runtime_invalid_or_expired_launch_never_reaches_preflight runtime_ordinary_no_intent_activation_latches_once runtime_orchestrator_npc_net_spawn_is_active_only runtime_entity_net_spawn_isolates_only_owned_npcs runtime_entity_net_spawn_fails_closed_on_owner_and_community_faults runtime_entity_activation_rejects_runtime_community_drift runtime_ordinary_loaded_save_rejects_stray_launch runtime_ordinary_loaded_save_rejects_stray_resume runtime_new_game_does_not_reuse_prior_load_state_latch runtime_game_load_boundary_drops_prior_runtime_generation runtime_config_quarantine_propagates_to_fatal runtime_save_payload_is_plain_deep_copy runtime_manual_save_and_load_flags_are_blocked runtime_callback_boundary_routes_exceptions_once runtime_callback_boundary_routes_false_results_once runtime_inactive_callback_results_remain_benign runtime_active_save_failure_enters_fatal_once runtime_fatal_main_menu_retries_throw_then_becomes_idempotent runtime_fatal_main_menu_retries_explicit_false runtime_fatal_main_menu_bypasses_terminal_cleanup_error runtime_ordinary_main_menu_still_rejects_terminal_cleanup_error runtime_fatal_ui_helper_propagates_callback_results runtime_bootstrap_registration_rolls_back_every_position runtime_bootstrap_registration_poison_blocks_retry runtime_bootstrap_requires_unregister_before_composition runtime_bootstrap_status_preserves_initialization_result runtime_unexpected_net_destroy_clears_external_route runtime_actor_inventory_release_is_deferred_and_verified runtime_actor_inventory_drain_waits_for_looted_items runtime_actor_inventory_drain_releases_newly_surfaced_item_once runtime_actor_inventory_drain_times_out_with_sorted_evidence runtime_actor_inventory_drain_timeout_is_wrap_safe runtime_actor_inventory_drain_rejects_unowned_public_actor runtime_actor_inventory_drain_rejects_direct_nil_and_invalid_snapshot_values runtime_actor_inventory_drain_submits_sorted_deduplicated_ids runtime_actor_inventory_drain_cleanup_clears_transaction runtime_wait_inventory_blocks_fight_generation_and_loadout runtime_actor_normalization_uses_gamma_bleeding_sentinel runtime_actor_input_ownership_is_idempotent runtime_actor_rejects_coincident_patrol_points runtime_checkpoint_requires_stable_required_files runtime_checkpoint_allows_absent_or_late_dds runtime_checkpoint_wrap_clock_times_out runtime_checkpoint_verifies_rename_and_delete_postconditions runtime_checkpoint_recovers_mixed_crash_states runtime_checkpoint_persists_intent_before_load runtime_checkpoint_consumes_intent_only_after_rehide runtime_checkpoint_rejects_mismatched_resume runtime_checkpoint_cleanup_is_idempotent_in_every_state runtime_checkpoint_two_sessions_leave_no_stale_paths runtime_dedicated_start_reaches_preparing_without_checkpoint runtime_engine_checkpoint_port_uses_xray_alias_for_existence runtime_entity_wounded_cleanup_holds_offline_before_release runtime_entity_living_defeat_cleanup_holds_offline runtime_entity_cleanup_quiesce_failure_is_terminal_without_release"
local task3_start_marker = "runtime_ordinary_start_preflight_precedes_mutation"
local runtime_community_deferral_marker = "runtime_npc_net_spawn_errors_defer_fatal_ui_to_update"
local task4_rematch_marker = "runtime_defeat_menu_fresh_failures_are_bounded runtime_defeat_menu_preflight_failure_identity_is_preserved runtime_defeat_menu_default_fatal_path_skips_start_settings"
local task6_preflight_marker = "runtime_preflight_requires_task6_actor_checkpoint_ports runtime_actor_rematch_resets_gamma_body_health runtime_actor_rematch_boundary_aborts_before_input_lock runtime_actor_rematch_boundary_failure_never_acquires_input runtime_actor_rematch_transients_clear_once_before_loadout_cleanup runtime_actor_transient_failure_prevents_loadout_cleanup runtime_bootstrap_engine_transients_clear_and_verify runtime_bootstrap_engine_booster_readback_is_nonfatal runtime_bootstrap_gamma_transient_integrations_are_exact"
local review_markers = "runtime_actor_rejects_nil_inventory_parent runtime_actor_rejects_throwing_inventory_accessors runtime_checkpoint_load_wait_is_bounded_and_wrap_safe runtime_checkpoint_transient_mutation_failures_retry_to_success runtime_checkpoint_zero_required_target_waits_for_timeout runtime_checkpoint_permanent_mutation_throws_time_out runtime_checkpoint_fresh_process_recovers_all_exact_layouts runtime_checkpoint_fresh_recovery_rejects_missing_inconsistent_and_mismatch runtime_checkpoint_fresh_recovery_rejects_persisted_intent_drift runtime_fatal_recovery_waits_for_cleanup_before_disconnect runtime_pre_session_fatal_waits_for_cleanup_before_disconnect runtime_prepare_resume_legacy_mismatch_is_normalized runtime_checkpoint_late_dds_retries_throw_then_succeeds runtime_checkpoint_late_dds_permanent_failures_are_bounded_and_wrap_safe runtime_bootstrap_teardown_drains_transient_exact_cleanup_idempotently runtime_bootstrap_teardown_resets_across_sessions runtime_completed_teardown_allows_next_loaded_launch_activation runtime_bootstrap_teardown_permanent_failures_are_bounded runtime_bootstrap_teardown_rejects_unbounded_update_limits runtime_bootstrap_teardown_override_budgets_route_exactly runtime_failed_teardown_retries_then_latches_success runtime_entity_ammo_box_size_failure_precedes_actor_mutation runtime_entity_death_dropped_is_persisted_and_round_tripped"
local task7_markers = "runtime_preflight_requires_task7_entity_ports_and_ammo_metadata runtime_entity_actor_loadout_precedes_spawn runtime_entity_npcs_are_offline_until_atomic_activation runtime_entity_online_wait_is_bounded_and_wrap_safe runtime_entity_active_defers_input_release_to_task8 runtime_bootstrap_actor_loadout_port_is_bound_and_exact runtime_actor_loadout_creates_physical_grenades_and_rolls_back runtime_actor_loadout_derives_unreadable_server_ammo_quantity runtime_actor_loadout_creates_exact_bonus_ammo_box runtime_actor_loadout_bonus_ammo_rollback_is_owned runtime_actor_loadout_translates_ltx_slots_to_lua_slots runtime_actor_loadout_waits_across_frames_for_engine_equipment runtime_actor_loadout_rollback_blocks_disconnect_until_absent runtime_bootstrap_actor_existence_lookup_fails_closed runtime_actor_loadout_malformed_existence_blocks_teardown_disconnect runtime_bootstrap_hostility_port_is_feature_probed runtime_entity_bonus_ammo_box_size_failure_precedes_actor_mutation runtime_entity_partial_failures_rollback_in_reverse runtime_entity_creates_physical_grenade_and_rolls_back_failure runtime_entity_purges_only_snapshot_children_still_parented runtime_entity_supports_real_get_children_iterator runtime_entity_multi_return_ammo_is_exact runtime_entity_derives_unreadable_server_ammo_quantity runtime_entity_multi_return_late_failure_is_fully_registered runtime_entity_multi_return_invalid_or_duplicate_id_rolls_back_every_owned_creation runtime_entity_registry_is_plain_ids_only runtime_entity_cleanup_requires_registry_and_tag runtime_entity_forged_tag_is_ignored runtime_entity_tag_loss_fails_safe runtime_entity_cleanup_adopts_unloaded_weapon_child runtime_entity_cleanup_adopts_late_child_before_parent runtime_entity_runtime_child_tag_failure_is_terminal runtime_entity_runtime_child_limit_is_terminal runtime_entity_parent_release_blocks_unreadable_child_parent runtime_entity_cleanup_is_idempotent runtime_entity_lifecycle_cleanup_takes_over_mid_rollback runtime_entity_existence_result_must_be_boolean runtime_entity_duplicate_death_is_idempotent runtime_entity_unregistered_death_is_ignored runtime_entity_object_death_signature_is_normalized runtime_entity_numeric_death_requires_test_injection runtime_registered_death_owner_tag_failures_route_through_real_callback_router runtime_registered_death_mismatching_owner_tag_is_benign runtime_entity_release_is_async_and_never_direct runtime_entity_release_timeout_is_wrap_safe runtime_entity_max_cardinality_cleanup_fits_default_budget runtime_entity_relations_friend_first_then_actor_hostile runtime_entity_activation_does_not_wait_for_precombat_active_item runtime_entity_callbacks_fail_closed runtime_validator_rejects_effective_nonhuman_profile runtime_entity_runtime_profile_check_precedes_actor_mutation runtime_orchestrator_living_count_fails_closed runtime_entity_actor_loadout_readiness_starts_spawning_without_gate"
local task9_markers = "runtime_preflight_requires_task9_death_hold_port runtime_result_modal_releases_global_input runtime_task9_ordinary_death_is_inert runtime_task9_active_death_latches_and_defers_defeat runtime_task9_death_outside_active_is_not_a_defeat runtime_task9_single_result_contract_maps_both_kinds runtime_task9_countdown_escape_model_routes_main_menu_cleanup runtime_task9_resume_failures_normalize_to_restore_failed runtime_task9_resume_pending_invalid_loaded_session_normalizes runtime_task9_restoring_state_read_failure_normalizes runtime_task9_resume_completion_transition_failure_normalizes runtime_task9_defeat_retry_reuses_same_spec_without_checkpoint runtime_task9_defeat_and_victory_share_main_menu_cleanup runtime_task9_restore_failure_enters_error_with_safe_menu_only runtime_fight_index_max_minus_one_advances_once runtime_fight_index_exhaustion_precedes_mutation_and_routes_fatal runtime_actor_loadout_consumed_absent_id_retires_without_release runtime_actor_loadout_pre_release_reused_foreign_id_is_never_released runtime_actor_loadout_post_submit_reuse_is_never_released_twice runtime_actor_loadout_malformed_ownership_proof_fails_closed runtime_actor_loadout_exact_owned_match_releases_once runtime_actor_loadout_apply_failures_never_drop_valid_created_ids runtime_actor_loadout_failed_tag_write_never_manufactures_ownership"
local task11_markers = "runtime_preflight_requires_tactical_director_apis runtime_preflight_requires_tactical_director_config runtime_entity_tactical_begin_precedes_hostility runtime_entity_tactical_bind_failure_rolls_back runtime_entity_tactical_active_failure_is_fail_soft_once runtime_entity_tactical_death_and_stop_are_ordered runtime_entity_tactical_stop_failure_is_retried_before_release"
function run() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\modxml_gamma_arena.script' @'
local function on_read(xml_file_name, xml_obj)
    local normalized = string.lower(string.gsub(xml_file_name, "/", "\\"))
    if normalized ~= "ui\\ui_mm_main.xml" and normalized ~= "ui\\ui_mm_main_16.xml" then return end
    local existing = xml_obj:query("menu_main btn[name=btn_gamma_arena]")
    if existing and #existing > 0 then return end
    local menu = xml_obj:query("menu_main")
    local new_game = xml_obj:query("menu_main > btn[name=btn_newgame]")
    local new_game_position = xml_obj:getElementPosition(new_game[1])
    local GA_DXML_POSITION_API_UNAVAILABLE = true
    local GA_DXML_MENU_MISSING = true
    local GA_DXML_NEW_GAME_MISSING = true
    local GA_DXML_NEW_GAME_PARENT_MISMATCH = true
    local GA_DXML_NEW_GAME_POSITION_INVALID = true
    xml_obj:insertFromXMLString([[<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu" />]], menu[1], new_game_position + 1)
end
function on_xml_read()
    local result = { error = { code = "GA_DXML", message = "fixture", context = {} } }
    pcall(gamma_arena_log.error, result.error.code, result.error.message, result.error.context)
    return register(RegisterScriptCallback)
end
function register(registrar)
    local GA_DXML_REGISTRAR_UNAVAILABLE = true
    local GA_DXML_REGISTER_FAILED = true
    registrar("on_xml_read", on_read)
    registrar("main_menu_on_init", gamma_arena_main_menu.on_main_menu_init)
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_main_menu.script' @'
local function bind(menu)
    if type(menu.AddCallback) == "function" then
        menu:AddCallback("btn_gamma_arena", ui_events.BUTTON_CLICKED, function() end, menu)
    end
end
function on_main_menu_init(menu)
    bind(menu)
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_ui_start.script' @'
class "UIStart" (CUIScriptWnd)
function UIStart:InitControls()
    local xml = CScriptXmlInit()
    xml:InitStatic("x", self)
    xml:InitTextWnd("x", self)
    xml:InitEditBox("x", self)
    xml:Init3tButton("x", self)
    xml:InitComboBox("x", self)
    self:Register(self, "x")
    self:AddCallback("x", ui_events.BUTTON_CLICKED, self.StartGame, self)
end
function UIStart:StartGame() self.owner:StartGame() end
function UIStart:RetryStale()
    local first = gamma_arena_session_store.issue_launch()
    if first.error.code == "GA_LAUNCH_STALE_CLEARED" then gamma_arena_session_store.issue_launch() end
end
function handoff_start_game(owner, config)
    local detail = owner:StartGame()
    if detail == false then return gamma_arena_session_store.clear_transient(config) end
end
function UIStart:OnStart() return handoff_start_game(self.owner, axr_main.config) end
function UIStart:ShowFatal() self.fatal_main_menu = true end
function invoke_fatal_main_menu(callback) return callback() end
function UIStart:OnFatalMainMenu() return invoke_fatal_main_menu(self.callback) end
function create() end
function show_fatal() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_ui_result.script' @'
class "UIResult" (CUIScriptWnd)
local markers = "show_countdown clear_countdown show_result clear_result ClearOwnedWidgets __finalize st_gamma_arena_result_defeat st_gamma_arena_result_victory DIK_RETURN DIK_SPACE DIK_ESCAPE OnNext OnMainMenu"
function new() return markers end
function UIResult:OnNext() end
function UIResult:OnMainMenu() end
function UIResult:ShowCountdown(model) local callback = model.on_main_menu; self.on_main_menu = callback end
function UIResult:OnKeyboard(dik)
    if dik == DIK_keys.DIK_RETURN or dik == DIK_keys.DIK_SPACE then self:OnNext(); return true end
    if dik == DIK_keys.DIK_ESCAPE then self:OnMainMenu(); return true end
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_migrations.script' @'
local function stale_launch_is_recovered_by_new_store() end
local function launch_survives_vm_reload_with_matching_bridge_lease() end
local function launch_handoff_rejects_mismatched_or_expired_lease() end
local function serialized_launch_requires_fake_start_phase_proof() end
local function same_store_corrupt_launch_is_replaced() end
local function resume_rejects_tampered_expected_session() end
local function mutation_failure_matrix_is_crash_safe() end
local function recovery_failure_quarantines_transaction() end
local function read_and_false_return_faults_are_safe() end
local function stale_cleanup_and_conflict_faults_are_safe() end
local function matching_resume_cleanup_is_session_scoped() end
local function prepared_resume_consume_rejects_persisted_drift() end
local function dxml_accepts_canonical_callback_path() end
local function dxml_registers_first_main_menu_click() end
local function dxml_registration_failures_are_structured() end
local function dxml_places_arena_after_new_game() end
local function dxml_placement_failures_are_structured() end
local function character_creation_bridge_restores_exactly_from_fresh_store() end
local function character_creation_bridge_accepts_engine_nil_for_present_empty_values() end
local function ordinary_character_creation_without_lease_is_untouched() end
local function character_creation_bridge_restores_on_every_launch_terminal_route() end
local function character_creation_bridge_faults_fail_closed() end
local function start_game_failures_restore_bridge_immediately() end
local function arm_fault() end
local function arm_read_fault() end
local function arm_recovery_fault() end
local persisted = {}
function run() end
'@
    $DomainPath = Join-Path $Root 'dev\gamedata\scripts\gamma_arena_test_domain.script'
    $DomainContent = Get-Content -LiteralPath $DomainPath -Raw
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_domain.script' ($DomainContent + "`nfunction task4_fixture() return gamma_arena_test_migrations.run(run_case_fn) end`n")
    Write-FixtureFile $Root 'src\gamedata\configs\ui\gamma_arena_start.xml' @'
<w><gamma_arena_start><auto_static x="0" y="0" width="1024" height="768" stretch="1"><texture>ui\ui_actor_main_menu_one</texture></auto_static><title/><difficulty/><seed/><random_seed/><validation/><start/><back/><fatal><fatal_text/><fatal_main_menu/></fatal></gamma_arena_start></w>
'@
    Write-FixtureFile $Root 'src\gamedata\configs\ui\gamma_arena_result.xml' '<w><gamma_arena_result><countdown/><result_panel><title/><next/><main_menu/></result_panel></gamma_arena_result></w>'
    $Locale = @'
<?xml version="1.0" encoding="utf-8"?>
<string_table>
<string id="st_gamma_arena_main_menu"><text>ARENA</text></string>
<string id="st_gamma_arena_title"><text>Gamma Arena</text></string>
<string id="st_gamma_arena_difficulty_rookie"><text>&#x041D;&#x043E;&#x0432;&#x0438;&#x0447;&#x043E;&#x043A;</text></string>
<string id="st_gamma_arena_difficulty_stalker"><text>&#x0421;&#x0442;&#x0430;&#x043B;&#x043A;&#x0435;&#x0440;</text></string>
<string id="st_gamma_arena_difficulty_veteran"><text>&#x0412;&#x0435;&#x0442;&#x0435;&#x0440;&#x0430;&#x043D;</text></string>
<string id="st_gamma_arena_difficulty_master"><text>&#x041C;&#x0430;&#x0441;&#x0442;&#x0435;&#x0440;</text></string>
<string id="st_gamma_arena_random_seed"><text>&#x0421;&#x043B;&#x0443;&#x0447;&#x0430;&#x0439;&#x043D;&#x044B;&#x0439; seed</text></string>
<string id="st_gamma_arena_start"><text>&#x041D;&#x0410;&#x0427;&#x0410;&#x0422;&#x042C;</text></string>
<string id="st_gamma_arena_back"><text>&#x041D;&#x0410;&#x0417;&#x0410;&#x0414;</text></string>
<string id="st_gamma_arena_fatal_title"><text>Fatal</text></string>
<string id="st_gamma_arena_fatal_error_line"><text>Gamma Arena error [%s].</text></string>
<string id="st_gamma_arena_fatal_main_menu"><text>&#x0412; &#x0433;&#x043B;&#x0430;&#x0432;&#x043D;&#x043E;&#x0435; &#x043C;&#x0435;&#x043D;&#x044E;</text></string>
<string id="st_gamma_arena_seed_invalid"><text>Invalid</text></string>
<string id="st_gamma_arena_manual_save_disabled"><text>Disabled</text></string>
<string id="st_gamma_arena_result_victory"><text>&#x041F;&#x043E;&#x0431;&#x0435;&#x0434;&#x0430;</text></string>
<string id="st_gamma_arena_result_defeat"><text>&#x0412;&#x044B; &#x043F;&#x043E;&#x0433;&#x0438;&#x0431;&#x043B;&#x0438;</text></string>
<string id="st_gamma_arena_result_main_menu"><text>&#x0412; &#x0433;&#x043B;&#x0430;&#x0432;&#x043D;&#x043E;&#x0435; &#x043C;&#x0435;&#x043D;&#x044E;</text></string>
<string id="st_gamma_arena_result_next"><text>&#x0421;&#x043B;&#x0435;&#x0434;&#x0443;&#x044E;&#x0449;&#x0438;&#x0439; &#x0431;&#x043E;&#x0439;</text></string>
</string_table>
'@
    $RussianLocale = [Net.WebUtility]::HtmlDecode(($Locale -replace '^<\?xml[^>]+>\r?\n', ''))
    Write-FixtureFileEncoded $Root 'src\gamedata\configs\text\rus\st_gamma_arena.xml' $RussianLocale ([Text.Encoding]::GetEncoding(1251))
    Write-FixtureFile $Root 'src\gamedata\configs\text\eng\st_gamma_arena.xml' $Locale
    Write-FixtureFile $Root 'tests\fixtures\settings-v0.ltx' "[gamma_arena]`nlast_difficulty_id = veteran`nlast_seed_mode = manual"
    Write-FixtureFile $Root 'tests\fixtures\settings-v1.ltx' "[gamma_arena]`nsettings_schema_version = 1`nlast_difficulty_id = master`nlast_seed_mode = random"
    Write-FixtureFile $Root 'schemas\session-v1.md' 'session_nonce checkpoint_name resume_session_nonce FightSpec FightRegistry ResumeIntent non-durable ga1:<issued_at_epoch>:<nonce> 600'

    # Keep the positive baseline aligned with the current versioned combat-loop
    # contracts. Negative fixtures below overwrite only the file under test.
    $CurrentContractFiles = @(
        'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_difficulties.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_layouts.ltx',
        'src\gamedata\configs\gamma_arena\gamma_arena_tactical.ltx',
        'src\gamedata\scripts\gamma_arena_catalog.script',
        'src\gamedata\scripts\gamma_arena_catalog_discovery.script',
        'src\gamedata\scripts\gamma_arena_generator.script',
        'src\gamedata\scripts\gamma_arena_random_generator.script',
        'src\gamedata\scripts\gamma_arena_fight_builder.script',
        'src\gamedata\scripts\gamma_arena_fight_spec.script',
        'src\gamedata\scripts\gamma_arena_fight_validator_v9.script',
        'src\gamedata\scripts\gamma_arena_validator.script',
        'src\gamedata\scripts\gamma_arena_layout_adapter.script',
        'src\gamedata\scripts\gamma_arena_booster_reconciler.script',
        'src\gamedata\scripts\gamma_arena_actor_diagnostics.script',
        'src\gamedata\scripts\gamma_arena_bootstrap.script',
        'src\gamedata\scripts\gamma_arena_compat.script',
        'src\gamedata\scripts\gamma_arena_orchestrator.script',
        'src\gamedata\scripts\gamma_arena_entity_adapter.script',
        'dev\gamedata\scripts\gamma_arena_test_domain.script',
        'dev\gamedata\scripts\gamma_arena_test_generator.script',
        'dev\gamedata\scripts\gamma_arena_test_catalog_discovery.script',
        'dev\gamedata\scripts\gamma_arena_test_layout_adapter.script',
        'dev\gamedata\scripts\gamma_arena_test_runtime.script',
        'tests\fixtures\golden-fights-v9.txt',
        'schemas\fight-spec-v9.md'
    )
    foreach ($RelativePath in $CurrentContractFiles) {
        $SourcePath = Join-Path $RepoRoot $RelativePath
        $DestinationPath = Join-Path $Root $RelativePath
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationPath) -Force
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    }
}

function Invoke-PowerShellFile([string]$Path, [string[]]$Arguments, [switch]$CaptureOutput) {
    $Target = if ($Arguments.Count -gt 0) { Split-Path -Leaf $Arguments[$Arguments.Count - 1] } else { '' }
    Write-Host ("SMOKE: {0} {1}" -f (Split-Path -Leaf $Path), $Target)
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $Output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    if ($env:GAMMA_ARENA_REGRESSION_VERBOSE -eq '1') { $Output | ForEach-Object { Write-Host $_ } }
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($CaptureOutput) {
        return [PSCustomObject]@{ ExitCode = $ExitCode; Output = ($Output | Out-String) }
    }
    return $ExitCode
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    if (-not $ToolFixturesOnly) {
    $DevFixture = New-Task7Fixture 'dev-fixture'
    Write-FixtureFile $DevFixture 'dev\gamedata\scripts\gamma_arena_test_dev.script' 'dev fixture'
    $DevFixtureExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DevFixture)
    Assert-True ($DevFixtureExit -eq 0) 'Static release policy must ignore dev/gamedata gamma_arena_test_* fixtures.'

    $DocumentationFreeFixture = New-Task7Fixture 'documentation-free-checkout'
    Write-FixtureFile $DocumentationFreeFixture '.git' 'gitdir: fixture'
    Write-FixtureFile $DocumentationFreeFixture 'tools\Build-GammaArena.ps1' ([IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\Build-GammaArena.ps1')))
    foreach ($RequiredStaticArtifact in @(
        'tests\reference\New-GammaArenaRandomSemanticSnapshot.ps1',
        'tests\reference\New-GammaArenaGoldenFights.ps1',
        'tools\New-CompatibilityReport.ps1'
    )) {
        Write-FixtureFile $DocumentationFreeFixture $RequiredStaticArtifact ([IO.File]::ReadAllText((Join-Path $RepoRoot $RequiredStaticArtifact)))
    }
    $DocumentationFreePath = Join-Path $DocumentationFreeFixture 'docs'
    if (Test-Path -LiteralPath $DocumentationFreePath) {
        Remove-Item -LiteralPath $DocumentationFreePath -Recurse -Force
    }
    $DocumentationFreeExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DocumentationFreeFixture)
    Assert-True ($DocumentationFreeExit -eq 0) 'Static project checks must not require the local documentation tree.'

    $AggregateRunnerContent = Get-Content -LiteralPath (Join-Path $RepoRoot 'tools\Test-GammaArena.ps1') -Raw
    Assert-True ($AggregateRunnerContent -notmatch 'Test-BalanceDocumentation\.ps1') 'Standard build checks must not invoke documentation validation.'
    if ($PositiveFixtureOnly) {
        if ($script:Failures.Count -gt 0) {
            foreach ($Failure in $script:Failures) { Write-Host "FAIL: $Failure" }
            exit 1
        }
        $global:LASTEXITCODE = 0
        if ($global:LASTEXITCODE -ne 0) { throw 'Successful smoke harness did not restore the native exit status.' }
        Write-Host 'PASS: isolated positive smoke fixture'
        return
    }

    $MissingReleaseSurfaceFixture = New-Task7Fixture 'missing-current-release-surface'
    Write-FixtureFile $MissingReleaseSurfaceFixture '.git' 'gitdir: fixture'
    Write-FixtureFile $MissingReleaseSurfaceFixture 'tools\Build-GammaArena.ps1' ([IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\Build-GammaArena.ps1')))
    Remove-Item -LiteralPath (Join-Path $MissingReleaseSurfaceFixture 'VERSION') -Force
    Remove-Item -LiteralPath (Join-Path $MissingReleaseSurfaceFixture 'tools\Build-GammaArena.ps1') -Force
    Remove-Item -LiteralPath (Join-Path $MissingReleaseSurfaceFixture 'tests\fixtures\custom-catalog-v10.json') -Force
    $MissingReleaseSurfaceResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingReleaseSurfaceFixture) -CaptureOutput
    Assert-True ($MissingReleaseSurfaceResult.ExitCode -ne 0) 'A real-repo-shaped release surface must fail when current artifacts are missing.'
    foreach ($Diagnostic in @('VERSION is missing','Task 7 release build script is missing.','Task 7 current catalog fixture custom-catalog-v10.json is missing.')) {
        Assert-True ($MissingReleaseSurfaceResult.Output.Contains($Diagnostic)) "Currentness gate must report every missing real-repo artifact: $Diagnostic"
    }

    $NestedGammaRandomFixture = New-Task7Fixture 'nested-gamma-random'
    Write-FixtureFile $NestedGammaRandomFixture 'src\gamedata\scripts\nested\gamma_arena_random.script' 'local value = math.random()'
    $NestedGammaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGammaRandomFixture)
    Assert-True ($NestedGammaRandomExit -ne 0) 'Static policy must reject a nested gamma_arena_* math.random call.'

    $NestedGaRandomFixture = New-Task7Fixture 'nested-ga-random'
    Write-FixtureFile $NestedGaRandomFixture 'src\gamedata\scripts\nested\ga_random.script' 'local value = math.randomseed(7)'
    $NestedGaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGaRandomFixture)
    Assert-True ($NestedGaRandomExit -ne 0) 'Static policy must reject a nested ga_* math.randomseed call.'

    $ReservedLuaFormalFixture = New-Task7Fixture 'reserved-lua-formal'
    $ReservedLuaFormalPath = Join-Path $ReservedLuaFormalFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
    $ReservedLuaFormalContent = Get-Content -LiteralPath $ReservedLuaFormalPath -Raw
    $CorrectedElapsedHelper = '(?ms)local function elapsed_u32\(now,\s*started\)\s*return \(now - started\) % 4294967296\s*end'
    $BrokenElapsedHelper = @'
local function elapsed_u32(now, then)
    return (now - then) % 4294967296
end
'@
    $ReservedLuaFormalMutationCount = ([regex]::Matches($ReservedLuaFormalContent, $CorrectedElapsedHelper)).Count
    Assert-True ($ReservedLuaFormalMutationCount -eq 1) 'Reserved Lua formal regression fixture must find the corrected elapsed_u32 helper exactly once.'
    if ($ReservedLuaFormalMutationCount -eq 1) {
        $ReservedLuaFormalMutated = [regex]::Replace($ReservedLuaFormalContent, $CorrectedElapsedHelper, $BrokenElapsedHelper, 1)
        Write-FixtureFile $ReservedLuaFormalFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script' $ReservedLuaFormalMutated
        $ReservedLuaFormalResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ReservedLuaFormalFixture) -CaptureOutput
        Assert-True ($ReservedLuaFormalResult.ExitCode -ne 0 -and $ReservedLuaFormalResult.Output -match 'gamma_arena_actor_adapter\.script' -and $ReservedLuaFormalResult.Output -match '\bthen\b') 'Static policy must reject a reserved Lua formal parameter with the actor adapter path and keyword diagnostic.'
    }

    $PrefixedMutantCatalogFixture = New-Task7Fixture 'prefixed-mutant-catalog'
    Write-FixtureFile $PrefixedMutantCatalogFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_bloodsucker = 1'
    $PrefixedMutantCatalogExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PrefixedMutantCatalogFixture)
    Assert-True ($PrefixedMutantCatalogExit -ne 0) 'Static policy must reject prefixed mutant class tokens in Arena configs.'

    $PositiveOnlyDxmlFixture = New-Task7Fixture 'positive-only-dxml'
    Write-FixtureFile $PositiveOnlyDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $PositiveOnlyDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PositiveOnlyDxmlFixture)
    Assert-True ($PositiveOnlyDxmlExit -ne 0) 'Static policy must reject a positive-only DXML duplicate query.'

    $MixedDxmlFixture = New-Task7Fixture 'mixed-dxml'
    Write-FixtureFile $MixedDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert><insert>add("btn_gamma_arena")</insert></dxml>'
    $MixedDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MixedDxmlFixture)
    Assert-True ($MixedDxmlExit -ne 0) 'Static policy must reject an unsafe DXML insert even when another insert is guarded.'

    $MissingLuaDxmlGuardFixture = New-Task7Fixture 'missing-lua-dxml-guard'
    Write-FixtureFile $MissingLuaDxmlGuardFixture 'src\gamedata\scripts\modxml_gamma_arena.script' @'
function on_xml_read()
    RegisterScriptCallback("on_xml_read", function(xml_file_name, xml_obj)
        if xml_file_name ~= "ui_mm_main.xml" then return end
        local menu = xml_obj:query("menu_main")
        xml_obj:insertFromXMLString([[<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu" />]], menu[1], #menu[1].kids)
    end)
end
'@
    $MissingLuaDxmlGuardExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingLuaDxmlGuardFixture)
    Assert-True ($MissingLuaDxmlGuardExit -ne 0) 'Static policy must reject a Lua DXML insert without the exact duplicate query guard.'

    $DuplicateLuaDxmlFixture = New-Task7Fixture 'duplicate-lua-dxml-button'
    $DuplicateDxmlPath = Join-Path $DuplicateLuaDxmlFixture 'src\gamedata\scripts\modxml_gamma_arena.script'
    $DuplicateDxmlContent = Get-Content -LiteralPath $DuplicateDxmlPath -Raw
    Write-FixtureFile $DuplicateLuaDxmlFixture 'src\gamedata\scripts\modxml_gamma_arena.script' ($DuplicateDxmlContent + "`nlocal duplicate = [[<btn name=`"btn_gamma_arena`" caption=`"st_gamma_arena_main_menu`" />]]`n")
    $DuplicateLuaDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DuplicateLuaDxmlFixture)
    Assert-True ($DuplicateLuaDxmlExit -ne 0) 'Static policy must reject duplicate Arena button insertion definitions.'

    $NilWriteFixture = New-Task7Fixture 'nil-write'
    $NilWritePath = Join-Path $NilWriteFixture 'src\gamedata\scripts\gamma_arena_session_store.script'
    $NilWriteContent = Get-Content -LiteralPath $NilWritePath -Raw
    Write-FixtureFile $NilWriteFixture 'src\gamedata\scripts\gamma_arena_session_store.script' ($NilWriteContent + "`nlocal function bad(config) config:w_value(`"gamma_arena`", `"launch_pending`", nil) end`n")
    $NilWriteExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NilWriteFixture)
    Assert-True ($NilWriteExit -ne 0) 'Static policy must reject w_value(..., nil) because it persists an empty string.'

    $ValidStaticFixture = New-Task7Fixture 'valid-static-fixture'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\gamma_arena_safe.script' 'local value = 4'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\ga_safe.script' 'local value = 8'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_stalker = 1'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $ValidStaticExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ValidStaticFixture)
    Assert-True ($ValidStaticExit -eq 0) 'Static policy must accept deterministic gamma_arena_/ga_ scripts, a human Arena config, and a guarded DXML insert.'

    $MissingTask2Fixture = New-Task7Fixture 'missing-task2-contract'
    Remove-Item -LiteralPath (Join-Path $MissingTask2Fixture 'src\gamedata\scripts\gamma_arena_rng.script') -Force
    $MissingTask2Exit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingTask2Fixture)
    Assert-True ($MissingTask2Exit -ne 0) 'Static policy must reject a missing required Task 2 contract script.'

    $MissingAggregateRunnerFixture = New-Task7Fixture 'missing-aggregate-runner'
    Remove-Item -LiteralPath (Join-Path $MissingAggregateRunnerFixture 'tools\Test-GammaArena.ps1') -Force
    $MissingAggregateRunnerExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingAggregateRunnerFixture)
    Assert-True ($MissingAggregateRunnerExit -ne 0) 'Static policy must reject a missing aggregate runner.'

    $LogicalDeathFixture = New-Task7Fixture 'logical-death-cancellation'
    $LogicalDeathPath = Join-Path $LogicalDeathFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script'
    $LogicalDeath = Get-Content -LiteralPath $LogicalDeathPath -Raw
    $LogicalDeath = $LogicalDeath.Replace('    self.death_latched = true', @'
    local flags = select(2, ...)
    if type(flags) == "table" then flags.ret_value = false end
    self.deps.actor:hold_after_logical_death()
    self.death_latched = true
'@)
    Write-FixtureFile $LogicalDeathFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script' $LogicalDeath
    $LogicalDeathResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $LogicalDeathFixture) -CaptureOutput
    Assert-True ($LogicalDeathResult.ExitCode -ne 0 -and $LogicalDeathResult.Output -match 'Natural death must not cancel lethal engine damage through flags\.ret_value\.') 'Static policy must reject logical-death cancellation through its intended policy failure.'
    Assert-True ($LogicalDeathResult.Output -match 'Natural death must not invoke logical-death hold or revival behavior\.') 'Static policy must reject logical-death holds through its intended policy failure.'

    $PostDeathHoldFixture = New-Task7Fixture 'post-death-logical-hold'
    $PostDeathHoldPath = Join-Path $PostDeathHoldFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script'
    $PostDeathHold = (Get-Content -LiteralPath $PostDeathHoldPath -Raw).Replace('    local errors = {}', '    self.deps.actor:hold_after_logical_death()' + [Environment]::NewLine + '    local errors = {}')
    Write-FixtureFile $PostDeathHoldFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script' $PostDeathHold
    $PostDeathHoldResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PostDeathHoldFixture) -CaptureOutput
    Assert-True ($PostDeathHoldResult.ExitCode -ne 0 -and $PostDeathHoldResult.Output -match 'Production Arena death control must not invoke logical-death hold, revival, invulnerability, or healing APIs\.') 'Static policy must reject logical-death holds introduced outside actor_on_before_death.'

    $UnsupportedDeathCallbackFixture = New-Task7Fixture 'unsupported-actor-death-callback'
    $UnsupportedDeathCallbackPath = Join-Path $UnsupportedDeathCallbackFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script'
    $UnsupportedDeathCallbackSource = Get-Content -LiteralPath $UnsupportedDeathCallbackPath -Raw
    $UnsupportedDeathCallback = $UnsupportedDeathCallbackSource.Replace('    "actor_on_before_death",', '    "actor_on_before_death",' + [Environment]::NewLine + '    "actor_on_death",')
    Assert-True ($UnsupportedDeathCallback -ne $UnsupportedDeathCallbackSource) 'Unsupported actor-death fixture must preserve supported callbacks and add exactly the forbidden callback.'
    Write-FixtureFile $UnsupportedDeathCallbackFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script' $UnsupportedDeathCallback
    $UnsupportedDeathCallbackResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $UnsupportedDeathCallbackFixture) -CaptureOutput
    Assert-True ($UnsupportedDeathCallbackResult.ExitCode -ne 0 -and $UnsupportedDeathCallbackResult.Output -match 'Bootstrap must not register the nonexistent actor_on_death callback') 'Static policy must reject an added actor_on_death registration while preserving every supported callback.'

    $DefeatStageFixture = New-Task7Fixture 'defeat-confirmation-bypassed'
    $DefeatStagePath = Join-Path $DefeatStageFixture 'src\gamedata\scripts\gamma_arena_session_store.script'
    $DefeatStage = (Get-Content -LiteralPath $DefeatStagePath -Raw).Replace('{ "defeat_stage", "confirmed" }', '{ "defeat_stage", "armed" }')
    Write-FixtureFile $DefeatStageFixture 'src\gamedata\scripts\gamma_arena_session_store.script' $DefeatStage
    $DefeatStageResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DefeatStageFixture) -CaptureOutput
    Assert-True ($DefeatStageResult.ExitCode -ne 0 -and $DefeatStageResult.Output -match 'Defeat confirmation must preserve the confirmed-stage transition and idempotence\.') 'Static policy must reject a confirm_defeat implementation that bypasses the confirmed stage.'

    $DefeatTtlFixture = New-Task7Fixture 'defeat-ttl-removed'
    $DefeatTtlPath = Join-Path $DefeatTtlFixture 'src\gamedata\scripts\gamma_arena_session_store.script'
    $DefeatTtl = (Get-Content -LiteralPath $DefeatTtlPath -Raw).Replace('if now - issued_at > DEFEAT_TOKEN_TTL then', 'if false then')
    Write-FixtureFile $DefeatTtlFixture 'src\gamedata\scripts\gamma_arena_session_store.script' $DefeatTtl
    $DefeatTtlResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DefeatTtlFixture) -CaptureOutput
    Assert-True ($DefeatTtlResult.ExitCode -ne 0 -and $DefeatTtlResult.Output -match 'Defeat token parsing must enforce the defeat TTL\.') 'Static policy must reject defeat token parsing that bypasses the TTL comparison.'

    $UnverifiedExoFixture = New-Task7Fixture 'unverified-powered-exo'
    $UnverifiedExoPath = Join-Path $UnverifiedExoFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script'
    $UnverifiedExo = Get-Content -LiteralPath $UnverifiedExoPath -Raw
    $UnverifiedExo = [regex]::Replace($UnverifiedExo, '(?s)\s*local verified = actor_loadout_call\("GA_ACTOR_EXO_VERIFY_FAILED".*?\s*end\r?\n\s*equipment\.outfit_power = 100', "`r`n                equipment.outfit_power = 100", 1)
    Write-FixtureFile $UnverifiedExoFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script' $UnverifiedExo
    $UnverifiedExoResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $UnverifiedExoFixture) -CaptureOutput
    Assert-True ($UnverifiedExoResult.ExitCode -ne 0 -and $UnverifiedExoResult.Output -match 'Powered-exo CHARGE_OUTFIT must initialize fresh state, then read back and verify 100-percent charge after writing it\.') 'Static policy must reject a powered exo write without CHARGE_OUTFIT readback verification.'

    $NativeEqualityFixture = New-Task7Fixture 'native-game-object-equality'
    $NativeEqualityPath = Join-Path $NativeEqualityFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
    $NativeEqualityContent = Get-Content -LiteralPath $NativeEqualityPath -Raw
    $NativeEqualityNeedle = 'if not parent_id_matches_actor then'
    Assert-True (([regex]::Matches($NativeEqualityContent, [regex]::Escape($NativeEqualityNeedle))).Count -eq 1) 'Native-equality negative fixture must find exactly one parent-ID ownership guard.'
    $NativeEqualityMutant = $NativeEqualityContent.Replace($NativeEqualityNeedle, 'if parent ~= actor or not parent_id_matches_actor then')
    Assert-True ($NativeEqualityMutant -ne $NativeEqualityContent) 'Native-equality negative fixture must reintroduce one unsafe comparison.'
    Write-FixtureFile $NativeEqualityFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script' $NativeEqualityMutant
    $NativeEqualityResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NativeEqualityFixture) -CaptureOutput
    Assert-True ($NativeEqualityResult.ExitCode -ne 0 -and $NativeEqualityResult.Output -match 'Actor inventory ownership must not compare native game_object values') 'Static policy must reject native game_object equality through its intended diagnostic.'

    $PurgeEqualityFixture = New-Task7Fixture 'native-purge-game-object-equality'
    $PurgeEqualityPath = Join-Path $PurgeEqualityFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script'
    $PurgeEqualityContent = Get-Content -LiteralPath $PurgeEqualityPath -Raw
    $PurgeEqualityNeedle = 'if owned_actor_id ~= requested_actor_id then'
    Assert-True (([regex]::Matches($PurgeEqualityContent, [regex]::Escape($PurgeEqualityNeedle))).Count -eq 1) 'Purge-equality negative fixture must find exactly one actor-ID ownership guard.'
    $PurgeEqualityMutant = $PurgeEqualityContent.Replace($PurgeEqualityNeedle, 'if owned.value ~= actor or owned_actor_id ~= requested_actor_id then')
    Assert-True ($PurgeEqualityMutant -ne $PurgeEqualityContent) 'Purge-equality negative fixture must reintroduce one unsafe comparison.'
    Write-FixtureFile $PurgeEqualityFixture 'src\gamedata\scripts\gamma_arena_actor_adapter.script' $PurgeEqualityMutant
    $PurgeEqualityResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PurgeEqualityFixture) -CaptureOutput
    Assert-True ($PurgeEqualityResult.ExitCode -ne 0 -and $PurgeEqualityResult.Output -match 'Actor inventory ownership must not compare native game_object values') 'Static policy must reject purge game_object equality through its intended diagnostic.'

    $BootstrapEqualityFixture = New-Task7Fixture 'native-bootstrap-game-object-equality'
    $BootstrapEqualityPath = Join-Path $BootstrapEqualityFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script'
    $BootstrapEqualityContent = Get-Content -LiteralPath $BootstrapEqualityPath -Raw
    $BootstrapEqualityNeedle = 'return candidate_id ~= nil and actor_id ~= nil and candidate_id == actor_id'
    Assert-True (([regex]::Matches($BootstrapEqualityContent, [regex]::Escape($BootstrapEqualityNeedle))).Count -eq 1) 'Bootstrap-equality negative fixture must find exactly one strict actor-ID return.'
    $BootstrapEqualityMutant = $BootstrapEqualityContent.Replace($BootstrapEqualityNeedle, 'return candidate == current_actor')
    Assert-True ($BootstrapEqualityMutant -ne $BootstrapEqualityContent) 'Bootstrap-equality negative fixture must reintroduce one unsafe comparison.'
    Write-FixtureFile $BootstrapEqualityFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script' $BootstrapEqualityMutant
    $BootstrapEqualityResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $BootstrapEqualityFixture) -CaptureOutput
    Assert-True ($BootstrapEqualityResult.ExitCode -ne 0 -and $BootstrapEqualityResult.Output -match 'Bootstrap actor ownership must not compare native game_object values') 'Static policy must reject bootstrap game_object equality through its intended diagnostic.'

    $MaximumCostPlayerFixture = New-Task7Fixture 'maximum-cost-player-selection'
    $MaximumCostPlayerPath = Join-Path $MaximumCostPlayerFixture 'src\gamedata\scripts\gamma_arena_random_generator.script'
    $MaximumCostPlayer = (Get-Content -LiteralPath $MaximumCostPlayerPath -Raw).Replace('local weapon = stream(request, fight_index, catalogs, "actor_weapon"):pick(weapons)', 'local weapon = pick_affordable_band(stream(request, fight_index, catalogs, "actor_weapon"), weapons, equipment_budget)')
    Write-FixtureFile $MaximumCostPlayerFixture 'src\gamedata\scripts\gamma_arena_random_generator.script' $MaximumCostPlayer
    $MaximumCostPlayerResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-CatalogDiscovery.ps1') @('-RepoRoot', $MaximumCostPlayerFixture) -CaptureOutput
    Assert-True ($MaximumCostPlayerResult.ExitCode -ne 0 -and $MaximumCostPlayerResult.Output -match 'Player loadouts must use weighted class selection, not maximum-cost affordable-band selection') 'Static policy must reject maximum-cost player weapon selection through its intended policy failure.'

    $MissingMandatoryHealerFixture = New-Task7Fixture 'missing-mandatory-medical-healer'
    $MissingMandatoryHealerPath = Join-Path $MissingMandatoryHealerFixture 'src\gamedata\scripts\gamma_arena_medical_generator.script'
    $MissingMandatoryHealerContent = Get-Content -LiteralPath $MissingMandatoryHealerPath -Raw
    $MissingMandatoryHealer = $MissingMandatoryHealerContent.Replace('(not required or category_is_required)', '(not required or true)')
    Assert-True ($MissingMandatoryHealer -ne $MissingMandatoryHealerContent) 'Mandatory-healer negative fixture must remove the health/rare gate exactly once.'
    Write-FixtureFile $MissingMandatoryHealerFixture 'src\gamedata\scripts\gamma_arena_medical_generator.script' $MissingMandatoryHealer
    $MissingMandatoryHealerResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingMandatoryHealerFixture) -CaptureOutput
    Assert-True ($MissingMandatoryHealerResult.ExitCode -ne 0 -and $MissingMandatoryHealerResult.Output -match 'Actor medical generation must require a health/rare healer before optional picks') 'Static policy must reject removal of the mandatory actor healer rule.'

    $MissingMedicalOwnershipFixture = New-Task7Fixture 'missing-physical-medical-ownership'
    $MissingMedicalOwnershipPath = Join-Path $MissingMedicalOwnershipFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
    $MissingMedicalOwnershipContent = Get-Content -LiteralPath $MissingMedicalOwnershipPath -Raw
    $MedicalOwnershipNeedle = 'if item_owner.value ~= self.session_id or record.tagged ~= true then return gamma_arena_result.ok(false) end'
    $MissingMedicalOwnership = $MissingMedicalOwnershipContent.Replace($MedicalOwnershipNeedle, 'if false then return gamma_arena_result.ok(false) end')
    Assert-True ($MissingMedicalOwnership -ne $MissingMedicalOwnershipContent) 'Physical-medical ownership negative fixture must remove the persisted-owner gate exactly once.'
    Write-FixtureFile $MissingMedicalOwnershipFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script' $MissingMedicalOwnership
    $MissingMedicalOwnershipResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingMedicalOwnershipFixture) -CaptureOutput
    Assert-True ($MissingMedicalOwnershipResult.ExitCode -ne 0 -and $MissingMedicalOwnershipResult.Output -match 'Physical medicine consumption must prove registry, live parent/section, and persisted owner before release') 'Static policy must reject physical medicine release without persisted ownership proof.'

    $GenericHeavyExoFixture = New-Task7Fixture 'generic-heavy-powered-exo'
    $GenericHeavyExoPath = Join-Path $GenericHeavyExoFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
    $GenericHeavyExo = (Get-Content -LiteralPath $GenericHeavyExoPath -Raw).Replace('armor_class = "powered_exo"', 'local powered_exo_marker = "powered_exo"' + [Environment]::NewLine + '                    armor_class = "heavy"')
    Write-FixtureFile $GenericHeavyExoFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script' $GenericHeavyExo
    $GenericHeavyExoResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-CatalogDiscovery.ps1') @('-RepoRoot', $GenericHeavyExoFixture) -CaptureOutput
    Assert-True ($GenericHeavyExoResult.ExitCode -ne 0 -and $GenericHeavyExoResult.Output -match 'Dynamic catalog discovery must preserve installed Powered Exos repair_type/proto semantics') 'Static policy must reject generic-heavy powered-exo classification through its semantic precedence failure.'

    $MissingProtoExoFixture = New-Task7Fixture 'missing-proto-powered-exo'
    $MissingProtoExoPath = Join-Path $MissingProtoExoFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
    $MissingProtoExo = (Get-Content -LiteralPath $MissingProtoExoPath -Raw).Replace('or string.find(section, "proto", 1, true) ~= nil', 'or false')
    Write-FixtureFile $MissingProtoExoFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script' $MissingProtoExo
    $MissingProtoExoResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-CatalogDiscovery.ps1') @('-RepoRoot', $MissingProtoExoFixture) -CaptureOutput
    Assert-True ($MissingProtoExoResult.ExitCode -ne 0 -and $MissingProtoExoResult.Output -match 'Dynamic catalog discovery must preserve installed Powered Exos repair_type/proto semantics') 'Static policy must reject removal of the installed proto-exo classification rule.'

    $PostClassificationOverwriteFixture = New-Task7Fixture 'powered-exo-post-classification-overwrite'
    $PostClassificationOverwritePath = Join-Path $PostClassificationOverwriteFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script'
    $PostClassificationOverwrite = (Get-Content -LiteralPath $PostClassificationOverwritePath -Raw).Replace('                outfits[#outfits + 1] = {', '                armor_class = "heavy"' + [Environment]::NewLine + '                outfits[#outfits + 1] = {')
    Write-FixtureFile $PostClassificationOverwriteFixture 'src\gamedata\scripts\gamma_arena_catalog_discovery.script' $PostClassificationOverwrite
    $PostClassificationOverwriteResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-CatalogDiscovery.ps1') @('-RepoRoot', $PostClassificationOverwriteFixture) -CaptureOutput
    Assert-True ($PostClassificationOverwriteResult.ExitCode -ne 0 -and $PostClassificationOverwriteResult.Output -match 'Dynamic catalog discovery must preserve installed Powered Exos repair_type/proto semantics') 'Static policy must reject post-classification overwrites before emitting the outfit record.'

    foreach ($RegistrationCase in @(
        [PSCustomObject]@{ Name = 'runtime_fatal_main_menu_bypasses_terminal_cleanup_error'; Function = 'fatal_main_menu_bypasses_terminal_cleanup_error'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_ordinary_main_menu_still_rejects_terminal_cleanup_error'; Function = 'ordinary_main_menu_still_rejects_terminal_cleanup_error'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_entity_wounded_cleanup_holds_offline_before_release'; Function = 'runtime_entity_wounded_cleanup_holds_offline_before_release'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_entity_living_defeat_cleanup_holds_offline'; Function = 'runtime_entity_living_defeat_cleanup_holds_offline'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_entity_cleanup_quiesce_failure_is_terminal_without_release'; Function = 'runtime_entity_cleanup_quiesce_failure_is_terminal_without_release'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_bootstrap_status_preserves_initialization_result'; Function = 'runtime_bootstrap_status_preserves_initialization_result'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_actor_inventory_native_identity_uses_ids'; Function = 'runtime_actor_inventory_native_identity_uses_ids'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed'; Function = 'runtime_bootstrap_actor_ownership_is_id_only_and_fail_closed'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_ordinary_start_preflight_precedes_mutation'; Function = 'runtime_ordinary_start_preflight_precedes_mutation'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_defeat_menu_fresh_failures_are_bounded'; Function = 'runtime_defeat_menu_fresh_failures_are_bounded'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_defeat_menu_preflight_failure_identity_is_preserved'; Function = 'runtime_defeat_menu_preflight_failure_identity_is_preserved'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'runtime_defeat_menu_default_fatal_path_skips_start_settings'; Function = 'runtime_defeat_menu_default_fatal_path_skips_start_settings'; Path = 'dev\gamedata\scripts\gamma_arena_test_runtime.script' },
        [PSCustomObject]@{ Name = 'master_powered_exo_rate_is_rare'; Function = 'master_powered_exo_rate_is_rare'; Path = 'dev\gamedata\scripts\gamma_arena_test_generator.script' }
    )) {
        $RegistrationFixture = New-Task7Fixture ("registration-removed-" + $RegistrationCase.Name)
        $RegistrationPath = Join-Path $RegistrationFixture $RegistrationCase.Path
        $RegistrationContent = Get-Content -LiteralPath $RegistrationPath -Raw
        $RegistrationPattern = '\{\s*name\s*=\s*"' + [regex]::Escape($RegistrationCase.Name) + '"\s*,\s*fn\s*=\s*' + [regex]::Escape($RegistrationCase.Function) + '\s*\}'
        $RegistrationRegex = [regex]::new($RegistrationPattern)
        Assert-True ($RegistrationRegex.Matches($RegistrationContent).Count -eq 1) "Registration negative fixture must find exactly one case: $($RegistrationCase.Name)."
        $RegistrationMutated = $RegistrationRegex.Replace($RegistrationContent, '', 1)
        Assert-True ($RegistrationMutated -ne $RegistrationContent) "Registration negative fixture must remove exactly one case: $($RegistrationCase.Name)."
        Assert-True ($RegistrationRegex.Matches($RegistrationMutated).Count -eq 0) "Registration negative fixture must remove the matched case exactly once: $($RegistrationCase.Name)."
        Write-FixtureFile $RegistrationFixture $RegistrationCase.Path $RegistrationMutated
        $RegistrationResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $RegistrationFixture) -CaptureOutput
        $RegistrationDiagnostic = "Regression case must be registered exactly: $($RegistrationCase.Name) -> $($RegistrationCase.Function)."
        Assert-True ($RegistrationResult.ExitCode -ne 0 -and $RegistrationResult.Output -match [regex]::Escape($RegistrationDiagnostic)) "Static policy must reject a removed registration while its function definition remains: $($RegistrationCase.Name)."
    }

    $FatalBypassFixture = New-Task7Fixture 'fatal-main-menu-bypass-replaced'
    $FatalBypassPath = Join-Path $FatalBypassFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script'
    $FatalBypassContent = Get-Content -LiteralPath $FatalBypassPath -Raw
    $FatalEnterStart = $FatalBypassContent.IndexOf('function Orchestrator:enter_fatal')
    $FatalEnterEnd = if ($FatalEnterStart -ge 0) { $FatalBypassContent.IndexOf('function Orchestrator:on_callback_error', $FatalEnterStart) } else { -1 }
    Assert-True ($FatalEnterStart -ge 0 -and $FatalEnterEnd -gt $FatalEnterStart) 'Fatal bypass negative fixture must find the enter_fatal slice.'
    if ($FatalEnterStart -ge 0 -and $FatalEnterEnd -gt $FatalEnterStart) {
        $FatalEnter = $FatalBypassContent.Substring($FatalEnterStart, $FatalEnterEnd - $FatalEnterStart)
        $FatalAction = 'self:fatal_main_menu_action()'
        $NormalAction = 'self:main_menu_action()'
        $OriginalFatalActionCount = ([regex]::Matches($FatalEnter, [regex]::Escape($FatalAction))).Count
        $OriginalNormalActionCount = ([regex]::Matches($FatalEnter, [regex]::Escape($NormalAction))).Count
        Assert-True ($OriginalFatalActionCount -eq 2 -and $OriginalNormalActionCount -eq 0) 'Fatal bypass negative fixture must start with exactly two fatal-only actions and no ordinary action.'
        $FatalActionIndex = $FatalEnter.IndexOf($FatalAction)
        Assert-True ($FatalActionIndex -ge 0) 'Fatal bypass negative fixture must find the fatal-only menu action.'
        if ($FatalActionIndex -ge 0) {
            $MutatedFatalEnter = $FatalEnter.Substring(0, $FatalActionIndex) + $NormalAction + $FatalEnter.Substring($FatalActionIndex + $FatalAction.Length)
            $MutatedFatalActionCount = ([regex]::Matches($MutatedFatalEnter, [regex]::Escape($FatalAction))).Count
            $MutatedNormalActionCount = ([regex]::Matches($MutatedFatalEnter, [regex]::Escape($NormalAction))).Count
            Assert-True ($MutatedFatalActionCount -eq ($OriginalFatalActionCount - 1) -and $MutatedNormalActionCount -eq ($OriginalNormalActionCount + 1)) 'Fatal bypass negative fixture must replace exactly one fatal-only action with one ordinary action.'
            $MutatedFatalBypass = $FatalBypassContent.Substring(0, $FatalEnterStart) + $MutatedFatalEnter + $FatalBypassContent.Substring($FatalEnterEnd)
            Write-FixtureFile $FatalBypassFixture 'src\gamedata\scripts\gamma_arena_orchestrator.script' $MutatedFatalBypass
            $FatalBypassResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $FatalBypassFixture) -CaptureOutput
            $FatalBypassDiagnostic = 'Fatal UI must bind its Main menu action to the fatal-only cleanup-bypass exit.'
            Assert-True ($FatalBypassResult.ExitCode -ne 0 -and $FatalBypassResult.Output -match [regex]::Escape($FatalBypassDiagnostic)) 'Static policy must reject replacing the fatal-only Main menu action inside enter_fatal through its intended diagnostic.'
        }
    }

    $QuiesceFixture = New-Task7Fixture 'cleanup-quiesce-call-removed'
    $QuiescePath = Join-Path $QuiesceFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
    $QuiesceContent = Get-Content -LiteralPath $QuiescePath -Raw
    $DriveCleanupStart = $QuiesceContent.IndexOf('function EntityAdapter:drive_cleanup')
    $DriveCleanupEnd = if ($DriveCleanupStart -ge 0) { $QuiesceContent.IndexOf('function EntityAdapter:fail_and_rollback', $DriveCleanupStart) } else { -1 }
    Assert-True ($DriveCleanupStart -ge 0 -and $DriveCleanupEnd -gt $DriveCleanupStart) 'Quiesce negative fixture must find the drive_cleanup slice.'
    if ($DriveCleanupStart -ge 0 -and $DriveCleanupEnd -gt $DriveCleanupStart) {
        $DriveCleanup = $QuiesceContent.Substring($DriveCleanupStart, $DriveCleanupEnd - $DriveCleanupStart)
        $QuiesceCall = 'self:quiesce_live_owned_npcs()'
        $OriginalQuiesceCount = ([regex]::Matches($DriveCleanup, [regex]::Escape($QuiesceCall))).Count
        Assert-True ($OriginalQuiesceCount -eq 1) 'Quiesce negative fixture must start with exactly one cleanup quiesce call.'
        $QuiesceCallIndex = $DriveCleanup.IndexOf($QuiesceCall)
        Assert-True ($QuiesceCallIndex -ge 0) 'Quiesce negative fixture must find the cleanup quiesce call.'
        if ($QuiesceCallIndex -ge 0) {
            $MutatedDriveCleanup = $DriveCleanup.Remove($QuiesceCallIndex, $QuiesceCall.Length)
            $MutatedQuiesceCount = ([regex]::Matches($MutatedDriveCleanup, [regex]::Escape($QuiesceCall))).Count
            Assert-True ($MutatedQuiesceCount -eq 0) 'Quiesce negative fixture must remove the only cleanup quiesce call.'
            $MutatedQuiesce = $QuiesceContent.Substring(0, $DriveCleanupStart) + $MutatedDriveCleanup + $QuiesceContent.Substring($DriveCleanupEnd)
            Write-FixtureFile $QuiesceFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script' $MutatedQuiesce
            $QuiesceResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $QuiesceFixture) -CaptureOutput
            $QuiesceDiagnostic = 'Entity cleanup must quiesce living owned NPCs before it can submit releases.'
            Assert-True ($QuiesceResult.ExitCode -ne 0 -and $QuiesceResult.Output -match [regex]::Escape($QuiesceDiagnostic)) 'Static policy must reject removing cleanup quiescence before release submission through its intended diagnostic.'
        }
    }

    $OwnerBeforeRetirementFixture = New-Task7Fixture 'owner-before-absence-retirement'
    $OwnerBeforeRetirementPath = Join-Path $OwnerBeforeRetirementFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
    $OwnerBeforeRetirementContent = Get-Content -LiteralPath $OwnerBeforeRetirementPath -Raw
    $OwnerBeforeRetirementStart = $OwnerBeforeRetirementContent.IndexOf('function EntityAdapter:quiesce_live_owned_npcs')
    $OwnerBeforeRetirementEnd = if ($OwnerBeforeRetirementStart -ge 0) { $OwnerBeforeRetirementContent.IndexOf('function EntityAdapter:quarantine_live_records', $OwnerBeforeRetirementStart) } else { -1 }
    Assert-True ($OwnerBeforeRetirementStart -ge 0 -and $OwnerBeforeRetirementEnd -gt $OwnerBeforeRetirementStart) 'Owner-before-retirement negative fixture must find the quiesce slice.'
    if ($OwnerBeforeRetirementStart -ge 0 -and $OwnerBeforeRetirementEnd -gt $OwnerBeforeRetirementStart) {
        $OwnerBeforeRetirementSlice = $OwnerBeforeRetirementContent.Substring($OwnerBeforeRetirementStart, $OwnerBeforeRetirementEnd - $OwnerBeforeRetirementStart)
        $OwnerRead = 'self:load_owner_tag(record.id)'
        $AbsenceRetirement = 'record.released = true'
        $OriginalOwnerReadCount = ([regex]::Matches($OwnerBeforeRetirementSlice, [regex]::Escape($OwnerRead))).Count
        $AbsenceRetirementIndex = $OwnerBeforeRetirementSlice.IndexOf($AbsenceRetirement)
        Assert-True ($OriginalOwnerReadCount -eq 1 -and $AbsenceRetirementIndex -ge 0) 'Owner-before-retirement negative fixture must start with one owner read and one absence retirement marker.'
        if ($OriginalOwnerReadCount -eq 1 -and $AbsenceRetirementIndex -ge 0) {
            $PrematureOwnerRead = 'local premature_owner = ' + $OwnerRead + [Environment]::NewLine + '                '
            $MutatedOwnerBeforeRetirementSlice = $OwnerBeforeRetirementSlice.Insert($AbsenceRetirementIndex, $PrematureOwnerRead)
            $MutatedOwnerReadCount = ([regex]::Matches($MutatedOwnerBeforeRetirementSlice, [regex]::Escape($OwnerRead))).Count
            Assert-True ($MutatedOwnerReadCount -eq ($OriginalOwnerReadCount + 1)) 'Owner-before-retirement negative fixture must inject exactly one owner read before absence retirement.'
            $MutatedOwnerBeforeRetirement = $OwnerBeforeRetirementContent.Substring(0, $OwnerBeforeRetirementStart) + $MutatedOwnerBeforeRetirementSlice + $OwnerBeforeRetirementContent.Substring($OwnerBeforeRetirementEnd)
            Write-FixtureFile $OwnerBeforeRetirementFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script' $MutatedOwnerBeforeRetirement
            $OwnerBeforeRetirementResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $OwnerBeforeRetirementFixture) -CaptureOutput
            $OwnerBeforeRetirementDiagnostic = 'Quiescence must prove internal identity before server lookup, retire authoritative absence before persisted-tag proof, and prove the current owner before offline hold.'
            Assert-True ($OwnerBeforeRetirementResult.ExitCode -ne 0 -and $OwnerBeforeRetirementResult.Output -match [regex]::Escape($OwnerBeforeRetirementDiagnostic)) 'Static policy must reject owner reads moved before authoritative-absence retirement through its intended ordering diagnostic.'
        }
    }

    $BoundedLogFixture = New-Task7Fixture 'bounded-log-native-sink-removed'
    $BoundedLogPath = Join-Path $BoundedLogFixture 'src\gamedata\scripts\gamma_arena_log.script'
    $BoundedLogContent = Get-Content -LiteralPath $BoundedLogPath -Raw
    $BoundedLogCall = 'pcall(printf, "%s", native_payload)'
    $UnboundedLogCall = 'pcall(printf, "%s%s%s", "", native_payload, "")'
    $BoundedLogCallCount = ([regex]::Matches($BoundedLogContent, [regex]::Escape($BoundedLogCall))).Count
    Assert-True ($BoundedLogCallCount -eq 1) 'Bounded logger negative fixture must find exactly one constant-format native sink call.'
    if ($BoundedLogCallCount -eq 1) {
        $MutatedBoundedLog = $BoundedLogContent.Replace($BoundedLogCall, $UnboundedLogCall)
        Write-FixtureFile $BoundedLogFixture 'src\gamedata\scripts\gamma_arena_log.script' $MutatedBoundedLog
        $BoundedLogResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $BoundedLogFixture) -CaptureOutput
        $BoundedLogDiagnostic = 'Logger bounded native-sink contract is missing: pcall(printf, "%s", native_payload)'
        Assert-True ($BoundedLogResult.ExitCode -ne 0 -and $BoundedLogResult.Output -match [regex]::Escape($BoundedLogDiagnostic)) 'Static policy must reject replacing the bounded constant-format native logger sink.'
    }

    $RuntimeChildFixture = New-Task7Fixture 'runtime-child-adoption-call-removed'
    $RuntimeChildPath = Join-Path $RuntimeChildFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
    $RuntimeChildContent = Get-Content -LiteralPath $RuntimeChildPath -Raw
    $RuntimeChildDriveStart = $RuntimeChildContent.IndexOf('function EntityAdapter:drive_cleanup')
    $RuntimeChildDriveEnd = if ($RuntimeChildDriveStart -ge 0) { $RuntimeChildContent.IndexOf('function EntityAdapter:fail_and_rollback', $RuntimeChildDriveStart) } else { -1 }
    Assert-True ($RuntimeChildDriveStart -ge 0 -and $RuntimeChildDriveEnd -gt $RuntimeChildDriveStart) 'Runtime-child negative fixture must find the drive_cleanup slice.'
    if ($RuntimeChildDriveStart -ge 0 -and $RuntimeChildDriveEnd -gt $RuntimeChildDriveStart) {
        $RuntimeChildDrive = $RuntimeChildContent.Substring($RuntimeChildDriveStart, $RuntimeChildDriveEnd - $RuntimeChildDriveStart)
        $RuntimeChildCall = 'self:adopt_cleanup_children()'
        $RuntimeChildCallCount = ([regex]::Matches($RuntimeChildDrive, [regex]::Escape($RuntimeChildCall))).Count
        Assert-True ($RuntimeChildCallCount -eq 2) 'Runtime-child negative fixture must find initial and late adoption calls.'
        if ($RuntimeChildCallCount -eq 2) {
            $MutatedRuntimeChildDrive = $RuntimeChildDrive.Replace($RuntimeChildCall, '0')
            $MutatedRuntimeChild = $RuntimeChildContent.Substring(0, $RuntimeChildDriveStart) + $MutatedRuntimeChildDrive + $RuntimeChildContent.Substring($RuntimeChildDriveEnd)
            Write-FixtureFile $RuntimeChildFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script' $MutatedRuntimeChild
            $RuntimeChildResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $RuntimeChildFixture) -CaptureOutput
            $RuntimeChildDiagnostic = 'Entity cleanup must adopt current runtime children before NPC release.'
            Assert-True ($RuntimeChildResult.ExitCode -ne 0 -and $RuntimeChildResult.Output -match [regex]::Escape($RuntimeChildDiagnostic)) 'Static policy must reject removing just-in-time runtime-child adoption from cleanup.'
        }
    }

    $SaveGuardFixture = New-Task7Fixture 'arena-save-guard-predicate-removed'
    $SaveGuardPath = Join-Path $SaveGuardFixture 'src\gamedata\scripts\gamma_arena_save_guard.script'
    $SaveGuardContent = Get-Content -LiteralPath $SaveGuardPath -Raw
    $SavePredicate = 'token:lower() == "save"'
    Assert-True (([regex]::Matches($SaveGuardContent, [regex]::Escape($SavePredicate))).Count -eq 1) 'Save-guard negative fixture must find exactly one exact save predicate.'
    $SaveGuardContent = $SaveGuardContent.Replace($SavePredicate, 'token:lower() == "cfg_save"')
    Write-FixtureFile $SaveGuardFixture 'src\gamedata\scripts\gamma_arena_save_guard.script' $SaveGuardContent
    $SaveGuardResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $SaveGuardFixture) -CaptureOutput
    Assert-True ($SaveGuardResult.ExitCode -ne 0 -and $SaveGuardResult.Output -match 'Arena save guard contract is missing') 'Static policy must reject removal of exact Arena save suppression.'

    $ForensicRingFixture = New-Task7Fixture 'arena-forensic-ring-unbounded'
    $ForensicRingPath = Join-Path $ForensicRingFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script'
    $ForensicRingContent = Get-Content -LiteralPath $ForensicRingPath -Raw
    $ForensicRingContent = $ForensicRingContent.Replace('FORENSIC_RING_SIZE = 12', 'FORENSIC_RING_SIZE = 13')
    Write-FixtureFile $ForensicRingFixture 'src\gamedata\scripts\gamma_arena_entity_adapter.script' $ForensicRingContent
    $ForensicRingResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ForensicRingFixture) -CaptureOutput
    Assert-True ($ForensicRingResult.ExitCode -ne 0 -and $ForensicRingResult.Output -match 'Arena NPC forensic contract is missing: FORENSIC_RING_SIZE = 12') 'Static policy must reject an expanded forensic ring.'

    $ForensicCallbackFixture = New-Task7Fixture 'arena-forensic-callback-removed'
    $ForensicCallbackPath = Join-Path $ForensicCallbackFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script'
    $ForensicCallbackContent = Get-Content -LiteralPath $ForensicCallbackPath -Raw
    $ForensicCallbackContent = $ForensicCallbackContent.Replace('"npc_on_before_hit",', '')
    Write-FixtureFile $ForensicCallbackFixture 'src\gamedata\scripts\gamma_arena_bootstrap.script' $ForensicCallbackContent
    $ForensicCallbackResult = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ForensicCallbackFixture) -CaptureOutput
    Assert-True ($ForensicCallbackResult.ExitCode -ne 0 -and $ForensicCallbackResult.Output -match 'Arena NPC forensic callback is not registered') 'Static policy must reject removal of an Arena forensic callback.'
    }

    if ($StaticFixturesOnly) {
        if ($script:Failures.Count -gt 0) {
            foreach ($Failure in $script:Failures) { Write-Host "FAIL: $Failure" }
            exit 1
        }
        $global:LASTEXITCODE = 0
        if ($global:LASTEXITCODE -ne 0) { throw 'Successful smoke harness did not restore the native exit status.' }
        Write-Host 'PASS: static smoke fixtures passed'
        return
    }

    $OutsideReleaseOutput = Join-Path $TempRoot 'outside-release-output'
    $ReleaseOutputExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Build-GammaArena.ps1') @('-Configuration', 'Release', '-OutputDirectory', $OutsideReleaseOutput)
    Assert-True ($ReleaseOutputExit -ne 0) 'Release build must reject an output directory outside <RepoRoot>\dist.'

    $TerminalFailureLog = Join-Path $TempRoot 'terminal-failure.log'
    [IO.File]::WriteAllText($TerminalFailureLog, "[GammaArenaTest] START`r`n[GammaArenaTest] ALL PASS`r`n[GammaArenaTest] SUITE FAILED`r`n", (New-Object Text.UTF8Encoding($false)))
    $TerminalFailureExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Read-GammaArenaGameTests.ps1') @('-LogPath', $TerminalFailureLog)
    Assert-True ($TerminalFailureExit -ne 0) 'Game-log reader must reject a test status after ALL PASS.'

    $FakeMo2Root = Join-Path $TempRoot 'fake-mo2'
    $UnsafeTarget = Join-Path $FakeMo2Root 'mods\Gamma Arena DEV'
    Write-FixtureFile $FakeMo2Root 'mods\Gamma Arena DEV' 'must not be replaced'
    $DeployExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Deploy-GammaArenaDev.ps1') @('-Mo2Root', $FakeMo2Root)
    Assert-True ($DeployExit -ne 0) 'Dev deployment must reject an existing non-directory target.'
    Assert-True (Test-Path -LiteralPath $UnsafeTarget -PathType Leaf) 'Dev deployment must preserve an existing non-directory target.'

    $ReparseMo2Root = Join-Path $TempRoot 'reparse-mo2'
    $ReparseTarget = Join-Path $ReparseMo2Root 'mods\Gamma Arena DEV'
    $ReparseDestination = Join-Path $TempRoot 'reparse-destination'
    New-Item -ItemType Directory -Path (Join-Path $ReparseMo2Root 'mods') -Force | Out-Null
    New-Item -ItemType Directory -Path $ReparseDestination -Force | Out-Null
    New-Item -ItemType Junction -Path $ReparseTarget -Target $ReparseDestination | Out-Null
    $ReparseDeployExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tools\Deploy-GammaArenaDev.ps1') @('-Mo2Root', $ReparseMo2Root)
    Assert-True ($ReparseDeployExit -ne 0) 'Dev deployment must reject an existing reparse-point target.'
    Assert-True (((Get-Item -LiteralPath $ReparseTarget).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Dev deployment must preserve an existing reparse-point target.'
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
}

if ($script:Failures.Count -gt 0) {
    foreach ($Failure in $script:Failures) {
        Write-Host "FAIL: $Failure"
    }
    exit 1
}

$global:LASTEXITCODE = 0
if ($global:LASTEXITCODE -ne 0) { throw 'Successful smoke harness did not restore the native exit status.' }
Write-Host 'PASS: tool regression smoke checks passed'
