[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
    throw "Log file does not exist: $LogPath"
}

$Lines = @(Get-Content -LiteralPath $LogPath)
$RunMarkerPattern = '^\[GammaArenaTest\]\s+(START|BEGIN|RUN)\b'
$RunIndexes = @()
for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    if ($Lines[$Index] -match $RunMarkerPattern) {
        $RunIndexes += $Index
    }
}

if ($RunIndexes.Count -eq 0) {
    throw 'No Gamma Arena test-run marker was found.'
}

$LastRunIndex = $RunIndexes[$RunIndexes.Count - 1]
$RunLines = @($Lines[$LastRunIndex..($Lines.Count - 1)])
if (-not ($RunLines -contains '[GammaArenaTest] ALL PASS')) {
    throw 'The final Gamma Arena test run has no [GammaArenaTest] ALL PASS marker.'
}

foreach ($Line in $RunLines) {
    if ($Line -match '\[GammaArenaTest\]\s+FAIL' -or $Line -match '\[error\]\s+\[GammaArena\]') {
        throw "Gamma Arena game test failure: $Line"
    }
}

Write-Host 'PASS: Gamma Arena game tests completed successfully'
