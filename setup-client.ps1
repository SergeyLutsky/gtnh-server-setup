[CmdletBinding()]
param(
    [string]$InstancePath,
    [string]$PrismRoot,
    [string]$ServerAddress,
    [string]$ServerName = 'Private GTNH Server',
    [ValidatePattern('^[A-Za-z0-9_]{1,16}$')]
    [string]$PlayerName = 'LutchS',
    [string]$Mods = 'all',
    [ValidateRange(4096, 32768)]
    [int]$MemoryMB = 8192,
    [string]$CataloguePath,
    [string]$ClientCataloguePath,
    [switch]$SkipClientExtras,
    [switch]$SkipQuestContent,
    [switch]$SkipMemoryConfiguration
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:ExpectedVersion = '2.8.4'
$script:CatalogueUrl = 'https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/catalog/mods.json'
$script:ClientCatalogueUrl = 'https://raw.githubusercontent.com/SergeyLutsky/gtnh-server-setup/main/catalog/client-addons.json'

function Get-PrismInstancePath {
    if ($InstancePath) {
        return [IO.Path]::GetFullPath($InstancePath)
    }

    $instanceRoots = @()
    if ($PrismRoot) {
        $instanceRoots += (Join-Path ([IO.Path]::GetFullPath($PrismRoot)) 'instances')
    }
    $instanceRoots += @(
        (Join-Path $env:APPDATA 'PrismLauncher\instances'),
        (Join-Path $env:LOCALAPPDATA 'PrismLauncher\instances'),
        (Join-Path $env:USERPROFILE 'PrismLauncher\instances'),
        (Join-Path $env:USERPROFILE 'scoop\persist\prismlauncher\instances')
    )

    $matches = @()
    foreach ($root in ($instanceRoots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($directory in (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
            foreach ($gameDirectoryName in @('.minecraft', 'minecraft')) {
                $versionFile = Join-Path $directory.FullName "$gameDirectoryName\config\txloader\load\mainmenu\version.txt"
                if ((Test-Path -LiteralPath $versionFile -PathType Leaf) -and
                    ((Get-Content -LiteralPath $versionFile -Raw) -match 'GTNH\s+2\.8\.4(?:\D|$)')) {
                    $matches += $directory.FullName
                    break
                }
            }
        }
    }

    if ($matches.Count -eq 1) { return $matches[0] }
    if ($matches.Count -gt 1) {
        throw "More than one GTNH 2.8.4 Prism instance was found. Run again with -InstancePath and one of: $($matches -join '; ')"
    }
    throw 'No GTNH 2.8.4 Prism instance was found. Run again with -InstancePath "C:\path\to\PrismLauncher\instances\your-instance".'
}

function Get-MinecraftPath([string]$Instance) {
    foreach ($name in @('.minecraft', 'minecraft')) {
        $candidate = Join-Path $Instance $name
        if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
    }
    throw "The Prism game directory (.minecraft or minecraft) is missing: $Instance"
}

function Assert-GtnhInstance([string]$Path) {
    $instanceConfig = Join-Path $Path 'instance.cfg'
    $minecraftPath = Get-MinecraftPath $Path
    $versionFile = Join-Path $minecraftPath 'config\txloader\load\mainmenu\version.txt'
    if (-not (Test-Path -LiteralPath $instanceConfig -PathType Leaf)) {
        throw "Not a Prism Launcher instance: $Path"
    }
    if (-not (Test-Path -LiteralPath $versionFile -PathType Leaf)) {
        throw "The GTNH version marker is missing: $versionFile"
    }
    $versionText = Get-Content -LiteralPath $versionFile -Raw
    if ($versionText -notmatch 'GTNH\s+2\.8\.4(?:\D|$)') {
        throw "This script requires GTNH $script:ExpectedVersion, but the instance reports: $($versionText.Trim())"
    }
}

function Get-ModCatalogue {
    if ($CataloguePath) {
        $json = Get-Content -LiteralPath ([IO.Path]::GetFullPath($CataloguePath)) -Raw
    }
    else {
        $local = Join-Path $PSScriptRoot 'catalog\mods.json'
        if ($PSScriptRoot -and (Test-Path -LiteralPath $local -PathType Leaf)) {
            $json = Get-Content -LiteralPath $local -Raw
        }
        else {
            Write-Host 'Downloading the managed mod catalogue...'
            $json = (Invoke-WebRequest -UseBasicParsing -Uri $script:CatalogueUrl).Content
        }
    }
    $catalogue = $json | ConvertFrom-Json
    if ($catalogue.schemaVersion -ne 1 -or -not $catalogue.mods) {
        throw 'The mod catalogue has an unsupported or invalid format.'
    }
    return $catalogue
}

function Get-ClientCatalogue {
    if ($ClientCataloguePath) {
        $json = Get-Content -LiteralPath ([IO.Path]::GetFullPath($ClientCataloguePath)) -Raw
    }
    else {
        $local = Join-Path $PSScriptRoot 'catalog\client-addons.json'
        if ($PSScriptRoot -and (Test-Path -LiteralPath $local -PathType Leaf)) {
            $json = Get-Content -LiteralPath $local -Raw
        }
        else {
            Write-Host 'Downloading the managed client-add-on catalogue...'
            $json = (Invoke-WebRequest -UseBasicParsing -Uri $script:ClientCatalogueUrl).Content
        }
    }
    $catalogue = $json | ConvertFrom-Json
    if ($catalogue.schemaVersion -ne 1) {
        throw 'The client-add-on catalogue has an unsupported or invalid format.'
    }
    return $catalogue
}

function Resolve-SelectedMods($Catalogue) {
    if ([string]::IsNullOrWhiteSpace($Mods) -or $Mods -eq 'none') { return @() }
    if ($Mods -eq 'all') {
        return @($Catalogue.mods | Where-Object { $_.clientRequired -eq $true })
    }

    $ids = @($Mods.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $unknown = @($ids | Where-Object { $_ -notin @($Catalogue.mods.id) })
    if ($unknown.Count -gt 0) { throw "Unknown mod id(s): $($unknown -join ', ')" }
    $notClient = @($Catalogue.mods | Where-Object { $_.id -in $ids -and $_.clientRequired -ne $true })
    if ($notClient.Count -gt 0) { throw "Not client-installable: $($notClient.id -join ', ')" }
    return @($Catalogue.mods | Where-Object { $_.id -in $ids })
}

function Resolve-Artifacts($SelectedMods) {
    $resolved = @()
    foreach ($mod in $SelectedMods) {
        $release = @($mod.releases | Where-Object { $_.gtnh -eq $script:ExpectedVersion }) | Select-Object -First 1
        if (-not $release) { throw "$($mod.name) is not pinned for GTNH $script:ExpectedVersion." }
        $resolved += [pscustomobject]@{
            ModId = $mod.id; Name = $mod.name; Version = $release.version
            FileName = $release.asset; Url = $release.url
            Sha256 = $release.sha256.ToLowerInvariant(); SizeBytes = [long]$release.sizeBytes
        }
        $requirementsProperty = $release.PSObject.Properties['runtimeRequirements']
        $requirements = if ($requirementsProperty) { @($requirementsProperty.Value) } else { @() }
        foreach ($requirement in $requirements) {
            $clientProperty = $requirement.PSObject.Properties['clientRequired']
            $artifactProperty = $requirement.PSObject.Properties['artifact']
            if ($clientProperty -and $clientProperty.Value -eq $true -and $artifactProperty) {
                $requirementArtifact = $artifactProperty.Value
                $resolved += [pscustomobject]@{
                    ModId = $mod.id; Name = $requirement.name; Version = ''
                    FileName = $requirement.jar; Url = $requirementArtifact.url
                    Sha256 = $requirementArtifact.sha256.ToLowerInvariant()
                    SizeBytes = [long]$requirementArtifact.sizeBytes
                }
            }
        }
    }
    return $resolved
}

function Resolve-ContentPacks($SelectedMods) {
    if ($SkipQuestContent) { return @() }
    $packs = @()
    foreach ($mod in $SelectedMods) {
        $release = @($mod.releases | Where-Object { $_.gtnh -eq $script:ExpectedVersion }) | Select-Object -First 1
        if (-not $release) { continue }
        $property = $release.PSObject.Properties['contentPacks']
        if ($property) {
            foreach ($pack in @($property.Value)) {
                $packs += [pscustomobject]@{ ModId = $mod.id; Pack = $pack }
            }
        }
    }
    return $packs
}

function Convert-ToArtifact([string]$Id, [string]$Name, [string]$Version, $Artifact) {
    return [pscustomobject]@{
        ModId = $Id; Name = $Name; Version = $Version
        FileName = $Artifact.name; Url = $Artifact.url
        Sha256 = $Artifact.sha256.ToLowerInvariant(); SizeBytes = [long]$Artifact.sizeBytes
    }
}

function Test-Artifact([string]$Path, $Artifact) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -ne $Artifact.SizeBytes) { return $false }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Artifact.Sha256
}

function Get-VerifiedArtifact($Artifact, [string]$CachePath) {
    $destination = Join-Path $CachePath $Artifact.FileName
    if (Test-Artifact $destination $Artifact) { return $destination }
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }

    $partial = "$destination.partial"
    if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    Write-Host "Downloading $($Artifact.Name)..."
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Artifact.Url -OutFile $partial
        if (-not (Test-Artifact $partial $Artifact)) {
            throw "Checksum or size verification failed for $($Artifact.FileName)."
        }
        Move-Item -LiteralPath $partial -Destination $destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
    return $destination
}

function Backup-File([string]$File, [string]$Instance, [string]$BackupRoot) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return }
    $relative = $File.Substring($Instance.TrimEnd('\').Length).TrimStart('\')
    $target = Join-Path $BackupRoot $relative
    if (Test-Path -LiteralPath $target -PathType Leaf) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $File -Destination $target
}

function Backup-Path([string]$Path, [string]$Instance, [string]$BackupRoot) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Backup-File $Path $Instance $BackupRoot
        return
    }
    $relative = $Path.Substring($Instance.TrimEnd('\').Length).TrimStart('\')
    $target = Join-Path $BackupRoot $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -LiteralPath $Path -Destination $target -Recurse -Force
}

function Expand-ZipSubtree([string]$Archive, [string]$ArchiveRoot, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $prefix = $ArchiveRoot.Trim('/').Replace('\', '/') + '/'
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if (-not $name.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
            $relative = $name.Substring($prefix.Length)
            if (-not $relative) { continue }
            $segments = @($relative.Split('/') | Where-Object { $_ })
            if ($relative.StartsWith('/') -or $segments -contains '..') {
                throw "Unsafe path in archive: $name"
            }
            $target = Join-Path $Destination ($segments -join [IO.Path]::DirectorySeparatorChar)
            if (-not $entry.Name) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            $input = $entry.Open()
            $output = [IO.File]::Create($target)
            try { $input.CopyTo($output) }
            finally { $output.Dispose(); $input.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}

function Install-ContentPack($Pack, [string]$Archive, [string]$Instance, [string]$BackupRoot) {
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("gtnh-content-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        Expand-ZipSubtree $Archive $Pack.archiveRoot $temporary
        foreach ($required in @($Pack.requiredEntries)) {
            $requiredRelative = $required.Substring($Pack.archiveRoot.Trim('/').Length).TrimStart('/')
            if ($requiredRelative -and -not (Test-Path -LiteralPath (Join-Path $temporary $requiredRelative))) {
                throw "Quest archive is missing required content: $required"
            }
        }
        $targetRoot = Join-Path (Get-MinecraftPath $Instance) ($Pack.target.Replace('/', '\'))
        foreach ($replace in @($Pack.replacePaths)) {
            if ($replace.StartsWith('/') -or @($replace.Split('/')) -contains '..') {
                throw "Unsafe quest replacement path: $replace"
            }
            $source = Join-Path $temporary ($replace.Replace('/', '\'))
            $destination = Join-Path $targetRoot ($replace.Replace('/', '\'))
            if (-not (Test-Path -LiteralPath $source)) { throw "Quest content is missing: $replace" }
            Backup-Path $destination $Instance $BackupRoot
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

function Test-ContentPackInstalled($Pack, [string]$Instance) {
    $targetRoot = Join-Path (Get-MinecraftPath $Instance) ($Pack.target.Replace('/', '\'))
    foreach ($replace in @($Pack.replacePaths)) {
        if (-not (Test-Path -LiteralPath (Join-Path $targetRoot ($replace.Replace('/', '\'))))) { return $false }
    }
    return $true
}

function Install-ResourcePack($Pack, [string]$Archive, [string]$Instance, [string]$BackupRoot) {
    $resourcePacks = Join-Path (Get-MinecraftPath $Instance) 'resourcepacks'
    $destination = Join-Path $resourcePacks $Pack.folder
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("gtnh-resource-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        Expand-ZipSubtree $Archive $Pack.archiveRoot $temporary
        foreach ($required in @($Pack.requiredEntries)) {
            if (-not (Test-Path -LiteralPath (Join-Path $temporary $required))) {
                throw "Resource-pack archive is missing: $required"
            }
        }
        Backup-Path $destination $Instance $BackupRoot
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
        New-Item -ItemType Directory -Path $resourcePacks -Force | Out-Null
        Move-Item -LiteralPath $temporary -Destination $destination
        $temporary = $null
    }
    finally {
        if ($temporary -and (Test-Path -LiteralPath $temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    }
}

function Enable-ResourcePack([string]$Folder, [string]$Instance, [string]$BackupRoot) {
    $path = Join-Path (Get-MinecraftPath $Instance) 'options.txt'
    $content = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { '' }
    $packs = @()
    $wasJsonArray = $false
    $match = [regex]::Match($content, '(?m)^resourcePacks:(.*)$')
    if ($match.Success -and $match.Groups[1].Value.Trim()) {
        $wasJsonArray = $match.Groups[1].Value.Trim().StartsWith('[')
        try { $packs = @($match.Groups[1].Value.Trim() | ConvertFrom-Json) }
        catch { throw 'The resourcePacks entry in options.txt is invalid JSON.' }
    }
    if ($Folder -in $packs -and $wasJsonArray) { return }
    if ($Folder -notin $packs) { $packs += $Folder }
    $line = 'resourcePacks:' + (ConvertTo-Json -InputObject @($packs) -Compress)
    if ($match.Success) { $updated = [regex]::Replace($content, '(?m)^resourcePacks:.*$', $line) }
    else { $updated = $content.TrimEnd("`r", "`n") + $(if ($content) { "`r`n" } else { '' }) + "$line`r`n" }
    Backup-File $path $Instance $BackupRoot
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    [IO.File]::WriteAllText($path, $updated, (New-Object Text.UTF8Encoding($false)))
}

function Reset-ModGeneratedFiles($Mod, [string]$Instance, [string]$BackupRoot) {
    $release = @($Mod.releases | Where-Object { $_.gtnh -eq $script:ExpectedVersion }) | Select-Object -First 1
    if (-not $release) { return }
    $property = $release.PSObject.Properties['updateResetPaths']
    if (-not $property) { return }
    foreach ($relative in @($property.Value) | Select-Object -Unique) {
        if (-not $relative.StartsWith('config/') -or @($relative.Split('/')) -contains '..') {
            throw "Unsafe generated-file reset path: $relative"
        }
        $minecraftPath = Get-MinecraftPath $Instance
        $paths = @((Join-Path $minecraftPath ($relative.Replace('/', '\'))))
        if ($relative -eq 'config/GregTech/GregTech.lang') {
            $paths += Join-Path $minecraftPath 'GregTech.lang'
        }
        foreach ($path in ($paths | Select-Object -Unique)) {
            Backup-Path $path $Instance $BackupRoot
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
    }
}

function Set-IniValue([string]$Content, [string]$Key, [string]$Value) {
    $line = "$Key=$Value"
    if ($Content -match "(?m)^$([regex]::Escape($Key))=") {
        return [regex]::Replace($Content, "(?m)^$([regex]::Escape($Key))=.*$", $line)
    }
    return $Content.TrimEnd("`r", "`n") + "`r`n$line`r`n"
}

function Set-PrismMemory([string]$Instance, [string]$BackupRoot) {
    $path = Join-Path $Instance 'instance.cfg'
    Backup-File $path $Instance $BackupRoot
    $content = Get-Content -LiteralPath $path -Raw
    $minimum = [Math]::Min(4096, $MemoryMB)
    $content = Set-IniValue $content 'OverrideMemory' 'true'
    $content = Set-IniValue $content 'MinMemAlloc' ([string]$minimum)
    $content = Set-IniValue $content 'MaxMemAlloc' ([string]$MemoryMB)
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
}

function Set-PrismAccount([string]$Instance, [string]$BackupRoot) {
    $prismDataRoot = if ($PrismRoot) {
        [IO.Path]::GetFullPath($PrismRoot)
    }
    else {
        Split-Path -Parent (Split-Path -Parent $Instance)
    }
    $accountsPath = Join-Path $prismDataRoot 'accounts.json'
    if (-not (Test-Path -LiteralPath $accountsPath -PathType Leaf)) {
        throw "Prism's accounts.json is missing. Add the Minecraft account '$PlayerName' in Prism Launcher, close Prism, and run this script again."
    }

    try { $accounts = Get-Content -LiteralPath $accountsPath -Raw | ConvertFrom-Json }
    catch { throw "Prism's accounts.json is unreadable. Close Prism Launcher and verify its account configuration." }
    $matches = @($accounts.accounts | Where-Object {
        $_.profile -and ([string]$_.profile.name -ceq $PlayerName) -and $_.profile.id
    })
    if ($matches.Count -ne 1) {
        $available = @($accounts.accounts | ForEach-Object { if ($_.profile.name) { [string]$_.profile.name } })
        $suffix = if ($available.Count -gt 0) { " Available profiles: $($available -join ', ')." } else { '' }
        throw "Prism must contain exactly one Minecraft profile named '$PlayerName'.$suffix Add or refresh that account, close Prism, and run this script again."
    }

    $path = Join-Path $Instance 'instance.cfg'
    Backup-File $path $Instance $BackupRoot
    $content = Get-Content -LiteralPath $path -Raw
    $content = Set-IniValue $content 'UseAccountForInstance' 'true'
    $content = Set-IniValue $content 'InstanceAccountId' ([string]$matches[0].profile.id)
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
    return [string]$matches[0].profile.id
}

function Set-DefaultServer([string]$Instance, [string]$BackupRoot) {
    if ([string]::IsNullOrWhiteSpace($ServerAddress)) { return }
    if ($ServerAddress -match '[|\r\n]' -or $ServerName -match '[|\r\n]') {
        throw 'ServerAddress and ServerName cannot contain a pipe or newline.'
    }
    $path = Join-Path (Get-MinecraftPath $Instance) 'config\defaultserverlist.cfg'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "GTNH's Default Server List configuration is missing: $path"
    }
    Backup-File $path $Instance $BackupRoot
    $content = Get-Content -LiteralPath $path -Raw
    $block = "    S:servers <`r`n        $ServerAddress|$ServerName`r`n     >"
    if ($content -notmatch '(?ms)^\s*S:servers\s*<.*?^\s*>') {
        throw 'The Default Server List configuration has an unexpected format.'
    }
    $content = [regex]::Replace($content, '(?ms)^\s*S:servers\s*<.*?^\s*>', $block)
    $content = [regex]::Replace($content, '(?m)^\s*B:useURL=(?:true|false)\s*$', '    B:useURL=false')
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
}

if ($env:GTNH_SETUP_TEST_ONLY -eq '1') { return }

$instance = Get-PrismInstancePath
Assert-GtnhInstance $instance
$catalogue = Get-ModCatalogue
$clientCatalogue = Get-ClientCatalogue
$selected = @(Resolve-SelectedMods $catalogue)
$artifacts = @(Resolve-Artifacts $selected)
$contentPacks = @(Resolve-ContentPacks $selected)
$resourcePacks = @()

if (-not $SkipClientExtras) {
    foreach ($clientMod in @($clientCatalogue.clientMods | Where-Object { $_.gtnh -eq $script:ExpectedVersion })) {
        $artifacts += Convert-ToArtifact $clientMod.id $clientMod.name $clientMod.version $clientMod.artifact
    }
    $resourcePacks = @($clientCatalogue.resourcePacks | Where-Object { $_.gtnh -eq $script:ExpectedVersion })
}

$minecraft = Get-MinecraftPath $instance
$modsPath = Join-Path $minecraft 'mods'
$statePath = Join-Path $instance '.gtnh-client-setup.json'
$cachePath = Join-Path $env:LOCALAPPDATA 'gtnh-server-setup\downloads'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $instance ".gtnh-client-backups\$timestamp"
New-Item -ItemType Directory -Path $modsPath, $cachePath -Force | Out-Null

$downloadArtifacts = @($artifacts)
foreach ($wrapped in $contentPacks) {
    $downloadArtifacts += Convert-ToArtifact $wrapped.Pack.id $wrapped.Pack.name $wrapped.Pack.version $wrapped.Pack.archive
}
foreach ($pack in $resourcePacks) {
    $downloadArtifacts += Convert-ToArtifact $pack.id $pack.name $pack.version $pack.artifact
}
$downloads = @{}
foreach ($artifact in $downloadArtifacts) {
    $downloads[$artifact.FileName] = Get-VerifiedArtifact $artifact $cachePath
}

$previousState = $null
$previousFiles = @()
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try {
        $previousState = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $managedProperty = $previousState.PSObject.Properties['managedFiles']
        if ($managedProperty) { $previousFiles = @($managedProperty.Value) }
    }
    catch { Write-Warning 'The previous client setup state is unreadable; no files from it will be removed.' }
}
$wantedFiles = @($artifacts | ForEach-Object { $_.FileName })
foreach ($fileName in $previousFiles) {
    if ($fileName -and $fileName -notin $wantedFiles) {
        $path = Join-Path $modsPath $fileName
        Backup-File $path $instance $backupRoot
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

# Remove other enabled versions of selected server mods. CurseForge instances
# may already contain newer or older JARs whose filenames differ from our pin;
# loading both versions would fail before Minecraft reaches the main menu.
foreach ($selectedMod in $selected) {
    $patternSet = @($clientCatalogue.serverModFilePatterns | Where-Object { $_.id -eq $selectedMod.id }) | Select-Object -First 1
    if (-not $patternSet) { continue }
    foreach ($pattern in @($patternSet.patterns)) {
        foreach ($existing in (Get-ChildItem -LiteralPath $modsPath -File -Filter $pattern -ErrorAction SilentlyContinue)) {
            if ($existing.Name -in $wantedFiles) { continue }
            Backup-File $existing.FullName $instance $backupRoot
            Remove-Item -LiteralPath $existing.FullName -Force
        }
    }
}
foreach ($retired in @($catalogue.retiredMods)) {
    foreach ($fileName in @($retired.artifacts)) {
        $path = Join-Path $modsPath $fileName
        Backup-File $path $instance $backupRoot
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

# The authors require generated configuration and GregTech language files to be
# rebuilt whenever these mod JARs change. Back up first, and do nothing on a no-op rerun.
foreach ($mod in $selected) {
    $release = @($mod.releases | Where-Object { $_.gtnh -eq $script:ExpectedVersion }) | Select-Object -First 1
    if (-not $release) { continue }
    $artifact = @($artifacts | Where-Object { $_.ModId -eq $mod.id -and $_.FileName -eq $release.asset }) | Select-Object -First 1
    if ($artifact -and -not (Test-Artifact (Join-Path $modsPath $artifact.FileName) $artifact)) {
        Reset-ModGeneratedFiles $mod $instance $backupRoot
    }
}

foreach ($artifact in $artifacts) {
    $target = Join-Path $modsPath $artifact.FileName
    if (-not (Test-Artifact $target $artifact)) {
        Backup-File $target $instance $backupRoot
        Copy-Item -LiteralPath $downloads[$artifact.FileName] -Destination $target -Force
    }
}

$installedContentPacks = [ordered]@{}
foreach ($wrapped in $contentPacks) {
    $pack = $wrapped.Pack
    $previousVersion = $null
    if ($previousState) {
        $mapProperty = $previousState.PSObject.Properties['contentPacks']
        if ($mapProperty -and $mapProperty.Value) {
            $versionProperty = $mapProperty.Value.PSObject.Properties[$pack.id]
            if ($versionProperty) { $previousVersion = [string]$versionProperty.Value }
        }
    }
    if ($previousVersion -ne [string]$pack.version -or -not (Test-ContentPackInstalled $pack $instance)) {
        Install-ContentPack $pack $downloads[$pack.archive.name] $instance $backupRoot
    }
    $installedContentPacks[$pack.id] = $pack.version
}

$installedResourcePacks = [ordered]@{}
foreach ($pack in $resourcePacks) {
    $destination = Join-Path $minecraft "resourcepacks\$($pack.folder)"
    $previousVersion = $null
    if ($previousState) {
        $mapProperty = $previousState.PSObject.Properties['resourcePacks']
        if ($mapProperty -and $mapProperty.Value) {
            $versionProperty = $mapProperty.Value.PSObject.Properties[$pack.id]
            if ($versionProperty) { $previousVersion = [string]$versionProperty.Value }
        }
    }
    if ($previousVersion -ne [string]$pack.version -or -not (Test-Path -LiteralPath (Join-Path $destination 'pack.mcmeta'))) {
        Install-ResourcePack $pack $downloads[$pack.artifact.name] $instance $backupRoot
    }
    Enable-ResourcePack $pack.folder $instance $backupRoot
    $installedResourcePacks[$pack.id] = $pack.version
}

$profileId = Set-PrismAccount $instance $backupRoot
if (-not $SkipMemoryConfiguration) { Set-PrismMemory $instance $backupRoot }
Set-DefaultServer $instance $backupRoot

$state = [ordered]@{
    schemaVersion = 1
    managedBy = 'gtnh-server-setup'
    configuredAt = (Get-Date).ToUniversalTime().ToString('o')
    gtnhVersion = $script:ExpectedVersion
    instancePath = $instance
    selectedMods = @($selected | ForEach-Object { $_.id })
    managedFiles = $wantedFiles
    contentPacks = $installedContentPacks
    resourcePacks = $installedResourcePacks
    serverAddress = $ServerAddress
    playerName = $PlayerName
    prismProfileId = $profileId
    memoryMB = if ($SkipMemoryConfiguration) { $null } else { $MemoryMB }
}
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))

Write-Host ''
Write-Host "GTNH $script:ExpectedVersion client is configured: $instance" -ForegroundColor Green
if ($selected.Count -eq 0) { Write-Host 'Managed client add-ons: none' }
else { Write-Host "Managed client add-ons: $(@($selected | ForEach-Object { $_.name }) -join ', ')" }
if (-not $SkipClientExtras) { Write-Host 'Client extras: Extreme Sound Muffler: Legacy, Outlined Ores Modern' }
if ($contentPacks.Count -gt 0) { Write-Host "Quest content: $(@($contentPacks | ForEach-Object { $_.Pack.name }) -join ', ')" }
if ($ServerAddress) { Write-Host "Multiplayer server: $ServerName ($ServerAddress)" }
Write-Host "Minecraft account: $PlayerName (pinned to this Prism instance)"
if (-not $SkipMemoryConfiguration) { Write-Host "Prism memory: $MemoryMB MiB maximum" }
if (Test-Path -LiteralPath $backupRoot -PathType Container) { Write-Host "Backups: $backupRoot" }
Write-Host 'Restart Prism Launcher before starting the instance.'
