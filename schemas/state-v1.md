# Gamma Arena state schema v1

## Result envelope

Every recoverable Gamma Arena failure is returned as a structured value:

```lua
{ ok = true, value = value }
{ ok = false, error = { code = "GA_*", message = "...", context = {...} } }
```

`gamma_arena_result.is_ok(result)` is true only for the success shape. Invalid
state transitions use `GA_STATE_TRANSITION_INVALID`; their context contains the
unchanged `current` state and the rejected `event`.

## States

`IDLE`, `PREFLIGHT`, `CHECKPOINTING`, `PREPARING`, `COUNTDOWN`, `ACTIVE`,
`RESULT`, `RECOVERING`, `EXITING`, and `ERROR` are the complete v1 state set.

## Transition matrix

| Current state | Event | Next state |
| --- | --- | --- |
| `IDLE` | `START` | `PREFLIGHT` |
| `PREFLIGHT` | `PREFLIGHT_SUCCEEDED` | `CHECKPOINTING` |
| `PREFLIGHT` | `PREFLIGHT_FAILED` | `ERROR` |
| `PREFLIGHT` | `EXIT` | `EXITING` |
| `CHECKPOINTING` | `CHECKPOINT_SUCCEEDED` | `PREPARING` |
| `CHECKPOINTING` | `CHECKPOINT_FAILED` | `ERROR` |
| `CHECKPOINTING` | `EXIT` | `EXITING` |
| `PREPARING` | `PREPARATION_SUCCEEDED` | `COUNTDOWN` |
| `PREPARING` | `PREPARATION_FAILED` | `ERROR` |
| `PREPARING` | `EXIT` | `EXITING` |
| `COUNTDOWN` | `COUNTDOWN_FINISHED` | `ACTIVE` |
| `COUNTDOWN` | `EXIT` | `EXITING` |
| `ACTIVE` | `VICTORY` | `RESULT` |
| `ACTIVE` | `DEFEAT` | `RESULT` |
| `ACTIVE` | `EXIT` | `EXITING` |
| `RESULT` | `NEXT_AFTER_VICTORY` | `PREPARING` |
| `RESULT` | `NEXT_AFTER_DEFEAT` | `RECOVERING` |
| `RESULT` | `EXIT` | `EXITING` |
| `RECOVERING` | `CHECKPOINT_RESTORED` | `PREPARING` |
| `RECOVERING` | `CHECKPOINT_RESTORE_FAILED` | `ERROR` |
| `RECOVERING` | `EXIT` | `EXITING` |
| `EXITING` | `CLEANUP_SUCCEEDED` | `IDLE` |
| `EXITING` | `CLEANUP_FAILED` | `ERROR` |
| `ERROR` | `EXIT` | `EXITING` |

There is no implicit fallback: every matrix entry absent from this table returns
`GA_STATE_TRANSITION_INVALID` and does not mutate `current`.

## Deterministic random streams

`gamma_arena_rng.derive_seed(parts)` uses a length-delimited polynomial fold with
base `131` and modulus `2147483646`. Callers pass a complete stream key ending in
one of the stable tags `actor_loadout`, `enemy_count`, `enemy_profile`,
`enemy_loadout`, or `spawn_path`. New decisions use a new tag, so they do not
consume or perturb an existing stream.

`normalize_uint32` maps `NaN`, positive infinity, and negative infinity to the
valid Park-Miller seed `1` before any arithmetic.

## Logging context-key policy

Structured logging accepts only scalar context keys: strings, finite numbers, and
booleans. It serializes these as unambiguous type-prefixed canonical keys and sorts
them lexically. Unsupported keys (including tables, functions, userdata, threads,
and non-finite numbers) are skipped. If a canonical key would collide, its value is
replaced with the stable `<canonical-key-collision>` placeholder. This avoids
memory-address output and any dependency on the iteration order of `pairs`.
