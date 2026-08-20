# Gamma Arena 0.1.0 compatibility evidence

- Evidence label: `2026-08-21`
- Release ZIP: `dist/Gamma-Arena-v0.1.0-MO2.zip`
- Release SHA-256: `5a69aab748752b67a503e31f75debc0dae98235afae05037025bc67835a9f9aa`
- Overall installed-profile status: **DEFERRED_RUNTIME_VERIFY**

## Prominent limitation

No compatibility report was produced from a real installed MO2 profile. The user explicitly deferred deployment, direct game use, and reliance on `D:\GAMMA` or `D:\Anomaly`. `D:\GAMMA` was reported deleted before Task 11; a late read-only `Test-Path -LiteralPath 'D:\GAMMA'` unexpectedly returned `True`, indicating external recreation. Task 11 did not inspect, create, deploy to, modify, launch, or rely on that directory. It did not target `D:\Anomaly` at all.

Therefore this document contains repository-local and synthetic-fixture compatibility evidence only. It is not an installed-profile fingerprint and is not an in-game PASS.

## Future installed-profile command

After the intended GAMMA profile is reinstalled and runtime verification is authorized, run this exact command from `D:\Projects\gamma-arena`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-CompatibilityReport.ps1 -AnomalyRoot D:\Anomaly -Mo2Root D:\GAMMA -Profile 'G.A.M.M.A'
```

Retain its standard output as the real compatibility fingerprint. It must include the active `modlist.txt` hash, Anomaly executable hashes, effective critical providers, exact release-path overlaps, missing-provider count, blocking-overlap count, and reviewed warning disposition. None of those installed-profile values is claimed here.

## Evidence obtained

| Check | Status | Evidence |
| --- | --- | --- |
| Compatibility reporter safety and determinism | PASS_STATIC | `tools/Test-GammaArena.ps1` exited 0. Its fixture checks require deterministic identical output, no writes to fake Anomaly/MO2 roots, later-enabled provider precedence, exact overlap reporting, rejection of missing providers, invalid names, traversal, and unsafe reparse points. |
| Real active-profile fingerprint | DEFERRED_RUNTIME_VERIFY | No real `New-CompatibilityReport.ps1` invocation was made. No real profile/provider/modlist/executable hash was collected. |
| Release path overlap with active profile | DEFERRED_RUNTIME_VERIFY | No installed profile was read. Synthetic same-path warning evidence cannot establish the live overlap set. |
| Forbidden full overrides in release | PASS_PACKAGE | Final archive inspection found none of `ui_main_menu.script`, `ui_mm_faction_select.script`, `axr_main.script`, `bind_stalker_ext.script`, `system.ltx`, or the base `npc_loadouts.ltx` override. |
| MO2-ready archive root | PASS_PACKAGE | Root contains `CHANGELOG.md`, `README.md`, `gamma-arena-manifest.json`, and `gamedata/`; all runtime content is below `gamedata/`. |
| Release/manifest integrity | PASS_PACKAGE | 35 ZIP entries are ordinal, unique, fixed-date, and safe-path. All 33 non-manifest files are represented once in ordinal manifest order and every SHA-256 matches packaged bytes. Manifest keys, version values, UTF-8/no-BOM/LF rules, and checksum sidecar were verified. |
| Dev material exclusion | PASS_PACKAGE | Archive scan found 0 Dev, test, tool, or `gamma_arena_test` entries. |
| Byte reproducibility | PASS_PACKAGE | Two final Release builds independently produced `5a69aab748752b67a503e31f75debc0dae98235afae05037025bc67835a9f9aa`. |
| Installed menu/provider coexistence | DEFERRED_RUNTIME_VERIFY | DXML/DLTX adapters and absence of forbidden overrides are static support only; live MCM/menu coexistence and callback order were not exercised. |
| Update against installed add-on | DEFERRED_RUNTIME_VERIFY | Static migration contracts say durable compatible preferences migrate while transient intent is cleared on version change. No side-by-side MO2 update or real save was exercised. |

## Compatibility boundaries reviewed

- MVP implements Skirmish only. Survival and waves are not implemented.
- A case-insensitive source scan found no `mutant` or `wave` token. The sole `survival` source occurrence removes the stock `new_game_survival_mode` character-creation key before Arena launch; it is cleanup, not Survival implementation.
- The runtime composition injects a `mode_policy` and ships only `gamma_arena_mode_skirmish.script`, preserving a future `ModePolicy` seam without unused Survival code.
- Mutants are absent from catalogs and code paths; human profile validation remains fail-closed. Installed effective-section validation is still runtime-deferred.
- Active fights are incompatible across add-on upgrades or rollback. Only compatible durable Arena preferences are migrated; transient launch/resume state, FightSpec, session, and checkpoint continuity are not promised.
- `git ls-files src` reports 32 tracked source files and no tracked absolute paths. All project source remains under `D:\Projects\gamma-arena`; no source is maintained in an installed game tree.

## Required follow-up

Run the future command above, review every warning/overlap, then run the complete in-game Lua suite and the Task 11 runtime acceptance/soak/failure-injection matrix. Until those produce passing evidence, installed compatibility remains **DEFERRED_RUNTIME_VERIFY** and the MVP Definition of Done is not met.
