param(
    [string]$RepositoryRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$files = @(
    'schemas/state.schema.json',
    'schemas/mod-catalogue.schema.json',
    'schemas/release-checksums.schema.json',
    'catalog/mods.json',
    'catalog/gtnh-release-checksums.json',
    'tests/fixtures/state-valid.json',
    'tests/fixtures/releases.json'
)

foreach ($relativePath in $files) {
    $path = Join-Path $RepositoryRoot $relativePath
    $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Write-Host "valid JSON: $relativePath"
}
