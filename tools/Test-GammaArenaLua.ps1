[CmdletBinding()]
param(
    [string]$Python = 'python',
    [string[]]$Suites = @('gamma_arena_test_domain')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

& $Python -B -m unittest discover -s (Join-Path $RepoRoot 'tests/lua') -p test_runner.py
if ($LASTEXITCODE -ne 0) { exit 1 }

& $Python -B (Join-Path $RepoRoot 'tests/lua/run_tests.py') --repo-root $RepoRoot @Suites
if ($LASTEXITCODE -ne 0) { exit 1 }
exit 0
