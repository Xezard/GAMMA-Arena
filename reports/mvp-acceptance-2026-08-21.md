# Gamma Arena MVP 0.1.0 acceptance report

- Evidence label: `2026-08-21`
- Repository: `D:\Projects\gamma-arena`
- Reviewed commit before release metadata: `6facf58f995692c544ea1dcfcd93d716425656d9`
- Release ZIP: `dist/Gamma-Arena-v0.1.0-MO2.zip`
- Release SHA-256: `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084`
- Checksum line: `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084  Gamma-Arena-v0.1.0-MO2.zip`
- Overall status: **DONE_WITH_CONCERNS**
- Design-spec Definition of Done: **NOT MET**

## Prominent acceptance limitation

The user authorized repository-local/static/build/archive/report work but explicitly deferred deployment and direct game use. No installed-profile test, game launch, Lua-suite log, real soak, campaign-save comparison, live callback-order observation, or real compatibility fingerprint was produced. Every criterion that needs such evidence is `DEFERRED_RUNTIME_VERIFY`, never PASS. Static and fake-port contracts are cited only as supporting evidence and are not substitutes for installed runtime acceptance.

`D:\GAMMA` was reported deliberately deleted before Task 11. A late read-only existence probe unexpectedly returned `True`, indicating external recreation during the task; Task 11 did not inspect, create, deploy to, modify, launch, or rely on it. No command targeted `D:\Anomaly`.

Status meanings:

- `PASS_STATIC`: freshly executed repository-local static/oracle/smoke evidence satisfies only the stated non-runtime criterion.
- `PASS_PACKAGE`: freshly inspected final ZIP/checksum bytes satisfy only the stated package criterion.
- `DEFERRED_RUNTIME_VERIFY`: the required installed-profile/game evidence does not exist; supporting static evidence does not change this status.

## Fresh command evidence

