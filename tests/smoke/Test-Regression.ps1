[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:Failures = New-Object System.Collections.Generic.List[string]
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gamma-arena-regression-" + [Guid]::NewGuid().ToString('N'))

& (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1') -Verify
if (-not $?) { exit 1 }

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

function New-StaticFixture([string]$Name) {
    $Root = Join-Path $TempRoot $Name
    New-Item -ItemType Directory -Path (Join-Path $Root 'src\gamedata') -Force | Out-Null
    foreach ($File in @('VERSION', '.gitattributes', '.gitignore', 'README.md', 'CHANGELOG.md')) {
        Write-FixtureFile $Root $File 'fixture'
    }
    return $Root
}

function Add-Task2ContractFixture([string]$Root) {
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_assert.script' @'
function equals() end
function is_true() end
function is_false() end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_runner.script' @'
function run_case() end
function on_game_start()
    return pcall(function()
        return gamma_arena_test_domain.run(run_case)
    end)
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_domain.script' @'
function run() end
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
states = {}
events = {}
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
    return { session_seed = normalized_seed, fight_index = fight_index }
end
function stable_encode()
    return "session_seed=" .. "fight_index="
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_validator.script' @'
function validate()
    local expected_fight_id = "ga-1-0-g1-c1-l1"
    local difficulty = { enemy_total_budget = 1 }
    local opponent_count = 1
    local slot_base = math.floor(difficulty.enemy_total_budget / opponent_count)
    gamma_arena_number.is_integer(1)
    return "GA_MODE_INVALID GA_LEVEL_INVALID GA_LAYOUT_VERSION_INVALID GA_OPPONENT_SLOT_INVALID GA_FIGHT_ID_INVALID GA_FIGHTSPEC_TYPE_INVALID GA_LOADOUT_COMBINATION_INVALID GA_ENEMY_SLOT_BUDGET_INVALID"
end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_generator.script' 'function run() end'
    Write-FixtureFile $Root 'src\gamedata\configs\gamma_arena\gamma_arena_catalogs.ltx' @'
[meta]
schema_version = 1
revision = 1
gamma_arena_bandit_novice
gamma_arena_bandit_trainee
gamma_arena_bandit_experienced
gamma_arena_bandit_veteran
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
opponent_spawn_paths = bar_arena_walk_3_1,bar_arena_walk_3_2,bar_arena_walk_6_1,bar_arena_walk_6_3,bar_arena_walk_6_6,bar_arena_monstr_walk
'@
    Write-FixtureFile $Root 'src\gamedata\configs\mod_system_gamma_arena_npcs.ltx' @'
[gamma_arena_bandit_novice]:sim_default_bandit_0
[gamma_arena_bandit_veteran]:sim_default_bandit_3
'@
    Write-FixtureFile $Root 'src\gamedata\configs\items\settings\npc_loadouts\mod_npc_loadouts_gamma_arena.ltx' @'
![skip_npcs]
gamma_arena_bandit_novice = bandit
gamma_arena_bandit_trainee = bandit
gamma_arena_bandit_experienced = bandit
gamma_arena_bandit_veteran = bandit
'@
    Write-FixtureFile $Root 'tests\fixtures\golden-fights-v1.txt' @'
seed=0,difficulty=rookie,fight=0,stable_encode=schema_version=1|session_seed=1|fight_index=0|fight_id=ga-1-0-g1-c1-l1|diagnostic=FightSpecV1 rookie
seed=1,difficulty=stalker,fight=0,stable_encode=schema_version=1|session_seed=1|fight_index=0|fight_id=ga-1-0-g1-c1-l1|diagnostic=FightSpecV1 stalker
seed=3735928559,difficulty=veteran,fight=7,stable_encode=schema_version=1|session_seed=1588444913|fight_index=7|fight_id=ga-1588444913-7-g1-c1-l1|diagnostic=FightSpecV1 veteran
seed=4294967295,difficulty=master,fight=31,stable_encode=schema_version=1|session_seed=3|fight_index=31|fight_id=ga-3-31-g1-c1-l1|diagnostic=FightSpecV1 master
'@
    Write-FixtureFile $Root 'schemas\fight-spec-v1.md' 'fixture'
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_config_tx.script' @'
local function _snapshot_unchecked()
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
local markers = "ga1: launch_pending launch_token launch_mode_id launch_difficulty_id launch_seed_mode launch_session_seed resume_pending resume_session_id resume_session_nonce resume_next_fight_index resume_checkpoint_name resume_schema_version new_game_difficulty new_game_economy new_game_economy_treasure new_game_character_name new_game_faction new_game_map new_game_money new_game_loadout new_game_story_mode new_game_icon new_game_hardcore_mode new_game_hardcore_mode_lives new_game_hardcore_mode_regenerate new_game_survival_mode new_game_azazel_mode new_game_warfare new_game_campfire_mode new_game_conditions_mode new_game_timer_mode new_game_opened_routes new_game_test GA_RESUME_ALREADY_PENDING GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_INTENT_CONFLICT GA_LAUNCH_STALE_CLEARED GA_RESUME_CHECKPOINT_MISMATCH GA_RESUME_FIGHT_INDEX_MISMATCH GA_SESSION_GENERATOR_VERSION_INVALID GA_SESSION_UNKNOWN_FIELD"
local function remove(config, section, key) config:remove_line(section, key) end
local function validate_expected_session() end
local function validate_persisted_launch_request() end
gamma_arena_config_tx.run()
function new_store() end
function parse_manual_seed() end
function validate_start_request() end
function random_session_seed() end
function save_preferences() end
function issue_launch() end
function parse_launch_token() end
function consume_launch() end
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
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_bootstrap.script' @'
local callback_names = { "on_game_load", "actor_on_first_update", "actor_on_update", "actor_on_before_death", "npc_on_death_callback", "save_state", "load_state", "on_before_save_input", "on_before_load_input", "actor_on_net_destroy", "on_before_level_changing" }
local rollback = "GA_BOOTSTRAP_REGISTRATION_POISONED"
local function invoke_callback(result, callback)
    pcall(callback)
    if result.ok == false then return callback() end
end
local function guarded(active)
    if not active then return end
end
local task6 = "gamma_arena_actor_adapter.new gamma_arena_checkpoint_adapter.new level.disable_input level.enable_input safe_release_manager.release"
function make_callbacks() end
function new_registrar() return { register_all = function() UnregisterScriptCallback("x", guarded) end } end
function on_game_start() return new_registrar():register_all() end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_compat.script' @'
local markers = "RegisterScriptCallback UnregisterScriptCallback ini_file system_ini alife alife_create alife_create_item alife_release_id getFS se_save_var level.patrol_path_exists patrol db.actor axr_main.config safe_release_manager.release l05_bar AI_STL_S bandit point level_vertex_id game_vertex_id 4294967295 GA_PREFLIGHT_PATROL_MISSING GA_PREFLIGHT_PATROL_INVALID GA_PREFLIGHT_SECTION_MISSING GA_NPC_CLASS_API_MISSING GA_NPC_CLASS_MISSING GA_NPC_CLASS_READ_FAILED GA_NPC_CLASS_INVALID GA_NPC_COMMUNITY_API_MISSING GA_NPC_COMMUNITY_MISSING GA_NPC_COMMUNITY_READ_FAILED GA_NPC_COMMUNITY_INVALID"
local task6_markers = "getFS.update_path getFS.file_rename getFS.file_delete exec_console_cmd time_global level.disable_input level.enable_input db.actor.iterate_inventory db.actor.set_bleeding db.actor.set_actor_position"
function preflight() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_orchestrator.script' @'
local markers = "inspect_intents consume_launch prepare_resume gamma_arena_session st_gamma_arena_manual_save_disabled expect_checkpoint_reload GA_INTENT_CONFLICT GA_LAUNCH_REQUIRES_NEW_GAME disconnect pending_load_state awaiting_activation on_callback_result_error GA_DISCONNECT_FAILED main_menu_executed normalize_for_checkpoint verify_inventory_empty checkpoint request_checkpoint_restore runtime_stage begin_resume_recovery GA_RUNTIME_CLEANUP_PENDING cleanup_ready_for_disconnect normalize_resume_preparation"
function new() self.cleanup_required = true; return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_actor_adapter.script' @'
local markers = "normalize_for_checkpoint verify_inventory_empty apply_loadout reset_after_victory hold_after_logical_death begin_update iterate_inventory release_item_id set_health_ex set_power set_radiation set_bleeding set_psy_health give_money disable_effects_timer set_actor_position set_actor_direction input_owned GA_ACTOR_INACTIVE"
local parent_method = "parent"
local effects = { "set_bleeding", 1 }
function new() return markers, effects end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_checkpoint_adapter.script' @'
local CHECKPOINT_NAME = "_gamma_arena_checkpoint"
local markers = "WAITING_STABLE HIDING READY UNHIDING LOADING REHIDING CLEANING ERROR .scop .scoc .dds .gamma_arena_hidden GA_CHECKPOINT_TIMEOUT GA_CHECKPOINT_UNSAFE_PATH issue_resume consume_resume clear_resume_if_matches pending_or_timeout elapsed_ms engine_fs_port update_path file_rename file_delete GA_CHECKPOINT_LOAD_TIMEOUT last_mutation_cause mutation_attempt begin_resume_recovery GA_CHECKPOINT_RECOVERY_MISSING GA_CHECKPOINT_RECOVERY_INCONSISTENT GA_CHECKPOINT_RECOVERY_MISMATCH GA_CHECKPOINT_RECOVERY_TIMEOUT prepared_resume"
local mode = "rb"
local save_command = "save " .. CHECKPOINT_NAME
local load_command = "load " .. CHECKPOINT_NAME
local function keep_required_target_pending(target_info, required)
    if target_info.value.exists then
        if required and target_info.value.size <= 0 then return false end
    end
end
function new() return markers end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_runtime.script' @'
local markers = "runtime_preflight_aggregates_in_stable_order runtime_preflight_requires_community_for_every_custom_profile runtime_preflight_requires_human_class_for_every_custom_profile runtime_preflight_rejects_missing_profile_value_apis runtime_preflight_normalizes_effective_bandit_community runtime_wrong_level_skips_patrol_resolution runtime_launch_consumes_before_preflight_once runtime_activation_requires_game_load_boundary runtime_invalid_or_expired_launch_never_reaches_preflight runtime_ordinary_loaded_save_rejects_stray_launch runtime_ordinary_loaded_save_rejects_stray_resume runtime_new_game_does_not_reuse_prior_load_state_latch runtime_game_load_boundary_drops_prior_runtime_generation runtime_config_quarantine_propagates_to_fatal runtime_save_payload_is_plain_deep_copy runtime_manual_save_and_load_flags_are_blocked runtime_callback_boundary_routes_exceptions_once runtime_callback_boundary_routes_false_results_once runtime_inactive_callback_results_remain_benign runtime_active_save_failure_enters_fatal_once runtime_fatal_main_menu_retries_throw_then_becomes_idempotent runtime_fatal_main_menu_retries_explicit_false runtime_fatal_ui_helper_propagates_callback_results runtime_bootstrap_registration_rolls_back_every_position runtime_bootstrap_registration_poison_blocks_retry runtime_bootstrap_requires_unregister_before_composition runtime_net_destroy_teardown_honors_checkpoint_latch runtime_unexpected_net_destroy_clears_external_route runtime_actor_inventory_release_is_deferred_and_verified runtime_actor_normalization_uses_gamma_bleeding_sentinel runtime_actor_input_ownership_is_idempotent runtime_actor_rejects_coincident_patrol_points runtime_checkpoint_requires_stable_required_files runtime_checkpoint_allows_absent_or_late_dds runtime_checkpoint_wrap_clock_times_out runtime_checkpoint_verifies_rename_and_delete_postconditions runtime_checkpoint_recovers_mixed_crash_states runtime_checkpoint_persists_intent_before_load runtime_checkpoint_consumes_intent_only_after_rehide runtime_checkpoint_rejects_mismatched_resume runtime_checkpoint_cleanup_is_idempotent_in_every_state runtime_checkpoint_two_sessions_leave_no_stale_paths runtime_checkpoint_ready_gates_generation"
local task6_preflight_marker = "runtime_preflight_requires_task6_actor_checkpoint_ports"
local review_markers = "runtime_actor_rejects_nil_inventory_parent runtime_actor_rejects_throwing_inventory_accessors runtime_checkpoint_load_wait_is_bounded_and_wrap_safe runtime_checkpoint_transient_mutation_failures_retry_to_success runtime_checkpoint_zero_required_target_waits_for_timeout runtime_checkpoint_permanent_mutation_throws_time_out runtime_checkpoint_fresh_process_recovers_all_exact_layouts runtime_checkpoint_fresh_recovery_rejects_missing_inconsistent_and_mismatch runtime_checkpoint_fresh_recovery_rejects_persisted_intent_drift runtime_fatal_recovery_waits_for_cleanup_before_disconnect runtime_pre_session_fatal_waits_for_cleanup_before_disconnect runtime_prepare_resume_legacy_mismatch_is_normalized"
function run() return markers end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\modxml_gamma_arena.script' @'
local function on_read(xml_file_name, xml_obj)
    local normalized = string.lower(string.gsub(xml_file_name, "/", "\\"))
    if normalized ~= "ui\\ui_mm_main.xml" then return end
    local existing = xml_obj:query("menu_main btn[name=btn_gamma_arena]")
    if existing and #existing > 0 then return end
    local menu = xml_obj:query("menu_main")
    if menu and #menu > 0 then
        xml_obj:insertFromXMLString([[<btn name="btn_gamma_arena" caption="st_gamma_arena_main_menu" />]], menu[1], #menu[1].kids)
    end
end
function on_xml_read()
    pcall(gamma_arena_log.error, "GA_DXML", "fixture", {})
    RegisterScriptCallback("on_xml_read", on_read)
end
'@
    Write-FixtureFile $Root 'src\gamedata\scripts\gamma_arena_main_menu.script' @'
local function bind(menu)
    if type(menu.AddCallback) == "function" then
        menu:AddCallback("btn_gamma_arena", ui_events.BUTTON_CLICKED, function() end, menu)
    end
end
function on_game_start()
    RegisterScriptCallback("main_menu_on_init", bind)
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
function UIStart:ShowFatal() self.fatal_main_menu = true end
function invoke_fatal_main_menu(callback) return callback() end
function UIStart:OnFatalMainMenu() return invoke_fatal_main_menu(self.callback) end
function create() end
function show_fatal() end
'@
    Write-FixtureFile $Root 'dev\gamedata\scripts\gamma_arena_test_migrations.script' @'
local function stale_launch_is_recovered_by_new_store() end
local function same_store_corrupt_launch_is_replaced() end
local function resume_rejects_tampered_expected_session() end
local function mutation_failure_matrix_is_crash_safe() end
local function recovery_failure_quarantines_transaction() end
local function read_and_false_return_faults_are_safe() end
local function stale_cleanup_and_conflict_faults_are_safe() end
local function matching_resume_cleanup_is_session_scoped() end
local function prepared_resume_consume_rejects_persisted_drift() end
local function dxml_accepts_canonical_callback_path() end
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
<w><gamma_arena_start><title/><difficulty/><seed/><random_seed/><validation/><start/><back/><fatal><fatal_text/><fatal_main_menu/></fatal></gamma_arena_start></w>
'@
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
</string_table>
'@
    Write-FixtureFile $Root 'src\gamedata\configs\text\rus\st_gamma_arena.xml' $Locale
    Write-FixtureFile $Root 'src\gamedata\configs\text\eng\st_gamma_arena.xml' $Locale
    Write-FixtureFile $Root 'tests\fixtures\settings-v0.ltx' "[gamma_arena]`nlast_difficulty_id = veteran`nlast_seed_mode = manual"
    Write-FixtureFile $Root 'tests\fixtures\settings-v1.ltx' "[gamma_arena]`nsettings_schema_version = 1`nlast_difficulty_id = master`nlast_seed_mode = random"
    Write-FixtureFile $Root 'schemas\session-v1.md' 'session_nonce checkpoint_name resume_session_nonce FightSpec FightRegistry ResumeIntent non-durable ga1:<issued_at_epoch>:<nonce> 600'
    Write-FixtureFile $Root 'docs\compatibility.md' 'fixture'
}

function Invoke-PowerShellFile([string]$Path, [string[]]$Arguments) {
    $PreviousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1
    $ExitCode = $LASTEXITCODE
    $ErrorActionPreference = $PreviousErrorActionPreference
    return $ExitCode
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    $DevFixture = New-StaticFixture 'dev-fixture'
    Add-Task2ContractFixture $DevFixture
    Write-FixtureFile $DevFixture 'dev\gamedata\scripts\gamma_arena_test_dev.script' 'dev fixture'
    $DevFixtureExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DevFixture)
    Assert-True ($DevFixtureExit -eq 0) 'Static release policy must ignore dev/gamedata gamma_arena_test_* fixtures.'

    $NestedGammaRandomFixture = New-StaticFixture 'nested-gamma-random'
    Add-Task2ContractFixture $NestedGammaRandomFixture
    Write-FixtureFile $NestedGammaRandomFixture 'src\gamedata\scripts\nested\gamma_arena_random.script' 'local value = math.random()'
    $NestedGammaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGammaRandomFixture)
    Assert-True ($NestedGammaRandomExit -ne 0) 'Static policy must reject a nested gamma_arena_* math.random call.'

    $NestedGaRandomFixture = New-StaticFixture 'nested-ga-random'
    Add-Task2ContractFixture $NestedGaRandomFixture
    Write-FixtureFile $NestedGaRandomFixture 'src\gamedata\scripts\nested\ga_random.script' 'local value = math.randomseed(7)'
    $NestedGaRandomExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NestedGaRandomFixture)
    Assert-True ($NestedGaRandomExit -ne 0) 'Static policy must reject a nested ga_* math.randomseed call.'

    $PrefixedMutantCatalogFixture = New-StaticFixture 'prefixed-mutant-catalog'
    Add-Task2ContractFixture $PrefixedMutantCatalogFixture
    Write-FixtureFile $PrefixedMutantCatalogFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_bloodsucker = 1'
    $PrefixedMutantCatalogExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PrefixedMutantCatalogFixture)
    Assert-True ($PrefixedMutantCatalogExit -ne 0) 'Static policy must reject prefixed mutant class tokens in Arena configs.'

    $PositiveOnlyDxmlFixture = New-StaticFixture 'positive-only-dxml'
    Add-Task2ContractFixture $PositiveOnlyDxmlFixture
    Write-FixtureFile $PositiveOnlyDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $PositiveOnlyDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $PositiveOnlyDxmlFixture)
    Assert-True ($PositiveOnlyDxmlExit -ne 0) 'Static policy must reject a positive-only DXML duplicate query.'

    $MixedDxmlFixture = New-StaticFixture 'mixed-dxml'
    Add-Task2ContractFixture $MixedDxmlFixture
    Write-FixtureFile $MixedDxmlFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert><insert>add("btn_gamma_arena")</insert></dxml>'
    $MixedDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MixedDxmlFixture)
    Assert-True ($MixedDxmlExit -ne 0) 'Static policy must reject an unsafe DXML insert even when another insert is guarded.'

    $MissingLuaDxmlGuardFixture = New-StaticFixture 'missing-lua-dxml-guard'
    Add-Task2ContractFixture $MissingLuaDxmlGuardFixture
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

    $DuplicateLuaDxmlFixture = New-StaticFixture 'duplicate-lua-dxml-button'
    Add-Task2ContractFixture $DuplicateLuaDxmlFixture
    $DuplicateDxmlPath = Join-Path $DuplicateLuaDxmlFixture 'src\gamedata\scripts\modxml_gamma_arena.script'
    $DuplicateDxmlContent = Get-Content -LiteralPath $DuplicateDxmlPath -Raw
    Write-FixtureFile $DuplicateLuaDxmlFixture 'src\gamedata\scripts\modxml_gamma_arena.script' ($DuplicateDxmlContent + "`nlocal duplicate = [[<btn name=`"btn_gamma_arena`" caption=`"st_gamma_arena_main_menu`" />]]`n")
    $DuplicateLuaDxmlExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $DuplicateLuaDxmlFixture)
    Assert-True ($DuplicateLuaDxmlExit -ne 0) 'Static policy must reject duplicate Arena button insertion definitions.'

    $NilWriteFixture = New-StaticFixture 'nil-write'
    Add-Task2ContractFixture $NilWriteFixture
    $NilWritePath = Join-Path $NilWriteFixture 'src\gamedata\scripts\gamma_arena_session_store.script'
    $NilWriteContent = Get-Content -LiteralPath $NilWritePath -Raw
    Write-FixtureFile $NilWriteFixture 'src\gamedata\scripts\gamma_arena_session_store.script' ($NilWriteContent + "`nlocal function bad(config) config:w_value(`"gamma_arena`", `"launch_pending`", nil) end`n")
    $NilWriteExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $NilWriteFixture)
    Assert-True ($NilWriteExit -ne 0) 'Static policy must reject w_value(..., nil) because it persists an empty string.'

    $ValidStaticFixture = New-StaticFixture 'valid-static-fixture'
    Add-Task2ContractFixture $ValidStaticFixture
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\gamma_arena_safe.script' 'local value = 4'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\scripts\nested\ga_safe.script' 'local value = 8'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\gamma_arena\arena_population.ltx' 'sim_default_stalker = 1'
    Write-FixtureFile $ValidStaticFixture 'src\gamedata\configs\ui\main_menu.xml' '<dxml><insert>if not menu:find("btn_gamma_arena") then add("btn_gamma_arena") end</insert></dxml>'
    $ValidStaticExit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $ValidStaticFixture)
    Assert-True ($ValidStaticExit -eq 0) 'Static policy must accept deterministic gamma_arena_/ga_ scripts, a human Arena config, and a guarded DXML insert.'

    $MissingTask2Fixture = New-StaticFixture 'missing-task2-contract'
    Add-Task2ContractFixture $MissingTask2Fixture
    Remove-Item -LiteralPath (Join-Path $MissingTask2Fixture 'src\gamedata\scripts\gamma_arena_rng.script') -Force
    $MissingTask2Exit = Invoke-PowerShellFile (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') @('-RepoRoot', $MissingTask2Fixture)
    Assert-True ($MissingTask2Exit -ne 0) 'Static policy must reject a missing required Task 2 contract script.'

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

Write-Host 'PASS: tool regression smoke checks passed'
