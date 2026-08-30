[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') -RepoRoot $RepoRoot
if (-not $?) { exit 1 }
& (Join-Path $RepoRoot 'tests\static\Test-ActorDevices.ps1') -RepoRoot $RepoRoot
if (-not $?) { exit 1 }
& (Join-Path $RepoRoot 'tests\reference\New-GammaArenaGoldenFights.ps1') -Verify
if (-not $?) { exit 1 }
& (Join-Path $RepoRoot 'tests\static\Test-ReleaseAutomation.ps1') -RepoRoot $RepoRoot
if (-not $?) { exit 1 }
& (Join-Path $RepoRoot 'tests\static\Test-ReleaseWorkflow.ps1') -RepoRoot $RepoRoot
if (-not $?) { exit 1 }
exit 0
