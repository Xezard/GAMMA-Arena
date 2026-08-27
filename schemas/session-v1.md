# Gamma Arena session and settings schema v1

## Scope and lifetime

Gamma Arena has two distinct storage lifetimes:

1. Durable UI preferences in `axr_main.config` survive addon updates.
2. Launch intents, resume intents, and the `ArenaSession` checkpoint payload exist only to operate one temporary Arena session.

`FightSpec`, `FightRegistry`, and `ResumeIntent` are **non-durable** across addon upgrades. An active fight is intentionally not resumed after changing addon versions. Ordinary campaign saves are neither required nor modified.

## Durable settings

Section: `[gamma_arena]`. Schema version: `1`.

| Key | Type | v1 invariant |
| --- | --- | --- |
| `settings_schema_version` | integer | exactly `1` |
| `last_difficulty_id` | string | `rookie`, `stalker`, `veteran`, or `master` |
| `last_seed_mode` | string | `random` or `manual` |

No session seed, session identifier, token, checkpoint name, or fight state is a durable preference. An absent/v0 section migrates forward to v1. A schema newer than v1 returns `GA_SETTINGS_SCHEMA_NEWER` without writes. Reads and migrations report explicit events; invalid values are never silently corrected.

## ArenaStartRequest v1

```lua
{
  schema_version = 1,
  mode_id = "skirmish",
  difficulty_id = "rookie" | "stalker" | "veteran" | "master",
  seed_mode = "random" | "manual",
  session_seed = 0..4294967295
}
```

Manual input is an ASCII decimal uint32. Signs, whitespace, decimal points, exponent syntax, NaN, infinities, fractions, and values above `4294967295` fail closed.

## Launch intent

The following transient keys share `[gamma_arena]` but are deleted with `remove_line` in one saved transaction immediately after consumption or rejection:

```text
launch_pending
launch_token
launch_mode_id
launch_difficulty_id
launch_seed_mode
launch_session_seed
```

The token grammar is `ga1:<issued_at_epoch>:<nonce>`. `issued_at_epoch` is a non-negative decimal wall-clock epoch and `nonce` contains only ASCII word characters, `_`, or `-`. The TTL is **600** seconds, inclusive at the boundary. A token timestamp from the future is invalid.

Issuance also creates a module-local volatile permit. Consumption requires the persisted token and the volatile permit from the same Lua process. Therefore a persisted token left by a prior crashed process cannot activate Arena. A launch intent is consumed at most once.

Each `SessionStore` instance owns its own volatile permits. A same-instance duplicate is rejected only after the complete persisted token/request payload (mode, difficulty, seed mode, canonical decimal seed, timestamp, and volatile permit) is revalidated. An orphaned, malformed, expired, corrupted, or partially written intent is atomically removed and returns `GA_LAUNCH_STALE_CLEARED`; the start UI then performs exactly one fresh issuance attempt.

## ArenaSession v1 checkpoint payload

`ArenaSession` is embedded only in the hidden Arena checkpoint save payload:

```lua
{
  schema_version = 1,
  session_id = string,
  session_nonce = string,
  mode_id = "skirmish",
  generation_recipe = "random" | "custom",
  difficulty_id = string | nil,
  session_seed = number,
  fight_index = uint32,
  generator_version = 10,
  catalog_revision = 10,
  catalog_fingerprint = "ga-catalog-v9-...",
  custom_config = table | nil,
  layout_id = "rostok_arena_v1",
  checkpoint_name = "_gamma_arena_checkpoint",
  phase = string
}
```

`difficulty_id` is present only for the random recipe. `custom_config` is
present only for the custom recipe and is an immutable validated copy of the
selected shared faction, ordered exact-rank roster, actor items, and catalog
fingerprint. Both recipes produce the same strict FightSpec v8 after this
session-only provenance is consumed.

`session_nonce` binds external resume commands to this exact session. `checkpoint_name` identifies the single reserved Arena checkpoint. The payload is valid only for the addon/schema revisions that created it.

The runtime bootstrap writes this payload only while its orchestrator is active. An ordinary campaign save therefore receives no `gamma_arena_session` field. On load, an embedded payload is accepted only together with a matching `ResumeIntent`; a payload without that external route, or a resume route without a payload, fails closed and returns to the main menu. A launch route is valid only for a distinct new game with no loaded save payload, and its one-shot intent is consumed before compatibility preflight or any Arena runtime effect.

