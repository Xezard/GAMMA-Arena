# FightSpec v8

FightSpec v8 is the immutable deterministic contract for one Gamma Arena fight generated with catalog revision 10 and generator version 10.

## Root

| Field | Contract |
|---|---|
| `schema_version` | exactly `8` |
| `generator_version` | exactly `10` for the fallback catalog, or the normalized effective v10 generator identity |
| `catalog_revision` | the normalized effective catalog revision |
| `layout_version` | exactly the resolved layout version |
| `session_seed` | normalized positive Park-Miller seed |
| `fight_index` | finite non-negative integer |
| `fight_id` | `ga-<seed>-<index>-g<generator>-c<catalog>-l<layout>` |
| `mode_id` | `skirmish` |
| `difficulty_id` | one validated difficulty ID |
| `actor` | actor participant with one device record |
| `opponents` | dense array; opponents never contain devices |

## Actor device

`actor.loadout.device` is required and has the exact shape:

```lua
{
    catalog_id = "headlamp" | "nv_gen1" | "nv_gen2" | "nv_gen3",
    section = "device_torch_dummy" | "device_torch_nv_1" | "device_torch_nv_2" | "device_torch_nv_3",
    kind = "headlamp" | "gen1" | "gen2" | "gen3",
    weight = 50 | 25 | 18 | 7,
    nv_effect = nil | "nightvision_1" | "nightvision_2" | "nightvision_3"
}
```

The record must equal both its exact catalog entry and deterministic recomputation from `{ mode_id, session_seed, fight_index, layout_version, "actor_device" }`. Difficulty is deliberately omitted. The selected device is outside every gear and medical budget.

## Stable encoding

The actor gear segment contains:

```text
,device:<catalog_id>:<section>:<kind>:<weight>:<nv_effect-or-none>
```

immediately after the grenade segment and before actor costs. The complete device identity therefore participates in replay and golden-oracle comparisons.

## Validation and copies

Validation rejects missing, malformed, unknown, altered, or non-deterministic actor devices with `GA_LOADOUT_DEVICE_INVALID`. Any device field on an opponent is rejected with the same stable code. Validated accessors deep-copy the device record so caller mutation cannot alter the stored FightSpec.
