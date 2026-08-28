# Gamma Arena

> A deterministic, replayable combat arena for S.T.A.L.K.E.R. Anomaly G.A.M.M.A., distributed as an independent Mod Organizer 2 add-on.

Gamma Arena turns the classic Rostok Arena into a self-contained combat mode with seeded fights, generated equipment, four difficulty levels, and explicit round cleanup.

<!--
## Screenshots

Store the images in `.github/assets/`, then remove this HTML comment.

| Arena setup | Fight HUD | Results |
|:---:|:---:|:---:|
| ![Arena setup](.github/assets/arena-setup.webp) | ![Fight HUD](.github/assets/fight-hud.webp) | ![Results](.github/assets/results.webp) |
-->

## Features

- Seeded, deterministic fight generation.
- Four difficulty levels: Rookie, Stalker, Veteran, and Master.
- Profile-aware catalogs and generated weapons, armor, ammunition, medical supplies, grenades, and lighting devices.
- Arena-specific opponent setup, tactical behavior, medical use.
- Optional original Rostok Arena commentator and crowd reactions through MCM.
- English and Russian localization.

## Requirements

- A working S.T.A.L.K.E.R. Anomaly installation configured through G.A.M.M.A.
- Mod Organizer 2 and an existing G.A.M.M.A. profile.

Gamma Arena is not a standalone game or a replacement for G.A.M.M.A.

## Download and installation

1. Open the [latest release](https://github.com/Xezard/GAMMA-Arena/releases/latest).
2. Download the attached `Gamma-Arena-vX.Y.Z-MO2.zip` package. Do not use GitHub's automatically generated source archive as the mod package.
3. In Mod Organizer 2, select **Install a new mod from an archive** and choose the downloaded ZIP.
4. Install it as a separate mod named **Gamma Arena**.
5. Enable **Gamma Arena** in the `G.A.M.M.A.` profile and launch the game through MO2.

> [!IMPORTANT]
> Never extract or merge the package directly into the Anomaly or G.A.M.M.A. installation. Keeping it as an independent MO2 entry makes updates, conflict review, rollback, and removal predictable.

### Updating and rolling back

Install updates through MO2 and replace only the **Gamma Arena** entry. Keep the previous release archive, or retain the previous MO2 entry while validating the update, so rollback remains a simple enable/disable operation.

## Using the Arena

1. Launch G.A.M.M.A. through MO2.
2. Select **Arena** in the main menu, directly after **New Game**.
3. Choose a difficulty and start the session.
4. Complete the fight and use the result screen to continue. The battle HUD shows the active seed and fight number.
5. Use **Restart Arena** in the pause menu to discard the current fight and generate the next one without reloading the level.

The **Gamma Arena** MCM page controls the original Rostok commentator and crowd reactions. Both options are enabled by default and can be changed while the game is running.

## Compatibility

Gamma Arena is packaged as an additive `gamedata` tree and the static suite rejects base-game overrides. That does not guarantee compatibility with every possible mod list: another add-on may still provide the same relative path or alter a runtime provider used by the Arena.

Review same-path conflicts in MO2 instead of treating either side as an automatic overwrite winner. Maintainers and advanced users can generate a read-only compatibility report for an existing profile from the repository tooling described under [Development](#development).

## Troubleshooting and bug reports

If the Arena entry is missing or a fight fails to start:

- confirm that **Gamma Arena** is enabled in the active G.A.M.M.A. MO2 profile;
- launch the game through that profile rather than directly from the Anomaly executable;
- review MO2 conflicts involving main-menu, Arena, or script files;
- reproduce the problem once and keep the newest `Anomaly/appdata/logs/xray_*.log` file.

Open a [GitHub issue](https://github.com/Xezard/GAMMA-Arena/issues) and include:

- Gamma Arena release version;
- G.A.M.M.A., Anomaly, and Modded Exes versions;
- the active mod list and relevant MO2 conflicts;
- the Arena seed and fight number, when available;
- reproduction steps and the newest X-Ray log.

Review logs before uploading them and remove unrelated personal paths or private information.

## Development

<details>
<summary>Local checks and release build</summary>

From Windows PowerShell, enter the repository and run the complete local suite:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-GammaArena.ps1
```

Build the deterministic release package:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-GammaArena.ps1 -Configuration Release
```

The package is written to `dist\Gamma-Arena-vX.Y.Z-MO2.zip`. Its root contains `gamedata/`, `gamma-arena-manifest.json`, `README.md`, and `CHANGELOG.md`. The manifest records component versions and ordinally sorted SHA-256 file records.

</details>

<details>
<summary>Development deployment and in-game tests</summary>

Exit Anomaly before deploying, then provide the local MO2 root:

```powershell
$Mo2Root = 'C:\Games\GAMMA'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Deploy-GammaArenaDev.ps1 -Mo2Root $Mo2Root
```

The script runs the local suite, builds a Dev package from `src\gamedata` and `dev\gamedata`, and replaces only the `Gamma Arena DEV` MO2 entry. It does not edit MO2 profiles.

The packaged in-game suite is opt-in. Its production-like default is:

```ini
[gamma_arena]
dev_test_autorun = false
```

To run it once on the next G.A.M.M.A. process, set:

```ini
[gamma_arena]
dev_test_autorun = true
```

in the effective `gamedata\configs\axr_options.ltx`, launch through MO2, exercise the Arena, and then return the value to `false`.

Read the newest completed run with:

```powershell
$AnomalyRoot = 'C:\Games\Anomaly'
$LogPath = Get-ChildItem -LiteralPath (Join-Path $AnomalyRoot 'appdata\logs') -Filter 'xray_*.log' -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1 -ExpandProperty FullName
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Read-GammaArenaGameTests.ps1 -LogPath $LogPath
```

The reader succeeds only when the latest Gamma Arena run ends with `[GammaArenaTest] ALL PASS` and contains no later Arena test failure.

</details>

<details>
<summary>Compatibility report</summary>

Generate compatibility evidence for an existing profile without modifying it:

```powershell
$AnomalyRoot = 'C:\Games\Anomaly'
$Mo2Root = 'C:\Games\GAMMA'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\New-CompatibilityReport.ps1 `
    -AnomalyRoot $AnomalyRoot `
    -Mo2Root $Mo2Root `
    -Profile 'G.A.M.M.A'
```

The report is written to standard output. Exact same-path matches are review warnings, not automatic overwrite instructions.

</details>

The complete development loop is:

```text
edit -> Test-GammaArena.ps1 -> Deploy-GammaArenaDev.ps1 -> launch through MO2 -> Read-GammaArenaGameTests.ps1
```

### Repository layout

- `src/gamedata/` — release mod source.
- `dev/gamedata/` — opt-in in-game development suite.
- `tests/` — static, smoke, and deterministic reference checks.
- `tools/` — build, deployment, compatibility, and log-reading scripts.
- `schemas/` — versioned session, state, manifest, and FightSpec contracts.
- [`CHANGELOG.md`](CHANGELOG.md) — release history.
- [Arena balance dashboard](ARENA_BALANCE.md) - generated Arena balance reference.

Generated packages, build output, logs, and deployment state stay outside Git.

## Credits and disclaimer

Gamma Arena is an independent community project for S.T.A.L.K.E.R. Anomaly G.A.M.M.A. It is not affiliated with or endorsed by GSC Game World, the Anomaly developers, or the G.A.M.M.A. team. Project and product names are used only to identify compatibility.