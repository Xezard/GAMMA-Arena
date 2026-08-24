# Changelog

All notable changes to Gamma Arena are documented in this file.

## Unreleased

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
