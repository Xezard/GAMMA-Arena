# FightSpec v6

FightSpecV6 is the deterministic, side-effect-free description of one Gamma
Arena fight. It stores the final generated state that runtime must apply, not
intermediate generation provenance.

| Field | Contract |
| --- | --- |
| schema_version | exactly 6 |
| generator_version | exactly 8 |
| catalog_revision | equals the normalized effective catalog revision |
| layout_version | exactly the resolved layout version |
| session_seed | normalized Park-Miller state |
| fight_index | finite non-negative integer |
| fight_id | `ga-<seed>-<index>-g8-c<catalog>-l<layout>` |
| actor | actor paths plus one validated gear-and-medicine loadout |
| opponents | ordered human participants using unique resolved physical slots |
| diagnostic | stable `FightSpecV6` text |

Every loadout contains concrete weapon, base ammunition, `ammo_boxes`, outfit,
knife, ordered medicine, `gear_cost`, `medical_cost`, and total `cost`. The
actor's value is the final `ammo_boxes` count. Runtime creates exactly that many
ordinary boxes and does not reconstruct any reserve-ammunition policy.

## Actor ordinary ammunition

The actor's equipment roll privately chooses the cataloged one-or-two-box
quantity. That quantity alone contributes to `gear_cost`; the validator
recovers it exactly as:

`(gear_cost - weapon.cost - outfit.cost) / ammo.cost`

The numerator must be non-negative and exactly divisible by `ammo.cost`, and
the result must remain inside the weapon's cataloged ammo-box range. No
intermediate ammunition count is a public FightSpec field.

The generator reads normalized `magazine_size` and the standard variant's
`box_size`. It computes a three-magazine floor in whole boxes:

`ceil(3 * magazine_size / box_size)`

For `N` opponents, scaled ordinary ammunition is one guaranteed box plus one
independent roll for each logical opponent index. The per-opponent success
rates are pistol 40%, SMG 25%, shotgun 25%, rifle 20%, and sniper 10%. Each roll
uses core/equipment RNG epoch 6 and the dedicated tag
`actor_scaled_ammo:<index>`. Indexed tags make the result prefix-stable when a
larger roster extends the same immutable generation identity.

The final actor count is:

`max(private budgeted boxes, three-magazine floor) + scaled boxes`

There is no balance ceiling. Only finite engine-integer safety is enforced.
The expected scaled range is `1..N+1`, so the final count grows without a
gameplay cap as the opponent roster grows.

The validator derives the private budgeted count from `gear_cost`, recomputes
the floor and every indexed roll from immutable FightSpec identity, and
requires exact equality with the stored final count. Forged counts, fractional
cost recovery, invalid capacities, and integer overflow fail closed.

## Unchanged ammunition contracts

Opponent ordinary `ammo_boxes` remain the original cataloged budgeted count
and remain part of opponent gear cost. Opponent firing and corpse-loot
behavior are unchanged.

Actor-only `bonus_ammo` remains a separate final one-box record with its
existing category and section streams. It is outside gear and medicine budgets
and is not part of ordinary-ammunition scaling.

`stable_encode` retains the existing loadout field order and serializes the
final actor ordinary-ammo count. A validated facade copies only final public
FightSpec values.
