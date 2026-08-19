# FightSpec v1

`FightSpecV1` is the deterministic, side-effect-free input to the later transactional spawn adapter. Generation and validation perform no spawn, inventory, teleport, or other game mutation.

| Field | Type | Invariant |
| --- | --- | --- |
| `schema_version` | integer | exactly `1` |
| `generator_version` / `catalog_revision` / `layout_version` | integer | match the loaded catalog snapshot |
| `fight_id` | string | `ga-<normalized-seed>-<index>-g1-c1-l1` |
| `mode_id` | string | `skirmish` for MVP |
| `difficulty_id`, `layout_id`, `level` | string | present in catalog and layout |
| `actor` | table | configured actor paths and a budget-valid loadout |
| `opponents` | ordered array | human-only profiles, unique spawn paths, within envelope and budget |
| `loadout` | table | weapon, matching ammo, box count, outfit, consumables, exact cost |
| `diagnostic` | string | stable, non-random diagnostic text |

The catalog is versioned by `schema_version=1`, `revision=1`, and `generator_version=1`. NPC profiles are only the four `gamma_arena_bandit_*` sections. The validator rechecks all item sections through the normalized catalog, all costs, ammo compatibility, count/capacity, unique spawn paths, and fight-id grammar. On success it returns an accessor-only view (`fight_id`, `actor`, `opponents`, `stable_encode`) which retains the validated source privately.

`stable_encode` emits the complete fixed v1 schema in this lexical field order: schema/version fields, identity and routing fields, actor, indexed opponents, then diagnostic. A loadout is encoded as weapon, ammo, ammo-box count, outfit, ordered consumables, and cost; opponents are indexed in their stable array order. It never serializes table addresses or iterates an unordered map. The fixture records four complete encodings; Lua equality is exercised by the dev suite only when GAMMA is available. Golden fixture changes require a generator version or catalog revision increment and a matching changelog entry.