The orchestrator validates and caches a resume override but does not apply `next_fight_index` and does not consume the valid `ResumeIntent` during initial activation. Task 6 owns the hidden-checkpoint re-hide step and consumes/applies that prepared route only after re-hide succeeds. Invalid or stale routes are cleared immediately. While the orchestrator is active, manual Save and Load UI callbacks are blocked with `st_gamma_arena_manual_save_disabled`; internal checkpoint console operations are outside those UI callbacks.

## ResumeIntent v1

Resume intent is transient external coordination data, not part of the save:

```lua
{
  schema_version = 1,
  pending = true,
  session_id = string,
  session_nonce = string,
  next_fight_index = uint32,
  checkpoint_name = string
}
```

Its `[gamma_arena]` keys are:

```text
resume_pending
resume_session_id
resume_session_nonce
resume_next_fight_index
resume_checkpoint_name
resume_schema_version
```

Resume consumption validates the complete expected `ArenaSession` v1 payload: schema, identifiers, nonce, reserved checkpoint, generator/catalog revisions, layout, mode, difficulty, uint32 seed, uint32 fight index, and phase. `resume_session_id`, `resume_session_nonce`, and `resume_checkpoint_name` must match the checkpoint payload. `resume_next_fight_index` is external recovery state: it may be newer than the clean checkpoint's embedded `fight_index`, but it must not be older. The orchestrator applies that validated override only after the checkpoint is loaded and re-hidden. A mismatch or backward index fails closed and consumes the invalid intent. The resume keys are deleted with one `save()` transaction, so stale values from the wrapper cache cannot be consumed twice.

## Transaction and cache rules

- Before mutation, every touched key is snapshotted as exact presence plus raw string value via `line_exist` and `r_string_ex`.
- Persistent validity markers are written last. One-shot pending markers are removed first during consumption.
- Each successful multi-key write or removal invalidates the touched `ini_file_ex.cache` entries and performs exactly one `axr_main.config:save()`.
- A primary mutation/cache/save fault creates a touched-key recovery record. Recovery uses the raw `config.ini:w_string/remove_line` port, never replaces or reloads the whole options file, and invalidates only `cache[section .. "&" .. key]` for the touched keys.
- Recovery calls `save()` only after every raw restoration and cache invalidation succeeds. Transient intent keys recover fail-closed (removed); durable preferences and character-creation values recover to their exact presence/raw-value snapshot.
- If raw restoration or its save fails, the config is quarantined. No later Gamma Arena read/transaction is allowed through that config object until `gamma_arena_config_tx.recover(config)` succeeds or the wrapper/process is genuinely reloaded.
- `w_value(..., nil)` is forbidden because the wrapper writes an empty string instead of deleting the key.
- Removal uses `remove_line`.
- Process-local shadow state is not authoritative for pending-launch validation; persisted/raw wrapper state is read again before duplicate rejection.
- Unknown, malformed, simultaneous launch/resume, future-schema, and mismatched-nonce states return structured `Result` errors.

The adapter deliberately does not restore a whole stale copy of `axr_options.ltx`, so it does not discard unrelated in-memory changes made by other addons. Conversely, the shared wrapper's eventual `save()` can also persist unrelated changes already present in that same working object. A backend that partially writes and then throws/returns failure can make on-disk state unknowable; Gamma Arena reports that uncertainty and quarantines its own operations, but cannot provide transactional isolation for unrelated mods. These runtime details remain subject to installed-game verification.

## Character creation bridge

Starting Arena writes the neutral engine bootstrap values `difficulty=2`, `economy=2`, `economy_treasure=2`, name `Arena_Fighter`, faction `dolg`, map `makeshift_barracks`, and money `0`. In the same transaction it removes the complete stale-mode allowlist with `remove_line`: `new_game_loadout`, `new_game_story_mode`, `new_game_icon`, `new_game_hardcore_mode`, `new_game_hardcore_mode_lives`, `new_game_hardcore_mode_regenerate`, `new_game_survival_mode`, `new_game_azazel_mode`, `new_game_warfare`, `new_game_campfire_mode`, `new_game_conditions_mode`, `new_game_timer_mode`, `new_game_opened_routes`, and `new_game_test`. The 21 mutations end with exactly one save; any mutation/save failure restores the full working and persisted allowlist snapshot. Arena difficulty affects procedural FightSpec budgets; it does not mutate global difficulty during a session.
