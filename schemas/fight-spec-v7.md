# FightSpec v7

FightSpecV7 is the deterministic, side-effect-free description of one Gamma
Arena fight. It stores final runtime inventory, including rare physical hand
grenades, without generation provenance or item prices.

| Field | Contract |
| --- | --- |
| schema_version | exactly 7 |
| generator_version | exactly 9 |
| catalog_revision | equals the normalized effective catalog revision |
| layout_version | exactly the resolved layout version |
| session_seed | normalized Park-Miller state |
| fight_index | finite non-negative integer |
| fight_id | `ga-<seed>-<index>-g9-c<catalog>-l<layout>` |
| actor | actor paths plus one validated gear, medicine, ammunition, and grenade loadout |
| opponents | ordered human participants using unique resolved physical slots |
| diagnostic | stable `FightSpecV7` text |

Every loadout retains the FightSpecV6 weapon, base ammunition, final
`ammo_boxes`, outfit, knife, ordered medicine, `gear_cost`, `medical_cost`, and
total `cost` fields. It additionally contains `grenades`, a required dense,
ordered array of concrete game section names. Grenades never contribute to
`gear_cost`, `medical_cost`, `cost`, participant `total_cost`, or any budget.

## Grenade generation

The actor count draw is uniform over 1..100. Draw 1 produces two grenades,
draws 2..6 produce one, and draws 7..100 produce none: exactly 1%, 5%, and 94%.
Actor selections are independent uniform picks from `grenade_f1`,
`grenade_rgd5`, and `grenade_gd-05`; duplicate two-grenade selections are
valid. `grenade_smoke` is excluded from every participant pool.

Each logical opponent independently receives one grenade on draws 1..10 and
none on draws 11..100: exactly 10% and 90%. Opponent picks are uniform across
the same three-section pool.

Generation uses core/equipment RNG epoch 6 and isolated tags:

- `actor_grenade_count`
- `actor_grenade_section:1`
- `actor_grenade_section:2`
- `enemy_grenade_presence:<slot>`
- `enemy_grenade_section:<slot>`

Indexed opponent tags preserve every existing slot result when a roster is
extended. The validator derives those streams again from immutable FightSpec
identity and requires exact array length, order, and section equality. Missing,
sparse, over-cap, out-of-pool, and forged arrays fail closed with
`GA_LOADOUT_GRENADE_INVALID`.

## Runtime semantics

Each array entry becomes one ordinary physical inventory item owned by the
actor or the corresponding NPC. Runtime does not force a throw, change grenade
cooldowns, call `can_throw_grenades`, or schedule AI actions. NPC use remains
the native engine decision and therefore still requires possession plus the
engine's distance, visibility, trajectory, group-permission, and cooldown
conditions.

`stable_encode` appends `grenades:<section+section>` immediately after the
medicine field. Empty arrays encode as `grenades:`. The validated facade copies
only final public FightSpec values.