| Command | Exit | Key output / result |
| --- | ---: | --- |
| `git status --short` | 0 | Before release-report edits, the committed source/test tree was clean apart from user-owned untracked `gamma-arena-plan.md`; it was not touched or staged. |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GammaArena.ps1` | 0 | `PASS: static project checks passed`; `PASS: golden reference oracle matches fixture`; informational direct-file-symlink fixture unavailability remained statically covered. |
| `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke\Test-Regression.ps1` | 0 | `PASS: golden reference oracle matches fixture`; `PASS: tool regression smoke checks passed`. |
| First final `Build-GammaArena.ps1 -Configuration Release` | 0 | Static/oracle PASS; built ZIP; SHA-256 `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084`. |
| Second final `Build-GammaArena.ps1 -Configuration Release` | 0 | Static/oracle PASS; built ZIP; identical SHA-256 `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084`. |
| Final archive/manifest verifier | 0 | 35 safe ordinal unique fixed-date entries; MO2-ready root; 33/33 manifest file records and hashes match; exact key order/version values/encoding verified; 0 Dev entries; 0 forbidden overrides. |
| Checksum generation and verification | 0 | ASCII sidecar names the ZIP and matches its exact bytes; ZIP was not changed. |

## Final-review defect closure

The four final-review findings are closed by commit `6facf58f995692c544ea1dcfcd93d716425656d9` with repository-local behavioural coverage:

- The launch bridge now persists an exact durable lease before mutating all 21 `character_creation` keys and restores value/presence exactly through success, false/throwing/missing `StartGame`, rejection, expiration, stale issue cleanup, migrations, and injected backend faults. Fresh-store recovery and idempotent no-lease behavior are covered.
- Activation now reconciles migrations before inspecting intents. Upgrade, rollback, future-schema, pending-layout, and migration-failure cases are fail-closed through common cleanup.
- NPC owner-tag read failures now propagate through the real callback router into one deferred fatal transition and cleanup; only a successful ownership mismatch remains benign.
- Victory and defeat compute the next uint32 fight index before observable mutation. `0xFFFFFFFE` advances once to `0xFFFFFFFF`; exhaustion returns stable `GA_FIGHT_INDEX_EXHAUSTED` without changing session, checkpoint, actor, or result-latch state.

These are `PASS_STATIC`/synthetic-runtime results only. They do not change any installed-profile or in-game row from `DEFERRED_RUNTIME_VERIFY`.

## Task 11 acceptance matrix

Every row records the authoritative final build hash, even where runtime verification is deferred.

| Scenario | Status | Evidence / missing evidence | Build SHA-256 |
| --- | --- | --- | --- |
| Main-menu integration | DEFERRED_RUNTIME_VERIFY | Static DXML adapter and forbidden-override checks support one namespaced entry, but one live button and unaffected New Game/MCM were not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Random seed | DEFERRED_RUNTIME_VERIFY | Static uint32 validation exists; a displayed random seed and successful real session start were not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Manual seed | PASS_STATIC | Fresh golden reference oracle proves stable FightSpec v1 encoding for fixed seed/difficulty/index/version inputs. This does not prove engine application. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Four difficulties | PASS_STATIC | Static project validation plus the golden oracle cover all four versioned difficulty manifests and configured generator envelopes. No live spawn budget was observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Human-only rule | DEFERRED_RUNTIME_VERIFY | Source/catalog scan found no mutant path and static validators reject non-human profiles, but the required pure in-game 100-fight run was not executed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Full reroll | DEFERRED_RUNTIME_VERIFY | Fake-port contracts regenerate actor/opponent specs; real consecutive fights and inventories were not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Victory next | DEFERRED_RUNTIME_VERIFY | Fake-port orchestration covers cleanup/heal/index increment/new spec without load; live callback/effect order was not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Defeat screen | DEFERRED_RUNTIME_VERIFY | CP1251 source decoding confirms the exact text `Вы погибли` and both required localization labels, but the actual screen/buttons were not displayed in game. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Defeat next | DEFERRED_RUNTIME_VERIFY | Fake-port contracts cover hidden checkpoint intent/index progression and no lost-spec replay; real save/load callback order was not exercised. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Main-menu exit | DEFERRED_RUNTIME_VERIFY | Exact cleanup is fail-closed in fake ports; real registry/intent/checkpoint absence after disconnect was not inspected. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Campaign isolation | DEFERRED_RUNTIME_VERIFY | No Arena source writes directly to Anomaly, but existing save hashes and stock death behavior require a real campaign and were not tested. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Update test | DEFERRED_RUNTIME_VERIFY | v0/v1 fixtures and migration/fake-store contracts are present and statically checked; the complete Lua suite and a real side-by-side update were not run. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| Conflict check | DEFERRED_RUNTIME_VERIFY | PASS_PACKAGE supporting result: no forbidden archive override. The exact live overlap/provider fingerprint was not produced or reviewed because the installed profile was out of scope. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |

Task 11 matrix accounting: **2 PASS_STATIC, 0 complete installed-runtime PASS, 11 DEFERRED_RUNTIME_VERIFY**.

## Design-spec section 16 acceptance criteria

| # | Criterion | Status | Evidence / missing evidence | Build SHA-256 |
| ---: | --- | --- | --- | --- |
| 1 | Separate working `ARENA` button in the main menu | DEFERRED_RUNTIME_VERIFY | Namespaced DXML integration is statically checked; working live menu integration was not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 2 | Launch screen has difficulty, random/manual seed, and `START` | DEFERRED_RUNTIME_VERIFY | XML/localization/controllers are packaged; real rendering and interaction were not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 3 | Isolated temporary session on Rostok | DEFERRED_RUNTIME_VERIFY | Fake-port session contracts exist; no engine session was created. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 4 | Sequential fights generate only humans and new equipment | DEFERRED_RUNTIME_VERIFY | Human-only catalogs/full-reroll contracts are static support; no live sequence was run. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 5 | Same inputs/data versions produce same `FightSpec` | PASS_STATIC | Fresh independent PowerShell golden oracle matched the checked-in FightSpec v1 fixture; Release build reran it twice. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 6 | Victory is determined only by owned `FightRegistry` | DEFERRED_RUNTIME_VERIFY | Registry ownership contracts are statically/fake-port checked; live death callbacks and foreign NPCs were not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 7 | Death shows exact `Вы погибли` and both required buttons | DEFERRED_RUNTIME_VERIFY | Exact Russian source text was decoded and verified without copying console mojibake; real UI display was not observed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 8 | Death-next loads clean checkpoint and creates a new fight | DEFERRED_RUNTIME_VERIFY | Fake filesystem/orchestrator contracts support the flow; real checkpoint/save callback order was not run. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 9 | At least 20 fights leave no stale Arena entities/items | DEFERRED_RUNTIME_VERIFY | Synthetic 100-fight contract exists but was not executed in the game; no real soak evidence exists. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 10 | Ordinary GAMMA start/save/load never activates Arena | DEFERRED_RUNTIME_VERIFY | Intent gating is statically/fake-port checked; no real campaign was launched or hashed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 11 | Preparation failures leave no partial fight and preserve menu | DEFERRED_RUNTIME_VERIFY | Fail-closed rollback contracts exist; real missing catalog/patrol/spawn/checkpoint/intent failures were not injected. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 12 | ZIP installs via MO2 and writes nothing directly to `D:\Anomaly` | DEFERRED_RUNTIME_VERIFY | PASS_PACKAGE supporting result: MO2-ready root and no absolute paths/direct installer. Actual MO2 installation was not performed. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 13 | Side-by-side MO2 update preserves compatible Arena settings and ordinary saves | DEFERRED_RUNTIME_VERIFY | Migration/static contracts exist and active fights are intentionally incompatible across upgrades; real update/save hashes were not tested. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |
| 14 | Unit, property, static, and mandatory integration checks all pass | DEFERRED_RUNTIME_VERIFY | Static/oracle/smoke pass; mandatory installed integration checks were not run. | `d325b91883fcdc9ed148d24945a9e3d7dd2e6f1bcbf6e0d0e7eefdf126b9d084` |

Design-spec criteria accounting: **1 PASS_STATIC, 13 DEFERRED_RUNTIME_VERIFY**. Because acceptance requires all 14 simultaneously, the MVP is not accepted.

## Soak and failure-injection accounting

| Required run | Status | Missing evidence |
| --- | --- | --- |
| 100 pure in-game generator fights per difficulty (400 total) | DEFERRED_RUNTIME_VERIFY | Complete in-game Lua suite was not launched. The checked-in 10,000-seed Lua case is source/future-suite coverage, not executed evidence. |
| 50 accelerated runtime fights alternating victory/logical defeat | DEFERRED_RUNTIME_VERIFY | No game launch or runtime soak. |
| Missing catalog item | DEFERRED_RUNTIME_VERIFY | Static/fake-port failure paths exist; no installed failure injection. |
| Missing patrol | DEFERRED_RUNTIME_VERIFY | Static/fake-port preflight exists; no installed failure injection. |
| NPC spawn failure | DEFERRED_RUNTIME_VERIFY | Transactional rollback contracts exist; no installed failure injection. |
| Checkpoint timeout | DEFERRED_RUNTIME_VERIFY | Bounded fake-filesystem contracts exist; no installed timeout observation. |
| Mismatched `ResumeIntent` | DEFERRED_RUNTIME_VERIFY | Store/orchestrator contracts exist; no installed reload observation. |
| Per-failure owned-only cleanup, input restoration, campaign load | DEFERRED_RUNTIME_VERIFY | Requires live entities, input, checkpoint files, and campaign save evidence. |

## Final package review

- Two final Release builds are byte-identical.
- Checksum sidecar was generated after the final build and did not modify ZIP bytes.
- Archive root/layout is MO2-ready; entry names are safe, ordinal, unique, and fixed-date.
- Manifest root property order and values are exact: add-on `0.1.0`; state/session/FightSpec/generator/catalog/layout/compatibility-manifest versions all `1`.
- All 33 non-manifest file hashes match, and the manifest neither omits nor adds a packaged file.
- No Dev/test/tool content and no forbidden core override is packaged.
- The exact Russian defeat text is `Вы погибли` in the CP1251 localization source; no mojibake was copied into tracked release evidence.

## Scope and architectural confirmations

- Survival and waves are not implemented in MVP.
- Mutants are absent from data and code paths. A source scan found no `mutant` or `wave` token; effective installed profile validation is still deferred.
- The only source `survival` occurrence removes GAMMA's stock `new_game_survival_mode` bootstrap key. It is not Arena Survival code.
- `mode_policy` is an injected orchestration dependency and the only shipped policy is `gamma_arena_mode_skirmish.script`: the future `ModePolicy` seam exists without unused Survival implementation.
- Active fights are incompatible across add-on upgrades or rollback; compatible durable preferences may migrate, but transient launch/resume/session/FightSpec/checkpoint continuity is intentionally cleared/not promised.
- `git ls-files src` reports 32 tracked source files beneath `D:\Projects\gamma-arena\src`, with zero tracked absolute paths. All source remains under `D:\Projects\gamma-arena`.
- `dist/` is ignored by repository policy. The ZIP/checksum exist locally but are not force-added.

## Required runtime follow-up

Once deployment and game use are authorized, generate the real compatibility fingerprint using the exact command in `reports/compatibility-2026-08-21.md`, explicitly deploy Dev, run/parse the complete Lua suite, execute every matrix row and soak/failure case, record campaign save hashes and callback order, and rebuild only if runtime findings require code changes. The current report must not be relabeled PASS without that evidence.
