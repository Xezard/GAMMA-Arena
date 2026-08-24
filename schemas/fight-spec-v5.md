# FightSpec v5

FightSpecV5 is the deterministic, side-effect-free description of one Gamma
Arena fight with separately budgeted equipment and combat medicine.

| Field | Contract |
| --- | --- |
| schema_version | exactly 5 |
| generator_version | exactly 7 |
| catalog_revision | exactly 7 |
| layout_version | exactly the resolved layout version |
| session_seed | normalized Park-Miller state |
| fight_index | finite non-negative integer |
| fight_id | `ga-<seed>-<index>-g7-c7-l2` |
| actor | actor paths plus one validated gear-and-medicine loadout |
| opponents | ordered human participants using unique resolved physical slots |
| diagnostic | stable `FightSpecV5` text |

Every actor and opponent loadout contains concrete weapon, base ammunition,
ammo-box count, outfit, knife, and an ordered consumable section array. It also
contains three independently validated integers:

- `gear_cost`: weapon + budgeted base ammunition + outfit;
- `medical_cost`: sum of side-specific costs for every spawned medicine;
- `cost`: exactly `gear_cost + medical_cost`.

Actor gear must fit `player_gear_budget`; medicine must fit
`player_medical_budget`. Actor medicine begins with `bandage`, contains a
`health` or `rare` entry, and obeys difficulty tier, section, category, and
five-item caps. Actor-only bonus ammunition remains outside all three costs.

For `N` opponents, each profile plus gear must fit its deterministic legacy
slot budget minus one. The enemy medical team budget is exactly `N`, pooled
across the cohort. Only `medkit` and `bandage` are legal: medkits number from
one through `ceil(N/4)`, bandages number `N - 2 * medkits`, and a participant
may hold at most one of each. Aggregate profile, gear, and medicine cost cannot
exceed the unchanged difficulty enemy total.

Core composition and equipment use core/equipment RNG epoch 6. Actor and enemy
medicine use medical RNG epoch 1 with independent category, section, mix, and
recipient tags. Medical pool or cost changes therefore cannot consume or
reroll non-medical streams.

`stable_encode` includes the complete ordered medicine list in
`medical:<section+...>` form followed by `gear_cost`, `medical_cost`, and
`cost`. Validation reconstructs every cost from normalized catalog entries and
rejects unknown sections, wrong-side medicine, forged totals, invalid caps,
invalid cohort mix, budget overflow, or ordering drift.
