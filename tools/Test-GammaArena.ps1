[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $RepoRoot 'tests\static\Test-Project.ps1') -RepoRoot $RepoRoot
exit $LASTEXITCODE
