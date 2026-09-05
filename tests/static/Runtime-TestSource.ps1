function Get-RuntimeTestSource([string]$Path) {
    $Main = Get-Content -LiteralPath $Path -Raw
    $Sources = [ordered]@{}
    $Sources.Add('main', $Main)
    $Aliases = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $ImportPattern = '(?m)^local\s+(?<alias>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<module>gamma_arena_test_runtime_part_[A-Za-z0-9_]+)\s*$'
    foreach ($Import in [regex]::Matches($Main, $ImportPattern)) {
        $Alias = $Import.Groups['alias'].Value
        $Module = $Import.Groups['module'].Value
        if ($Aliases.ContainsKey($Alias)) { throw "Duplicate runtime module alias: $Alias" }
        $Aliases.Add($Alias, $Module)
        if (-not $Sources.Contains($Module)) {
            $PartPath = Join-Path (Split-Path -Parent $Path) ($Module + '.script')
            $Sources.Add($Module, (Get-Content -LiteralPath $PartPath -Raw))
        }
    }
    if ($Aliases.Count -eq 0) { throw 'Runtime suite must import named runtime parts.' }
    $CasePattern = '\{\s*name\s*=\s*["''](?<name>[^"'']+)["'']\s*,\s*fn\s*=\s*(?<alias>[A-Za-z_][A-Za-z0-9_]*)\.(?<function>[A-Za-z_][A-Za-z0-9_]*)\s*\}'
    $Cases = [regex]::Matches($Main, $CasePattern)
    if ($Cases.Count -eq 0 -or $Cases.Count -ne ([regex]::Matches($Main, '\bname\s*=')).Count) {
        throw 'Every runtime case must register an explicit named-module function.'
    }
    $DirectPattern = 'run_case_fn\(\s*["''](?<name>[^"'']+)["'']\s*,\s*(?<alias>[A-Za-z_][A-Za-z0-9_]*)\.(?<function>[A-Za-z_][A-Za-z0-9_]*)\s*\)'
    $DirectCases = [regex]::Matches($Main, $DirectPattern)
    $Names = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::Ordinal)
    foreach ($Case in @($Cases) + @($DirectCases)) {
        $Name = $Case.Groups['name'].Value
        $Alias = $Case.Groups['alias'].Value
        $Function = $Case.Groups['function'].Value
        if ($Name -cne $Function -and $Name -cne ('runtime_' + $Function)) {
            throw "Runtime case $Name must register its intended function, not $Alias.$Function"
        }
        if ($Names.ContainsKey($Name)) { throw "Duplicate runtime case: $Name" }
        $Names.Add($Name, $true)
        if (-not $Aliases.ContainsKey($Alias)) { throw "Runtime case $Name uses unknown module alias: $Alias" }
        $Definition = '(?m)^function\s+' + [regex]::Escape($Function) + '\s*\('
        if (([regex]::Matches($Sources[$Aliases[$Alias]], $Definition)).Count -ne 1) {
            throw "Runtime case $Name must reference one exported function: $Alias.$Function"
        }
    }
    return $Sources.Values -join "`n"
}
