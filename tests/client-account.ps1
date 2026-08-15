[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('gtnh-client-account-' + [guid]::NewGuid().ToString('N'))))
$instance = Join-Path $temporaryRoot 'instances\GTNH'
$backup = Join-Path $instance '.gtnh-client-backups\test'

try {
    New-Item -ItemType Directory -Path $instance -Force | Out-Null
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $instance 'instance.cfg'), "name=GTNH`r`n", $utf8)
    $accountJson = @{
        formatVersion = 3
        accounts = @(@{
            profile = @{
                id = '0123456789abcdef0123456789abcdef'
                name = 'LutchS'
            }
        })
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $temporaryRoot 'accounts.json'), $accountJson, $utf8)

    $env:GTNH_SETUP_TEST_ONLY = '1'
    . (Join-Path $workspace 'setup-client.ps1') -InstancePath $instance -PrismRoot $temporaryRoot -PlayerName LutchS
    $profileId = Set-PrismAccount $instance $backup
    Set-PrismMemory $instance $backup

    $content = Get-Content -LiteralPath (Join-Path $instance 'instance.cfg') -Raw
    $original = Get-Content -LiteralPath (Join-Path $backup 'instance.cfg') -Raw
    if ($profileId -ne '0123456789abcdef0123456789abcdef') { throw 'Unexpected Prism profile ID.' }
    if ($content -notmatch '(?m)^UseAccountForInstance=true\r?$') { throw 'Prism account override was not enabled.' }
    if ($content -notmatch '(?m)^InstanceAccountId=0123456789abcdef0123456789abcdef\r?$') { throw 'Prism account ID was not written.' }
    if ($original -ne "name=GTNH`r`n") { throw 'The original Prism instance configuration was not preserved.' }

    $PlayerName = 'DifferentPlayer'
    try {
        Set-PrismAccount $instance $backup | Out-Null
        throw 'A missing Prism profile was accepted.'
    }
    catch {
        if ($_.Exception.Message -notmatch "profile named 'DifferentPlayer'") { throw }
    }

    Write-Host 'Client account configuration test passed.'
}
finally {
    Remove-Item Env:GTNH_SETUP_TEST_ONLY -ErrorAction SilentlyContinue
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('gtnh-client-account-')) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
