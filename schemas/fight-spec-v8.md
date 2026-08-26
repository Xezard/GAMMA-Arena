# Gamma Arena FightSpec v8

FightSpec v8 is the sole published fight contract. Runtime generation uses catalog identity `9/10/10`: catalog schema 9, catalog revision 10, and generator 10. Older FightSpec versions are neither emitted nor accepted.

## Exact shape

The root contains exactly `schema_version`, `identity`, `arena`, `actor`, and `opponents`. `schema_version` is exactly `8`.

`identity` contains exactly `session_seed`, `fight_index`, `generator_version`, `catalog_fingerprint`, `layout_version`, `content_hash`, and `fight_id`. `generator_version` is exactly `10`; `catalog_fingerprint` begins with `ga-catalog-v9-`; `fight_id` is `ga8-` followed by `content_hash`.

`arena` contains exactly `layout_id`, `level`, and the dense `tactical_routes` array. `actor` contains exactly `spawn_path`, `look_path`, and dense `items`. Each opponent contains exactly `slot`, `faction`, `rank`, `profile`, `role`, `spawn_slot_id`, `spawn`, `tactical_route`, and dense `items`. `rank` contains exactly `id` and the exact numeric `value`. `spawn` contains exactly `position`, `level_vertex_id`, and `game_vertex_id`; `position` contains exactly `x`, `y`, and `z`.

Each item contains exactly `section`, positive integer `quantity`, and optional `equipped_slot`. The seven physical categories are ordered `outfit`, `helmet`, `knife`, `weapon`, `ammo`, `medicine`, `grenade`, after equipped-slot ordering. Unequipped entries then sort by category and section. Duplicate sections aggregate into one entry; in particular, duplicate actor grenade selections remain valid and become one unequipped grenade entry with quantity 2. Equipped slots are `outfit`, `helmet`, `knife`, `weapon_1`, and `weapon_2` and must be compatible with the catalog definition.

## Source and runtime identity

Opponent `faction` and rank selection use the source `faction.community`, which remains the faction id. The selected profile must be the exact faction/rank intersection and numeric rank must be within both named and profile bands. Every profile separately declares `runtime_community = arena_enemy`; the effective inherited runtime profile and activated NPC must both resolve to `arena_enemy`.

## Canonical encoding and checksum

Scalars encode as `key=<decimal byte length>:<value>`. Integers use exact base-10 form, finite positions use Lua `%.17g`, arrays are dense and encoded in canonical order, and absent equipped slots encode as the empty string. The checksum payload excludes `content_hash` and `fight_id`. Its two deterministic hash domains are `ga-fightspec-v8-a` and `ga-fightspec-v8-b`; their lower-case eight-hex-digit values concatenate into the 16-character `content_hash`.

Generation-only provenance is forbidden recursively, including `mode_id`, `difficulty_id`, budgets, prices, weights, points, threats, `custom_config`, `generation_recipe`, `generation_provenance`, `generation_rules`, and `provenance`. Runtime receives only the canonical immutable item and exact-rank contract.
