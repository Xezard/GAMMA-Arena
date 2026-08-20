# Changelog

All notable changes to Gamma Arena are documented in this file.

## 0.1.0 - 2026-08-21

- Initial reproducible MO2 package scaffold.
- Added versioned human-only catalogs and validated deterministic FightSpec v1 generation.
- Added a deterministic, read-only compatibility fingerprint for active MO2 profiles, executable/provider hashes, and exact release-path overlap warnings.
- Defined compatibility manifest v1 with independent add-on, state, session, FightSpec, generator, catalog, layout, and manifest versions.
- Defined forward-only durable preference migration and intentional transient launch/resume invalidation across recorded add-on version changes.
- Documented side-by-side MO2 installation, update, and rollback without modifying ordinary saves or merging files into Anomaly.
- Verified the static, golden-reference, smoke, package-integrity, manifest, and reproducible-build gates for the MVP release artifact.
- Recorded installed-profile, in-game Lua-suite, runtime soak, campaign-isolation, callback-order, and live compatibility-fingerprint acceptance as `DEFERRED_RUNTIME_VERIFY`; the MVP Definition of Done remains unmet until those checks pass.
