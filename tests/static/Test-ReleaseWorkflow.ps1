[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$WorkflowPath = Join-Path $RepoRoot '.github\workflows\release.yml'
if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    throw 'Release workflow is missing'
}
$Workflow = [IO.File]::ReadAllText($WorkflowPath)

$RequiredPatterns = @(
    '(?m)^on:\s*$',
    '(?m)^\s+push:\s*$',
    "(?m)^\s+- 'v\*\.\*\.\*'\s*$",
    '(?m)^\s+runs-on:\s*windows-latest\s*$',
    '(?m)^\s+contents:\s*write\s*$',
    'actions/checkout@v6',
    '(?m)^\s+fetch-depth:\s*0\s*$',
    '(?m)^\s+persist-credentials:\s*false\s*$',
    '(?m)^\s+shell:\s*pwsh\s*$',
    '\$PSVersionTable',
    'gh --version',
    'Get-GammaArenaReleaseNotes\.ps1',
    'Build-GammaArena\.ps1[^\r\n]+-Configuration Release',
    'Gamma-Arena-v\$env:RELEASE_VERSION-MO2\.zip',
    'gh release create',
    '--verify-tag',
    '--notes-file',
    '(?m)^\s+cancel-in-progress:\s*false\s*$'
)
foreach ($Pattern in $RequiredPatterns) {
    if ($Workflow -notmatch $Pattern) {
        throw "Release workflow contract is missing: $Pattern"
    }
}

$GitHubTokenExpression = '$' + '{{ github.token }}'
if ($Workflow -notmatch ('GH_TOKEN:\s*' + [regex]::Escape($GitHubTokenExpression))) {
    throw 'Release workflow does not authenticate GitHub CLI with github.token'
}
$ConcurrencyExpression = 'release-' + '$' + '{{ github.ref }}'
if ($Workflow -notmatch ('group:\s*' + [regex]::Escape($ConcurrencyExpression))) {
    throw 'Release workflow does not serialize work by tag ref'
}

$WritePermissions = [regex]::Matches($Workflow, '(?m)^\s+[A-Za-z-]+:\s*write\s*$')
if ($WritePermissions.Count -ne 1 -or $WritePermissions[0].Value -notmatch 'contents:\s*write') {
    throw 'Release workflow must grant only contents: write'
}
$ActionUses = [regex]::Matches($Workflow, '(?m)^\s*uses:\s*([^\s]+)\s*$')
if ($ActionUses.Count -ne 1 -or $ActionUses[0].Groups[1].Value -cne 'actions/checkout@v6') {
    throw 'Release workflow must use only the official checkout action'
}
foreach ($Forbidden in @('softprops/', 'action-gh-release', 'upload-artifact')) {
    if ($Workflow.Contains($Forbidden)) {
        throw "Release workflow uses a forbidden dependency: $Forbidden"
    }
}

$StandardSuitePath = Join-Path $RepoRoot 'tools\Test-GammaArena.ps1'
$StandardSuite = [IO.File]::ReadAllText($StandardSuitePath)
foreach ($RequiredTest in @('Test-ReleaseAutomation.ps1', 'Test-ReleaseWorkflow.ps1')) {
    if (-not $StandardSuite.Contains($RequiredTest)) {
        throw "Standard suite does not run release automation check: $RequiredTest"
    }
}
if ($StandardSuite -notmatch 'New-GammaArenaGoldenFights\.ps1''\) -Verify\r?\nif \(-not \$\?\) \{ exit 1 \}') {
    throw 'Standard suite must check the golden-reference result immediately'
}

Write-Host 'PASS: release workflow contract passed'
