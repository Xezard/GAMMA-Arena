# Gamma Arena FightSpec v9

FightSpec v9 is the sole emitted and accepted runtime fight contract. Its exact identity is FightSpec schema `9`, generator `11`, catalog schema `10`, and catalog revision `11`; the catalog fingerprint domain is `ga-catalog-v10-`. FightSpec v1-v8 have no runtime adapters, validators, schemas, or fixtures.

## Exact shape

The root contains exactly `schema_version`, `identity`, `arena`, `actor`, and `opponents`. `schema_version` is exactly `9`.

`identity` contains exactly `session_seed`, `fight_index`, `generator_version`, `catalog_schema_version`, `catalog_revision`, `catalog_fingerprint`, `layout_version`, `layout_hash`, and `fight_id`. `layout_hash` is a lower-case 16-hex hash over the complete resolved layout. `fight_id` is `ga9-` followed by the lower-case 16-hex hash of the canonical FightSpec payload excluding only `fight_id`; no separate content hash field is exposed.

`arena` contains exactly `layout_id`, `level`, and the dense `tactical_routes` array. `actor` contains exactly `spawn_path`, `look_path`, and dense `items`. Each opponent contains exactly `slot`, `faction`, `rank`, `profile`, `role`, `spawn_slot_id`, `spawn`, `tactical_route`, and dense `items`. `rank` contains exactly `id` and the exact numeric `value`. `spawn` contains exactly `position`, `level_vertex_id`, and `game_vertex_id`; `position` contains exactly `x`, `y`, and `z`.

Each item contains exactly `section`, positive integer `quantity`, and optional `equipped_slot`. Equipped slots sort `outfit`, `helmet`, `knife`, `device`, `weapon_1`, `weapon_2`; physical categories sort `outfit`, `helmet`, `knife`, `device`, `weapon`, `ammo`, `medicine`, `grenade`. Unequipped entries then sort by category and section. Duplicate ordinary sections aggregate. The actor may contain zero or one cataloged device, exactly `{section, quantity = 1, equipped_slot = "device"}`. Opponents contain no devices. Non-device sections cannot use the device slot, and device sections cannot use another slot.

## Source and runtime identity

Opponent `faction` and rank selection use the source `faction.community`, which remains the faction id. The selected profile must be the exact faction/rank intersection and numeric rank must be within both named and profile bands. Every profile separately declares `runtime_community = arena_enemy`; the effective inherited runtime profile and activated NPC must both resolve to `arena_enemy`.

## Canonical encoding and checksum

Scalars encode as `key=<decimal byte length>:<value>`. Integers use exact base-10 form, finite positions use Lua `%.17g`, arrays are dense and encoded in canonical order, and absent equipped slots encode as the empty string. The fight-ID payload excludes only `fight_id`. Its deterministic domains are `ga-fightspec-v9-a` and `ga-fightspec-v9-b`; their lower-case eight-hex values concatenate after `ga9-`.

Generation-only provenance is forbidden recursively, including mode, difficulty, budgets, prices, weights, points, threats, `custom_config`, `generation_recipe`, `generation_provenance`, `generation_rules`, and `provenance`. The strict validator checks catalog and layout identity, canonical order, participant limits including the 256-entity physical cap, item compatibility, exact ranks/profiles/spawns/routes, layout hash, fight ID, and defensive immutable accessors. It never reruns Random selection.
