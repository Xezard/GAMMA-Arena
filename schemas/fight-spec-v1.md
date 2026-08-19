# FightSpec v1

`FightSpecV1` is the deterministic, side-effect-free input to the later transactional spawn adapter. Generation and validation perform no spawn, inventory, teleport, or other game mutation.

| Field | Type | Invariant |
| --- | --- | --- |
| `schema_version` | integer | exactly `1` |
| `generator_version` / `catalog_revision` / `layout_version` | integer | match the loaded catalog snapshot |
| `session_seed` | integer | normalized RNG seed in `1..2147483646` |
| `fight_index` | integer | non-negative generation index |
| `fight_id` | string | exactly recomputed as `ga-<session_seed>-<fight_index>-g<generator_version>-c<catalog_revision>-l<layout_version>` |
| `mode_id` | string | `skirmish` for MVP |
| `difficulty_id`, `layout_id`, `level` | string | present in catalog and layout |
| `actor` | table | configured actor paths and a budget-valid loadout |
| `opponents` | ordered array | human-only profiles, unique spawn paths, within envelope and budget |
| `loadout` | table | weapon, matching ammo, box count, outfit, consumables, exact cost |
| `diagnostic` | string | stable, non-random diagnostic text |

The catalog is versioned by `schema_version=1`, `revision=1`, and `generator_version=1`. Revision 1 is an exact semantic manifest: profiles are `novice`, `trainee`, `experienced`, and `veteran`; weapons are `pm`, `mp5`, `ak74u`, `ak74`, and `wincheaster1300`; ammo is `ammo_9x18_fmj`, `ammo_9x19_fmj`, `ammo_5.45x39_fmj`, and `ammo_12x70_buck`; outfits are `novice`, `stalker`, and `banditmerc`; consumables are `bandage` and `medkit`. Their section mappings, costs, and weapon ammo/ranges are immutable at revision 1. Added, removed, substituted, or semantically changed entries require a new catalog revision.

NPC profiles are only the four `gamma_arena_bandit_*` sections. The validator rechecks all item sections through the normalized catalog, all costs, ammo compatibility, count/capacity, unique spawn paths, and the exact binding between `session_seed`, `fight_index`, version fields, and `fight_id`. On success it returns an accessor-only view (`session_seed`, `fight_index`, `fight_id`, `actor`, `opponents`, `stable_encode`) which retains the validated source privately.

Catalog, difficulty, and layout metadata must all declare schema/revision `1`.
The loader enumerates every LTX section and key and rejects undeclared additions,
duplicates, empty ids, non-human profiles, incompatible weapon/ammo pairs, missing
game sections, and infeasible budgets. Factory and INI enumeration exceptions are
converted to structured `GA_CATALOG_*` errors.

Validation is total for arbitrary Lua values: malformed nested tables return a
structured Result rather than throwing. It enforces `mode_id=skirmish`, known
difficulty/layout, exact level/layout version, normalized seed, non-negative fight
index, recomputed fight identity, dense
opponent and consumable arrays, `opponent.slot == array index`, non-empty unique
layout paths, and typed loadout fields before cost or compatibility checks.

`stable_encode` emits the complete fixed v1 schema in this field order: schema/version fields, `session_seed`, `fight_index`, `fight_id`, routing fields, actor, indexed opponents, then diagnostic. A loadout is encoded as weapon, ammo, ammo-box count, outfit, ordered consumables, and cost; opponents are indexed in their stable array order. It never serializes table addresses or iterates an unordered map. The fixture records four complete encodings; Lua equality is exercised by the dev suite only when GAMMA is available. After this v1 contract is released, golden fixture changes require a generator version or catalog revision increment and a matching changelog entry.
