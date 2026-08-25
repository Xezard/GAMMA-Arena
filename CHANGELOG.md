# Changelog

All notable changes to Gamma Arena are documented in this file.

## Unreleased

- Added independently configurable original Rostok Arena commentator and crowd reactions, with live MCM toggles, automatic compatibility with add-on 474's winning VFS resources, deterministic clip rotation, and fail-soft owned-channel cleanup.
- Added a localized in-game `Restart Arena` action that reuses the authoritative next-fight cleanup, advances `fight_index` once, and regenerates the fight without reloading the level.
- Quarantined only the broken actor HUD section `wpn_eft_mts_255_uh2`, preserving the base MTS-255, sibling optic variants, and NPC catalog eligibility.
- Quarantined only the confirmed actor section `wpn_dtmdr` while preserving its attachment variants and NPC eligibility; added effective HUD metadata logs plus a flushed pre-activation breadcrumb before the native weapon-animation boundary.
- Scaled the actor's ordinary ammunition for every firearm class with opponent count: one guaranteed box plus deterministic per-opponent chances (40% pistol, 25% SMG/shotgun, 20% rifle, 10% sniper), outside the gear budget and without a gameplay ceiling.
- Isolated every Arena-owned human NPC behind the engine-native `arena_enemy` community while retaining its generated source faction for presentation and loadout selection; added ownership-bounded net-spawn enforcement and activation readback without overriding any foreign mod.
- Restored the main-menu Arena Start callback by removing diagnostic level-state and file-I/O probes that are invalid before the new-game engine context exists.
- Restored the Arena Start handoff by deferring the global save-command guard until the new-game runtime accepts Arena launch ownership, while still arming suppression before any Arena activation or `fake_start` deferral.
- Suppressed every Lua `save` command and the known GAMMA new-game autosave event for Arena-owned launches while leaving campaign saves unchanged; added flushed crash checkpoints and passive bounded hit/state evidence for unexplained early NPC deaths.
- Bounded every native Gamma Arena log write and compacted routine opponent-state diagnostics to prevent CRT access violations from oversized formatted output.
- Adopted and safely released temporary ammo or magazine entities materialized under Arena opponents during combat, preventing `CLEANUP_FAILED` after unloading enemy weapons.
- Added deterministic budgeted medical loadouts for the actor and opponents, with a curated 16-item combat pool and separate gear/medical costs in FightSpec v5.
- Added physical opponent use of assigned bandages and medkits with rank-based reaction delays, bounded healing, ownership-safe consumption, and stock-AI conflict detection.
- Published catalog/difficulty identities 7/8/8 and 4/5, generated medical and actor-ammunition balance tables, and the independent FightSpec v6 golden oracle.
- Replaced native actor and inventory-owner equality with protected numeric ID checks to avoid unsupported X-Ray `game_object.__eq` calls.
- Initialized the Arena callback runtime from the main-menu preflight before the engine new-game handoff.
- Fixed actor-adapter parsing for Arena start configuration.
- Retained bootstrap diagnostics when Arena launch validation fails.
- Added fail-closed preflight for ordinary Arena starts and post-defeat rematches.
- Added ordered clean compatible-ammo discovery and deterministic actor-only weighted bonus ammo boxes.
- Added progress-aware asynchronous removal of looted actor inventory between fights.
- Added structured fail-soft diagnostic evidence for early opponent self-deaths.
- Added weighted player weapon/armor class selection with recalibrated difficulty budgets.
- Powered exoskeleton loadouts now start at 100 percent charge after verified readback.
- Arena defeats use natural actor death, then offer a fresh-fight action from the post-death menu.
- Arena-owned bots are neutralized when the actor dies.
- Reduced Master powered-exoskeleton class weight from 20% to 5% while preserving budget-bounded weighted randomness.
- Quiesced living and critically wounded Arena-owned NPCs offline before safe release to prevent cleanup races.
- Added a fatal-only emergency disconnect so terminal cleanup errors cannot trap the player or leave the main menu unusable.
- Added per-entity cleanup diagnostics and deduplicated repeated fatal display lines.

## 0.1.0 - 2026-08-21

- Initial reproducible MO2 package scaffold.
- Added versioned human-only catalogs and validated deterministic FightSpec v1 generation.
- Added a deterministic, read-only compatibility fingerprint for active MO2 profiles, executable/provider hashes, and exact release-path overlap warnings.
- Defined compatibility manifest v1 with independent add-on, state, session, FightSpec, generator, catalog, layout, and manifest versions.
- Defined forward-only durable preference migration and intentional transient launch/resume invalidation across recorded add-on version changes.
- Made the character-creation handoff crash-safe with a durable exact undo lease, fresh-process recovery, and restoration on every launch terminal route.
- Normalized GAMMA's engine-level `nil` representation of present empty INI values so durable character-creation recovery can complete.
- Canonicalized trusted X-Ray `$game_saves$` paths at the engine adapter boundary while retaining strict traversal rejection in the core checkpoint adapter.
- Fixed dotted ammunition keys in the in-game Dev generator fixture so the Lua test namespace can load.
- Reconciled add-on settings before every first activation intent inspection, including direct checkpoint loads and structured migration failure routing.
- Propagated registered NPC owner-tag read failures through deferred common fatal cleanup instead of treating them as benign deaths.
- Rejected uint32 fight-index exhaustion before victory or defeat continuation can mutate session/checkpoint state.
- Documented side-by-side MO2 installation, update, and rollback without modifying ordinary saves or merging files into Anomaly.
- Verified the static, golden-reference, smoke, package-integrity, manifest, and reproducible-build gates for the MVP release artifact.
- Recorded installed-profile, in-game Lua-suite, runtime soak, campaign-isolation, callback-order, and live compatibility-fingerprint acceptance as `DEFERRED_RUNTIME_VERIFY`; the MVP Definition of Done remains unmet until those checks pass.
