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

## ArenaSession v1 checkpoint payload

`ArenaSession` is embedded only in the hidden Arena checkpoint save payload:

```lua
{
  schema_version = 1,
  session_id = string,
  session_nonce = string,
  mode_id = "skirmish",
  difficulty_id = string,
  session_seed = number,
  fight_index = number,
  generator_version = 1,
  catalog_revision = 1,
  layout_id = "rostok_arena_v1",
  checkpoint_name = "_gamma_arena_checkpoint",
  phase = string
}
```

`session_nonce` binds external resume commands to this exact session. `checkpoint_name` identifies the single reserved Arena checkpoint. The payload is valid only for the addon/schema revisions that created it.

## ResumeIntent v1

Resume intent is transient external coordination data, not part of the save:

```lua
{
  schema_version = 1,
  pending = true,
  session_id = string,
  session_nonce = string,
  next_fight_index = non-negative integer,
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

`resume_session_id` and `resume_session_nonce` must both match the checkpoint `ArenaSession`. A mismatch fails closed and consumes the invalid intent. The resume keys are deleted with one `save()` transaction, so stale values from the wrapper cache cannot be consumed twice.

## Transaction and cache rules

- Each multi-key write or removal performs exactly one `axr_main.config:save()`.
- `w_value(..., nil)` is forbidden because the wrapper writes an empty string instead of deleting the key.
- Removal uses `remove_line`.
- The store maintains process-local shadow state because `ini_file_ex:remove_line` does not invalidate the wrapper's `r_value` cache.
- Unknown, malformed, simultaneous launch/resume, future-schema, and mismatched-nonce states return structured `Result` errors.

## Character creation bridge

Starting Arena writes the neutral engine bootstrap values `difficulty=2`, `economy=2`, name `Arena_Fighter`, faction `dolg`, map `makeshift_barracks`, and money `0`. It removes `new_game_loadout` and `new_game_story_mode` with `remove_line`, then saves once. Arena difficulty affects procedural FightSpec budgets; it does not mutate global difficulty during a session.
