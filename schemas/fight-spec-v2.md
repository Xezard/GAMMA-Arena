# FightSpec v2

FightSpecV2 is the deterministic, side-effect-free description of one Arena
fight. Generation and validation do not mutate the game world.

Compared with v1, every participant loadout has a required knife section.
The section must be one of the exact catalog revision 2 entries from
wpn_knife through wpn_knife9. Knife choice is budget-neutral and comes from
an independent tagged RNG stream: actor_knife or enemy_knife:<slot>.

The root contract is:

| Field | Contract |
| --- | --- |
| schema_version | exactly 2 |
| generator_version | exactly 2 |
| catalog_revision | exactly 2 |
| layout_version | exactly 1 |
| session_seed | normalized Park-Miller state |
| fight_index | finite non-negative integer |
| fight_id | ga-<seed>-<index>-g2-c2-l1 |
| mode_id | skirmish |
| difficulty_id | one validated difficulty |
| layout_id / level | rostok_arena_v1 / l05_bar |
| actor | t_way, t_look, and a validated loadout |
| opponents | ordered, human-only participant array |
| diagnostic | stable FightSpecV2 text |

A v2 loadout encodes, in order: firearm, compatible ammunition, reserve box
count, outfit, knife, ordered consumables, and firearm/outfit/ammo/consumable
budget cost. The knife does not change that cost.

Catalog revision 2 retains the v1 profiles, firearms, ammunition, outfits,
consumables, difficulties, and six ordered opponent paths. It adds the nine
knife sections and removes actor_boundary_zone from the closed Rostok layout.
Physical level geometry, not a per-frame teleport guard, confines the player.

stable_encode emits every field in fixed order and includes knife between
outfit and consumables. Any schema, generator, catalog, routing, budget,
firearm/ammunition, knife, or ordering mismatch returns a structured validation
error. Golden fixture changes require another explicit version advance.
