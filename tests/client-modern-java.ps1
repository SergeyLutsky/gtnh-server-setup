[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('gtnh-client-modern-java-' + [guid]::NewGuid().ToString('N'))))
$instance = Join-Path $temporaryRoot 'GTNH'
$minecraft = Join-Path $instance 'minecraft'
$utf8 = New-Object Text.UTF8Encoding($false)

try {
    New-Item -ItemType Directory -Path (Join-Path $minecraft 'config\txloader\load\mainmenu') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $minecraft 'mods') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $minecraft 'config\txloader\load\mainmenu\version.txt'), 'GTNH 2.8.4 (test)', $utf8)
    [IO.File]::WriteAllText((Join-Path $instance 'instance.cfg'), "OverrideJavaLocation=true`r`nJavaVersion=1.8.0_51`r`n", $utf8)
    [IO.File]::WriteAllText((Join-Path $instance 'mmc-pack.json'), '{"formatVersion":1,"components":[{"uid":"org.lwjgl"}]}', $utf8)

    $env:GTNH_SETUP_TEST_ONLY = '1'
    . (Join-Path $workspace 'setup-client.ps1') -InstancePath $instance

    try {
        Assert-GtnhInstance $instance
        throw 'A legacy Java 8/LWJGL2 instance was accepted.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'legacy Java 8/LWJGL2') { throw }
    }

    $modernManifest = @{
        formatVersion = 1
        components = @(
            @{ uid = 'org.lwjgl3' },
            @{ uid = 'me.eigenraven.lwjgl3ify.forgepatches' },
            @{ uid = 'me.eigenraven.lwjgl3ify.launchargs' }
        )
    } | ConvertTo-Json -Depth 4 -Compress
    [IO.File]::WriteAllText((Join-Path $instance 'mmc-pack.json'), $modernManifest, $utf8)
    [IO.File]::WriteAllText((Join-Path $minecraft 'mods\lwjgl3ify-2.1.16.jar'), 'test', $utf8)

    try {
        Assert-GtnhInstance $instance
        throw 'A modern component manifest with an explicit Java 8 override was accepted.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'overrides Java with a legacy runtime') { throw }
    }

    [IO.File]::WriteAllText((Join-Path $instance 'instance.cfg'), "OverrideJavaLocation=true`r`nJavaVersion=21.0.3`r`n", $utf8)
    Assert-GtnhInstance $instance
    Write-Host 'Client modern Java guard test passed.'
}
finally {
    Remove-Item Env:GTNH_SETUP_TEST_ONLY -ErrorAction SilentlyContinue
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('gtnh-client-modern-java-')) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
