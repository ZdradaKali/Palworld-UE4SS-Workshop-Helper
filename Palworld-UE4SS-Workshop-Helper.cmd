@echo off
rem Original scripts and helpers by ZdradaKali (GitHub) / Yani Neco (Steam) / hess_ch (Discord).
rem Official source: https://github.com/ZdradaKali/Palworld-UE4SS-Workshop-Helper
rem Copies from any other source are unverified and may have been modified.
setlocal
title Palworld UE4SS Workshop Helper
set "PALWORLD_HELPER_FILE=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:PALWORLD_HELPER_FILE; $c=[IO.File]::ReadAllText($p); $m='### POWERSHELL PAYLOAD ###'; $i=$c.LastIndexOf($m); if($i -lt 0){throw 'Embedded PowerShell payload not found.'}; & ([scriptblock]::Create($c.Substring($i+$m.Length)))"
set "HELPER_EXIT=%ERRORLEVEL%"
if not "%HELPER_EXIT%"=="0" (
    echo.
    echo The helper stopped with exit code %HELPER_EXIT%.
    pause
)
exit /b %HELPER_EXIT%
### POWERSHELL PAYLOAD ###

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:HelperVersion = '2.2.0'
$script:Builds = [ordered]@{
    Official = [pscustomobject]@{
        Key = 'Official'
        DisplayName = 'Official Experimental build'
        Owner = 'UE4SS-RE'
        Repository = 'RE-UE4SS'
        Tag = 'experimental-latest'
        AssetName = 'UE4SS_v3.0.1-1018-g662df915.zip'
        TrustedSha256 = '590AE4C6463DB61497123B9ED35373596C39FB27F736E2078A02B476599671BA'
    }
    Palworld = [pscustomobject]@{
        Key = 'Palworld'
        DisplayName = 'Palworld-specific Experimental build'
        Owner = 'Okaetsu'
        Repository = 'RE-UE4SS'
        Tag = 'experimental-palworld'
        AssetName = 'UE4SS-Palworld.zip'
        TrustedSha256 = '768A45718FBB9E429AC5CC3CE4A139A1B7B468BFF31B4A136AE483D725ACA1CA'
    }
}
$script:PalworldAppId = '1623730'
$script:GameRoot = $null

function Write-Heading {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan
}

function Wait-ForMenu {
    Write-Host ''
    Write-Host 'Press Enter to return to the main menu.' -ForegroundColor DarkGray
    [void](Read-Host)
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        $answer = (Read-Host "$Prompt [Y/N]").Trim()
        if ($answer -match '^(?i)y(?:es)?$') { return $true }
        if ($answer -match '^(?i)n(?:o)?$') { return $false }
        Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
    }
}

function Normalize-GameRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $clean = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').TrimEnd('\', '/'))
    try { return [IO.Path]::GetFullPath($clean) } catch { return $null }
}

function Test-GameRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $win64 = Join-Path $Path 'Pal\Binaries\Win64'
    if (-not (Test-Path -LiteralPath $win64 -PathType Container)) { return $false }
    foreach ($candidate in @(
        (Join-Path $Path 'Palworld.exe'),
        (Join-Path $win64 'Palworld-Win64-Shipping.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    return $false
}

function Write-AuditValue {
    param(
        [string]$Label,
        [object]$Value,
        [ValidateSet('Good','Bad','Warning','Neutral')][string]$State = 'Neutral'
    )
    $color = switch ($State) {
        'Good' { 'Green' }
        'Bad' { 'Red' }
        'Warning' { 'Yellow' }
        default { 'DarkGray' }
    }
    Write-Host ("{0,-40}: " -f $Label) -NoNewline
    Write-Host ([string]$Value) -ForegroundColor $color
}

function Get-ClientTableCell {
    param([object]$Value, [int]$Width)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text.Length -gt $Width) {
        if ($Width -le 3) { return $text.Substring(0, $Width) }
        $text = $text.Substring(0, $Width - 3) + '...'
    }
    return $text.PadRight($Width)
}

function Write-ClientModReport {
    param([object[]]$Mods)
    $columns = @(
        [pscustomobject]@{ Name='Mod'; Label='Mod'; Width=32 },
        [pscustomobject]@{ Name='Package'; Label='Package'; Width=26 },
        [pscustomobject]@{ Name='Types'; Label='Install types'; Width=14 },
        [pscustomobject]@{ Name='ServerRule'; Label='Server-side'; Width=12 },
        [pscustomobject]@{ Name='Dependencies'; Label='Dependencies'; Width=24 },
        [pscustomobject]@{ Name='RuntimeState'; Label='Runtime state'; Width=28 }
    )
    foreach ($column in $columns) {
        Write-Host (Get-ClientTableCell $column.Label $column.Width) -NoNewline -ForegroundColor Cyan
        Write-Host ' ' -NoNewline
    }
    Write-Host ''
    foreach ($column in $columns) { Write-Host (('-' * $column.Width) + ' ') -NoNewline -ForegroundColor DarkCyan }
    Write-Host ''

    foreach ($mod in @($Mods | Sort-Object Package)) {
        foreach ($column in $columns) {
            $value = $mod.($column.Name)
            $color = 'Gray'
            if ($column.Name -eq 'ServerRule') {
                $color = if ([string]$value -eq 'Yes') { 'Green' } elseif ([string]$value -eq 'No') { 'DarkGray' } else { 'Yellow' }
            } elseif ($column.Name -eq 'Dependencies') {
                $color = if ([string]$value -like 'Missing:*') { 'Red' } elseif ([string]$value -eq 'Present') { 'Green' } else { 'DarkGray' }
            } elseif ($column.Name -eq 'RuntimeState') {
                $color = switch -Regex ([string]$value) {
                    '^(Enabled(?: \((?:enabled\.txt|mods\.txt)\))?|PalSchema content deployed)$' { 'Green'; break }
                    '^(Content not deployed|Deployed but not enabled|Disabled in mods\.txt|PalSchema content not deployed|Invalid Info\.json)' { 'Red'; break }
                    default { 'DarkGray' }
                }
            }
            Write-Host (Get-ClientTableCell $value $column.Width) -NoNewline -ForegroundColor $color
            Write-Host ' ' -NoNewline
        }
        Write-Host ''
    }
    foreach ($mod in @($Mods | Where-Object { $_.Dependencies -like 'Missing:*' })) {
        Write-Host "Missing dependencies for $($mod.Package): $($mod.Dependencies.Substring(8).Trim())" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'Install types: deployment methods declared by the Workshop package, such as Lua, PalSchema, Paks or UE4SS.' -ForegroundColor DarkGray
    Write-Host 'Server-side: Yes means Info.json contains at least one IsServer=true rule. It does not guarantee multiplayer compatibility.' -ForegroundColor DarkGray
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($registryPath in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $key = Get-ItemProperty -LiteralPath $registryPath -ErrorAction Stop
            foreach ($property in @('SteamPath', 'InstallPath')) {
                $propertyValue = $key.PSObject.Properties[$property]
                if ($null -eq $propertyValue) { continue }
                $value = Normalize-GameRoot ([string]$propertyValue.Value)
                if ($value -and (Test-Path -LiteralPath $value -PathType Container)) { $roots.Add($value) }
            }
        } catch { }
    }

    $libraryFiles = @($roots | ForEach-Object { Join-Path $_ 'steamapps\libraryfolders.vdf' })
    foreach ($file in $libraryFiles) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $content = Get-Content -LiteralPath $file -Raw
            foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $library = $match.Groups[1].Value -replace '\\\\', '\'
                $library = Normalize-GameRoot $library
                if ($library -and (Test-Path -LiteralPath $library -PathType Container)) { $roots.Add($library) }
            }
        } catch { }
    }
    return @($roots | Sort-Object -Unique)
}

function Find-PalworldInstallations {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in Get-SteamRoots) {
        $steamApps = if ((Split-Path -Leaf $steamRoot) -ieq 'steamapps') { $steamRoot } else { Join-Path $steamRoot 'steamapps' }
        $manifest = Join-Path $steamApps "appmanifest_$($script:PalworldAppId).acf"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                $content = Get-Content -LiteralPath $manifest -Raw
                $match = [regex]::Match($content, '"installdir"\s+"([^"]+)"')
                if ($match.Success) {
                    $candidate = Normalize-GameRoot (Join-Path $steamApps (Join-Path 'common' $match.Groups[1].Value))
                    if (Test-GameRoot $candidate) { $candidates.Add($candidate) }
                }
            } catch { }
        }
        $defaultCandidate = Normalize-GameRoot (Join-Path $steamApps 'common\Palworld')
        if (Test-GameRoot $defaultCandidate) { $candidates.Add($defaultCandidate) }
    }
    return @($candidates | Sort-Object -Unique)
}

function Select-GameRoot {
    $found = @(Find-PalworldInstallations)
    if ($found.Count -eq 1) {
        Write-Host "Detected Palworld installation: $($found[0])" -ForegroundColor Green
        if (Read-YesNo 'Use this installation?') { $script:GameRoot = $found[0]; return }
    } elseif ($found.Count -gt 1) {
        Write-Host 'Multiple Palworld installations were detected:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1). $($found[$i])" }
        Write-Host "  M. Enter a path manually"
        while ($true) {
            $selection = (Read-Host 'Choose an installation').Trim()
            if ($selection -match '^\d+$') {
                $index = [int]$selection - 1
                if ($index -ge 0 -and $index -lt $found.Count) { $script:GameRoot = $found[$index]; return }
            }
            if ($selection -match '^(?i)m$') { break }
            Write-Host 'Invalid selection.' -ForegroundColor Yellow
        }
    }

    while ($true) {
        Write-Host ''
        Write-Host 'In Steam: Library > right-click Palworld > Manage > Browse local files.' -ForegroundColor DarkGray
        $manual = Normalize-GameRoot (Read-Host 'Paste the Palworld installation folder path')
        if (Test-GameRoot $manual) { $script:GameRoot = $manual; return }
        Write-Host 'That folder does not contain Pal\Binaries\Win64. Please try again.' -ForegroundColor Yellow
    }
}

function Get-Paths {
    if (-not (Test-GameRoot $script:GameRoot)) { Select-GameRoot }
    $root = $script:GameRoot
    return @{
        Root = $root
        Win64 = Join-Path $root 'Pal\Binaries\Win64'
        ManagedRoot = Join-Path $root 'Mods\ManagedMods'
        WorkshopRoot = Join-Path $root 'Mods\NativeMods\UE4SS'
        WorkshopMods = Join-Path $root 'Mods\NativeMods\UE4SS\Mods'
        WorkshopDll = Join-Path $root 'Mods\NativeMods\UE4SS\UE4SS.dll'
        WorkshopLayout = Join-Path $root 'Mods\NativeMods\UE4SS\MemberVariableLayout.ini'
        GitHubRoot = Join-Path $root 'Pal\Binaries\Win64\ue4ss'
        GitHubMods = Join-Path $root 'Pal\Binaries\Win64\ue4ss\Mods'
        GitHubDll = Join-Path $root 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
        GitHubProxy = Join-Path $root 'Pal\Binaries\Win64\dwmapi.dll'
        GitHubLayout = Join-Path $root 'Pal\Binaries\Win64\ue4ss\MemberVariableLayout.ini'
        RuntimeMarker = Join-Path $root 'Pal\Binaries\Win64\ue4ss\Palworld-UE4SS-Helper-runtime.json'
        HelperRoot = Join-Path $root '_UE4SS-Helper'
        BackupsRoot = Join-Path $root '_UE4SS-Helper\Backups'
    }
}

function Assert-PalworldClosed {
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -in @('Palworld', 'Palworld-Win64-Shipping', 'Palworld-WinGDK-Shipping')
    })
    if ($running.Count -gt 0) { throw 'Palworld is running. Close the game completely and try again.' }
}

function Test-IsJunction {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $item -and $item.LinkType -eq 'Junction')
}

function Assert-JunctionTarget {
    param([string]$Path, [string]$ExpectedTarget)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.LinkType -ne 'Junction') { throw "Expected a directory junction: $Path" }
    $targetText = [string]@($item.Target)[0]
    if (-not [IO.Path]::IsPathRooted($targetText)) { $targetText = Join-Path (Split-Path -Parent $Path) $targetText }
    $target = [IO.Path]::GetFullPath($targetText).TrimEnd('\')
    $expected = [IO.Path]::GetFullPath($ExpectedTarget).TrimEnd('\')
    if ($target -ine $expected) { throw "The junction points to '$target' instead of '$expected'." }
}

function Remove-VerifiedJunction {
    param([string]$Path, [string]$ExpectedTarget)
    Assert-JunctionTarget $Path $ExpectedTarget
    [IO.Directory]::Delete($Path, $false)
    if (Test-Path -LiteralPath $Path) { throw "The junction could not be removed: $Path" }
    if (-not (Test-Path -LiteralPath $ExpectedTarget -PathType Container)) {
        throw 'The junction target unexpectedly disappeared. Stop and restore from the backup.'
    }
}

function Copy-Directory {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    $code = $LASTEXITCODE
    if ($code -ge 8) { throw "Robocopy failed with exit code $code while copying '$Source'." }
}

function New-BackupRoot {
    param([hashtable]$Paths, [string]$Operation)
    New-Item -ItemType Directory -Path $Paths.BackupsRoot -Force | Out-Null
    $base = Join-Path $Paths.BackupsRoot "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$Operation"
    $candidate = $base
    $suffix = 1
    while (Test-Path -LiteralPath $candidate) { $candidate = "$base-$suffix"; $suffix++ }
    New-Item -ItemType Directory -Path $candidate | Out-Null
    return $candidate
}

function Save-BackupManifest {
    param([string]$BackupRoot, [string]$Operation, [hashtable]$Extra)
    $manifest = [ordered]@{
        helperVersion = $script:HelperVersion
        operation = $Operation
        createdUtc = [DateTime]::UtcNow.ToString('o')
        gameRoot = $script:GameRoot
    }
    foreach ($key in $Extra.Keys) { $manifest[$key] = $Extra[$key] }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $BackupRoot 'backup-manifest.json') -Encoding UTF8
}

function Get-RecordValue {
    param([object]$Record, [string]$Name)
    if ($null -eq $Record) { return '' }
    $property = $Record.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return '' }
    return [string]$property.Value
}

function Save-RuntimeRecord {
    param([string]$Path, [object]$Package, [string]$Target)
    $record = [ordered]@{
        helperVersion = $script:HelperVersion
        target = $Target
        installedUtc = [DateTime]::UtcNow.ToString('o')
        buildKey = $Package.BuildKey
        buildName = $Package.BuildName
        repository = $Package.Repository
        tag = $Package.Tag
        assetName = $Package.AssetName
        archiveSha256 = $Package.Sha256
    }
    $json = $record | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-RuntimeRecord {
    param([hashtable]$Paths)
    if (Test-Path -LiteralPath $Paths.RuntimeMarker -PathType Leaf) {
        try {
            $record = Get-Content -LiteralPath $Paths.RuntimeMarker -Raw | ConvertFrom-Json
            if (Get-RecordValue $record 'buildKey') {
                return [pscustomobject]@{ Record=$record; Source='runtime marker' }
            }
        } catch { }
    }
    if (Test-Path -LiteralPath $Paths.BackupsRoot -PathType Container) {
        foreach ($folder in @(Get-ChildItem -LiteralPath $Paths.BackupsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
            $manifestPath = Join-Path $folder.FullName 'backup-manifest.json'
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                if ((Get-RecordValue $manifest 'operation') -eq 'Install' -and (Get-RecordValue $manifest 'sourceBuild')) {
                    return [pscustomobject]@{ Record=$manifest; Source='latest helper install backup' }
                }
            } catch { }
        }
    }
    return $null
}

function Get-InstalledRuntimeSummary {
    param([hashtable]$Paths)
    $externalDll = Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf
    $externalProxy = Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf
    $workshop = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    if ($externalDll -and $externalProxy -and $workshop) {
        return [pscustomobject]@{ Text='CONFLICT: external and Workshop runtimes are both active'; Color='Red' }
    }
    if ($externalDll -xor $externalProxy) {
        return [pscustomobject]@{ Text='Incomplete external runtime (repair required)'; Color='Red' }
    }
    if ($externalDll -and $externalProxy) {
        $saved = Get-RuntimeRecord $Paths
        if ($saved) {
            $record = $saved.Record
            $buildKey = Get-RecordValue $record $(if ($saved.Source -eq 'runtime marker') { 'buildKey' } else { 'sourceBuild' })
            $buildName = Get-RecordValue $record 'buildName'
            if (-not $buildName) {
                $buildName = switch ($buildKey) {
                    'Palworld' { 'Palworld-specific Experimental build' }
                    'Official' { 'Official Experimental build' }
                    default { "$buildKey build" }
                }
            }
            $tag = Get-RecordValue $record $(if ($saved.Source -eq 'runtime marker') { 'tag' } else { 'sourceTag' })
            $suffix = if ($tag) { " [$tag]" } else { '' }
            $evidence = if ($saved.Source -eq 'runtime marker') { '' } else { ' (from last helper install)' }
            return [pscustomobject]@{ Text="$buildName$suffix$evidence"; Color='Green' }
        }
        return [pscustomobject]@{ Text='External Experimental build (provider unknown)'; Color='Yellow' }
    }
    if ($workshop) { return [pscustomobject]@{ Text='Palworld Workshop UE4SS runtime'; Color='Green' } }
    return [pscustomobject]@{ Text='No active UE4SS runtime detected'; Color='Red' }
}

function Get-ExperimentalRelease {
    param([object]$Build)
    $api = "https://api.github.com/repos/$($Build.Owner)/$($Build.Repository)/releases/tags/$($Build.Tag)"
    Write-Host "Checking: $($Build.DisplayName)..."
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = "Palworld-UE4SS-Workshop-Helper/$($script:HelperVersion)" }
    $release = Invoke-RestMethod -Uri $api -Headers $headers -UseBasicParsing -TimeoutSec 30
    if ([string]$release.tag_name -ne $Build.Tag) { throw "GitHub returned unexpected tag: $($release.tag_name)" }
    if ([string]$release.html_url -ne "https://github.com/$($Build.Owner)/$($Build.Repository)/releases/tag/$($Build.Tag)") {
        throw 'GitHub returned an unexpected release URL.'
    }
    $assets = @($release.assets | Where-Object {
        [string]$_.name -ceq $Build.AssetName -and
        [string]$_.browser_download_url -ceq "https://github.com/$($Build.Owner)/$($Build.Repository)/releases/download/$($Build.Tag)/$($Build.AssetName)"
    })
    if ($assets.Count -ne 1) {
        throw "Expected exactly one $($Build.AssetName) asset, but found $($assets.Count). The release layout may have changed; no file was downloaded."
    }
    return [pscustomobject]@{ Release=$release; Asset=$assets[0] }
}

function Test-ZipEntries {
    param([string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $totalSize = [int64]0
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            $segments = @($name.Split('/') | Where-Object { $_ -ne '' })
            if ($name.StartsWith('/') -or $name -match '^[A-Za-z]:' -or '..' -in $segments) {
                throw "Unsafe path found inside the ZIP: $name"
            }
            $totalSize += [int64]$entry.Length
            if ($totalSize -gt 2GB) { throw 'The ZIP expands beyond the 2 GB safety limit.' }
        }
    } finally { $archive.Dispose() }
}

function Get-ExtractedLayout {
    param([string]$ExtractedRoot)
    $dlls = @(Get-ChildItem -LiteralPath $ExtractedRoot -Filter 'UE4SS.dll' -File -Recurse | Where-Object { $_.Directory.Name -ieq 'ue4ss' })
    $layouts = New-Object System.Collections.Generic.List[object]
    foreach ($dll in $dlls) {
        $win64Source = $dll.Directory.Parent.FullName
        $proxy = Join-Path $win64Source 'dwmapi.dll'
        if (Test-Path -LiteralPath $proxy -PathType Leaf) {
            $layouts.Add([pscustomobject]@{ Win64Source=$win64Source; Ue4ssSource=$dll.Directory.FullName; ProxySource=$proxy })
        }
    }
    if ($layouts.Count -ne 1) { throw "The archive does not contain exactly one supported layout with dwmapi.dll and ue4ss\UE4SS.dll. Found: $($layouts.Count)." }
    return $layouts[0]
}

function Get-ExperimentalPackage {
    param([object]$Build)
    $releaseInfo = Get-ExperimentalRelease $Build
    $asset = $releaseInfo.Asset
    $release = $releaseInfo.Release
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "Palworld-UE4SS-Helper-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $zipPath = Join-Path $tempRoot ([string]$asset.name)
    $extractPath = Join-Path $tempRoot 'extracted'
    try {
        Write-Host "Downloading: $($asset.name)"
        Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = "Palworld-UE4SS-Workshop-Helper/$($script:HelperVersion)" }
        $actualLength = (Get-Item -LiteralPath $zipPath).Length
        if ($actualLength -ne [int64]$asset.size) { throw "Downloaded size mismatch. Expected $($asset.size), received $actualLength bytes." }
        $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($asset.PSObject.Properties.Name -contains 'digest' -and -not [string]::IsNullOrWhiteSpace([string]$asset.digest)) {
            $expectedHash = ([string]$asset.digest -replace '^(?i)sha256:', '').ToUpperInvariant()
            if ($hash -ne $expectedHash) { throw "SHA-256 mismatch. Expected $expectedHash, received $hash." }
        }
        if ($hash -ne $Build.TrustedSha256) {
            throw "The selected release archive has changed since this helper was reviewed. Expected trusted SHA-256 $($Build.TrustedSha256), received $hash. Download an updated helper release instead of continuing."
        }
        Test-ZipEntries $zipPath
        New-Item -ItemType Directory -Path $extractPath | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
        $layout = Get-ExtractedLayout $extractPath
        return [pscustomobject]@{
            TempRoot=$tempRoot
            BuildKey=[string]$Build.Key
            BuildName=[string]$Build.DisplayName
            Repository="$($Build.Owner)/$($Build.Repository)"
            Tag=[string]$release.tag_name
            ReleaseName=[string]$release.name
            PublishedAt=[string]$release.published_at
            AssetName=[string]$asset.name
            AssetSize=[int64]$asset.size
            DownloadUrl=[string]$asset.browser_download_url
            Sha256=$hash
            Layout=$layout
        }
    } catch {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
        throw
    }
}

function Copy-Ue4ssOverlay {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $sourceFull = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force -Recurse) {
        $relative = $item.FullName.Substring($sourceFull.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        if ($item.PSIsContainer) { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
        if ($relative -ieq 'UE4SS-settings.ini' -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-Host 'Preserved existing UE4SS-settings.ini.' -ForegroundColor DarkGray
            continue
        }
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
}

function Ensure-MemberVariableLayout {
    param(
        [hashtable]$Paths,
        [switch]$Apply,
        [switch]$Required
    )
    if (Test-Path -LiteralPath $Paths.GitHubLayout -PathType Leaf) {
        return [pscustomobject]@{ Changed=$false; Pending=$false; Result='Already present' }
    }
    if (-not (Test-Path -LiteralPath $Paths.WorkshopLayout -PathType Leaf)) {
        $message = "Missing from both locations. Workshop source not found: $($Paths.WorkshopLayout)"
        if ($Required) { throw $message }
        return [pscustomobject]@{ Changed=$false; Pending=$false; Result=$message }
    }
    if (-not $Apply) {
        return [pscustomobject]@{ Changed=$false; Pending=$true; Result='Would copy from the Workshop UE4SS folder' }
    }
    New-Item -ItemType Directory -Path $Paths.GitHubRoot -Force | Out-Null
    Copy-Item -LiteralPath $Paths.WorkshopLayout -Destination $Paths.GitHubLayout -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $Paths.GitHubLayout -PathType Leaf)) {
        throw "MemberVariableLayout.ini could not be installed: $($Paths.GitHubLayout)"
    }
    return [pscustomobject]@{ Changed=$true; Pending=$false; Result='Copied from the Workshop UE4SS folder' }
}

function Ensure-PreparedMemberVariableLayout {
    param([hashtable]$Paths, [string]$PreparedRoot)
    $destination = Join-Path $PreparedRoot 'MemberVariableLayout.ini'
    if (Test-Path -LiteralPath $destination -PathType Leaf) { return 'Included in the selected archive' }
    foreach ($source in @($Paths.WorkshopLayout, $Paths.GitHubLayout)) {
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
            if (Test-Path -LiteralPath $destination -PathType Leaf) { return "Preserved from: $source" }
        }
    }
    throw 'MemberVariableLayout.ini is missing from the selected archive, the Workshop runtime and the current GitHub runtime.'
}

function Show-InstallPreview {
    param([hashtable]$Paths, [object]$Package)
    Write-Heading 'Installation preview'
    Write-Host "Game folder : $($Paths.Root)"
    Write-Host "Build       : $($Package.BuildName)"
    Write-Host "Source      : $($Package.DownloadUrl)"
    Write-Host "Required tag: $($Package.Tag)"
    Write-Host "Asset       : $($Package.AssetName)"
    Write-Host "Size        : $([Math]::Round($Package.AssetSize / 1MB, 2)) MB"
    Write-Host "SHA-256     : $($Package.Sha256)"
    Write-Host ''
    Write-Host 'The helper will:'
    Write-Host '  - move the current GitHub UE4SS runtime and proxy into a backup, if present;'
    Write-Host '  - build a clean runtime from the selected archive instead of overlaying old files;'
    Write-Host '  - preserve existing mods and UE4SS-settings.ini;'
    Write-Host '  - merge existing Workshop UE4SS mods into the clean runtime;'
    Write-Host '  - replace the Workshop Mods directory with a verified junction;'
    Write-Host '  - verify MemberVariableLayout.ini and copy the Workshop file if needed;'
    Write-Host '  - disable the Workshop UE4SS.dll without deleting it.'
}

function Install-ExperimentalPackage {
    param([hashtable]$Paths, [object]$Package)
    Assert-PalworldClosed
    if (-not (Test-Path -LiteralPath $Paths.WorkshopRoot -PathType Container)) { throw "Workshop UE4SS is not installed: $($Paths.WorkshopRoot)" }
    $existingDisabledDll = Get-ChildItem -LiteralPath $Paths.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf) -and $null -eq $existingDisabledDll) {
        throw 'No active or previously disabled Workshop UE4SS.dll was found. Reinstall or update the Workshop mod first.'
    }
    if (Test-IsJunction $Paths.WorkshopMods) { Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods }
    elseif ((Test-Path -LiteralPath $Paths.WorkshopMods) -and -not (Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container)) {
        throw "The Workshop Mods path exists but is not a directory: $($Paths.WorkshopMods)"
    }
    $backup = New-BackupRoot $Paths 'Install'
    $state = @{
        JunctionCreated=$false
        WorkshopMoved=$false
        WorkshopDllDisabled=$false
        HadGitHubRoot=(Test-Path -LiteralPath $Paths.GitHubRoot -PathType Container)
        HadProxy=(Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf)
        HadJunction=(Test-IsJunction $Paths.WorkshopMods)
        OldRuntimeMoved=$false
        OldProxyMoved=$false
        NewRuntimeInstalled=$false
        NewProxyInstalled=$false
    }
    try {
        Save-BackupManifest $backup 'Install' @{ sourceBuild=$Package.BuildKey; sourceRepository=$Package.Repository; sourceTag=$Package.Tag; sourceAsset=$Package.AssetName; sourceSha256=$Package.Sha256 }

        $preparedRoot = Join-Path $backup 'PreparedGitHubRuntime'
        $preparedMods = Join-Path $preparedRoot 'Mods'
        New-Item -ItemType Directory -Path $preparedRoot | Out-Null
        if ($state.HadGitHubRoot) {
            Copy-Directory $Paths.GitHubMods $preparedMods
            $existingSettings = Join-Path $Paths.GitHubRoot 'UE4SS-settings.ini'
            if (Test-Path -LiteralPath $existingSettings -PathType Leaf) {
                Copy-Item -LiteralPath $existingSettings -Destination (Join-Path $preparedRoot 'UE4SS-settings.ini') -Force
            }
        }
        if ((Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container) -and -not (Test-IsJunction $Paths.WorkshopMods)) {
            Copy-Directory $Paths.WorkshopMods $preparedMods
        }
        Copy-Ue4ssOverlay $Package.Layout.Ue4ssSource $preparedRoot
        $layoutResult = Ensure-PreparedMemberVariableLayout $Paths $preparedRoot
        Write-Host "MemberVariableLayout.ini: $layoutResult" -ForegroundColor DarkGray
        Save-RuntimeRecord (Join-Path $preparedRoot 'Palworld-UE4SS-Helper-runtime.json') $Package 'WindowsSteamClient'
        if (-not (Test-Path -LiteralPath (Join-Path $preparedRoot 'UE4SS.dll') -PathType Leaf)) {
            throw 'The prepared UE4SS runtime does not contain UE4SS.dll.'
        }

        if ($state.HadGitHubRoot) {
            Move-Item -LiteralPath $Paths.GitHubRoot -Destination (Join-Path $backup 'PreviousGitHubRuntime')
            $state.OldRuntimeMoved = $true
        }
        if ($state.HadProxy) {
            Move-Item -LiteralPath $Paths.GitHubProxy -Destination (Join-Path $backup 'Previous-dwmapi.dll')
            $state.OldProxyMoved = $true
        }
        Move-Item -LiteralPath $preparedRoot -Destination $Paths.GitHubRoot
        $state.NewRuntimeInstalled = $true
        Copy-Item -LiteralPath $Package.Layout.ProxySource -Destination $Paths.GitHubProxy -Force
        $state.NewProxyInstalled = $true
        if (-not (Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf) -or
            -not (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf) -or
            -not (Test-Path -LiteralPath $Paths.GitHubLayout -PathType Leaf)) {
            throw 'UE4SS runtime verification failed after copying.'
        }

        if (Test-IsJunction $Paths.WorkshopMods) {
            Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
        } elseif (Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container) {
            Move-Item -LiteralPath $Paths.WorkshopMods -Destination (Join-Path $backup 'OriginalWorkshopMods')
            $state.WorkshopMoved = $true
            New-Item -ItemType Junction -Path $Paths.WorkshopMods -Target $Paths.GitHubMods | Out-Null
            $state.JunctionCreated = $true
            Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
        } else {
            New-Item -ItemType Directory -Path $Paths.GitHubMods -Force | Out-Null
            New-Item -ItemType Junction -Path $Paths.WorkshopMods -Target $Paths.GitHubMods | Out-Null
            $state.JunctionCreated = $true
            Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
        }

        if (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf) {
            $disabled = "$($Paths.WorkshopDll).workshop-disabled"
            if (Test-Path -LiteralPath $disabled) { $disabled += ".$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
            Move-Item -LiteralPath $Paths.WorkshopDll -Destination $disabled
            $state.WorkshopDllDisabled = $true
            $state.DisabledDllPath = $disabled
        }
        Write-Host ''
        Write-Host 'Experimental UE4SS installation completed successfully.' -ForegroundColor Green
        Write-Host "Backup: $backup"
        Write-Host "Installed SHA-256: $($Package.Sha256)"
        try {
            Write-Heading 'Automatic Workshop mod synchronization'
            $syncResults = @(Get-SyncResults $Paths $true)
            if ($syncResults.Count -eq 0) { Write-Host 'No applicable Workshop UE4SS mods were found.' }
            else { $syncResults | Sort-Object Package | Format-Table -AutoSize -Wrap }
        } catch {
            Write-Host "Installation succeeded, but automatic mod synchronization was skipped: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host 'You can retry it later from the main menu.' -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Attempting to restore the previous state...' -ForegroundColor Yellow
        try {
            if ($state.JunctionCreated -and (Test-IsJunction $Paths.WorkshopMods)) { Remove-VerifiedJunction $Paths.WorkshopMods $Paths.GitHubMods }
            if ($state.WorkshopMoved -and (Test-Path -LiteralPath (Join-Path $backup 'OriginalWorkshopMods'))) {
                Move-Item -LiteralPath (Join-Path $backup 'OriginalWorkshopMods') -Destination $Paths.WorkshopMods
            }
            if ($state.WorkshopDllDisabled -and (Test-Path -LiteralPath $state.DisabledDllPath) -and -not (Test-Path -LiteralPath $Paths.WorkshopDll)) {
                Move-Item -LiteralPath $state.DisabledDllPath -Destination $Paths.WorkshopDll
            }
            if ($state.NewRuntimeInstalled -and (Test-Path -LiteralPath $Paths.GitHubRoot -PathType Container)) {
                Move-Item -LiteralPath $Paths.GitHubRoot -Destination (Join-Path $backup 'FailedPartialGitHubRuntime')
            }
            if ($state.OldRuntimeMoved -and (Test-Path -LiteralPath (Join-Path $backup 'PreviousGitHubRuntime') -PathType Container)) {
                Move-Item -LiteralPath (Join-Path $backup 'PreviousGitHubRuntime') -Destination $Paths.GitHubRoot
            }
            if ($state.NewProxyInstalled -and (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf)) {
                Move-Item -LiteralPath $Paths.GitHubProxy -Destination (Join-Path $backup 'Failed-dwmapi.dll') -Force
            }
            if ($state.OldProxyMoved -and (Test-Path -LiteralPath (Join-Path $backup 'Previous-dwmapi.dll') -PathType Leaf)) {
                Move-Item -LiteralPath (Join-Path $backup 'Previous-dwmapi.dll') -Destination $Paths.GitHubProxy
            }
            Write-Host 'Previous state restored. Failed files were retained in the backup.' -ForegroundColor Yellow
        } catch {
            Write-Host "Automatic rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Do not launch Palworld. Inspect the backup: $backup" -ForegroundColor Red
        }
        throw 'The installation was not completed.'
    }
}

function Get-SafePackageName {
    param([object]$Value, [string]$InfoPath)
    $name = [string]$Value
    $baseName = ($name -split '\.', 2)[0]
    if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.', '..') -or
        $name -cne $name.Trim() -or $name.EndsWith('.') -or
        $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $name.Contains('\') -or $name.Contains('/') -or [IO.Path]::IsPathRooted($name) -or
        $baseName -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        throw "Unsafe or invalid PackageName in '$InfoPath': '$name'"
    }
    return $name
}

function Test-IsServerRule {
    param([object]$Rule)
    if ($null -eq $Rule) { return $false }
    $property = $Rule.PSObject.Properties['IsServer']
    return $null -ne $property -and $property.Value -is [bool] -and [bool]$property.Value
}

function Get-Ue4ssModsTxtState {
    param([string]$ModsRoot, [string]$Package)
    $modsTxt = Join-Path $ModsRoot 'mods.txt'
    if (-not (Test-Path -LiteralPath $modsTxt -PathType Leaf)) { return 'NotListed' }
    try {
        $escaped = [regex]::Escape($Package)
        $state = 'NotListed'
        foreach ($line in Get-Content -LiteralPath $modsTxt -ErrorAction Stop) {
            if ([string]$line -match "^(?i)\s*$escaped\s*:\s*([01])(?:\s*(?:;|#).*)?$") {
                $state = if ($Matches[1] -eq '1') { 'ModsTxtEnabled' } else { 'ModsTxtDisabled' }
            }
        }
        return $state
    } catch { return 'Unknown' }
}

function Get-Ue4ssModActivationState {
    param([string]$ModsRoot, [string]$Package)
    $modRoot = Join-Path $ModsRoot $Package
    if (Test-Path -LiteralPath (Join-Path $modRoot 'enabled.txt') -PathType Leaf) { return 'EnabledFile' }
    $modsTxtState = Get-Ue4ssModsTxtState $ModsRoot $Package
    if ($modsTxtState -in @('ModsTxtEnabled','ModsTxtDisabled','Unknown')) { return $modsTxtState }
    return 'NotEnabled'
}

function Get-SyncResults {
    param([hashtable]$Paths, [bool]$Apply)
    foreach ($required in @($Paths.ManagedRoot, $Paths.GitHubMods, $Paths.WorkshopMods)) {
        if (-not (Test-Path -LiteralPath $required -PathType Container)) { throw "Required directory not found: $required" }
    }
    Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
    $internal = @('UE4SSExperimentalPW','BPML_GenericFunctions','BPModLoaderMod','CheatManagerEnablerMod','ConsoleCommandsMod','ConsoleEnablerMod','Keybinds','LineTraceMod','SplitScreenMod','PalSchema','shared')
    $results = foreach ($managed in Get-ChildItem -LiteralPath $Paths.ManagedRoot -Directory) {
        $infoPath = Join-Path $managed.FullName 'Info.json'
        if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) { continue }
        try {
            $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
            $types = @($info.InstallRule | ForEach-Object Type | Select-Object -Unique)
            $package = Get-SafePackageName $info.PackageName $infoPath
            if ('Lua' -notin $types -or $package -in $internal) { continue }
            $destination = Join-Path $Paths.GitHubMods $package
            $mainLua = Join-Path $destination 'Scripts\main.lua'
            $mainDll = Join-Path $destination 'dlls\main.dll'
            $enabled = Join-Path $destination 'enabled.txt'
            if (-not (Test-Path -LiteralPath $mainLua -PathType Leaf) -and -not (Test-Path -LiteralPath $mainDll -PathType Leaf)) {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Content not deployed yet; launch Palworld once' }; continue
            }
            $activation = Get-Ue4ssModActivationState $Paths.GitHubMods $package
            if ($activation -eq 'EnabledFile') {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Already enabled' }; continue
            }
            if ($activation -eq 'ModsTxtEnabled') {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Enabled by mods.txt' }; continue
            }
            if ($activation -eq 'ModsTxtDisabled') {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Disabled in mods.txt; left unchanged' }; continue
            }
            if ($Apply) { New-Item -ItemType File -Path $enabled -ErrorAction Stop | Out-Null }
            [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result=$(if ($Apply) {'enabled.txt created'} else {'Would create enabled.txt'}) }
        } catch { [pscustomobject]@{ Mod=$managed.Name; Package=''; Result="Skipped: $($_.Exception.Message)" } }
    }
    return @($results)
}

function Invoke-Synchronization {
    param([hashtable]$Paths)
    Write-Heading 'Synchronization preview'
    $layoutPreview = Ensure-MemberVariableLayout $Paths
    Write-Host "MemberVariableLayout.ini: $($layoutPreview.Result)"
    Write-Host ''
    $preview = @(Get-SyncResults $Paths $false)
    if ($preview.Count -eq 0) { Write-Host 'No applicable Workshop UE4SS mods were found.' }
    else { $preview | Sort-Object Package | Format-Table -AutoSize -Wrap }
    $missingEnabled = @($preview | Where-Object Result -eq 'Would create enabled.txt').Count -gt 0
    if (-not $layoutPreview.Pending -and -not $missingEnabled) { return }
    if (-not (Read-YesNo 'Apply the pending synchronization changes now?')) { return }
    Assert-PalworldClosed
    Write-Heading 'Synchronization result'
    $layoutResult = Ensure-MemberVariableLayout $Paths -Apply
    Write-Host "MemberVariableLayout.ini: $($layoutResult.Result)"
    $results = @(Get-SyncResults $Paths $true)
    if ($results.Count -gt 0) { $results | Sort-Object Package | Format-Table -AutoSize -Wrap }
}

function Show-Status {
    param([hashtable]$Paths)
    Write-Heading 'Current status'
    $junction = Test-IsJunction $Paths.WorkshopMods
    $junctionTarget = 'Not applicable'
    if ($junction) {
        try { Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods; $junctionTarget = 'Correct' }
        catch { $junctionTarget = "Incorrect: $($_.Exception.Message)" }
    }
    $proxy = Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf
    $runtime = Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf
    $workshopActive = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    $disabledWorkshop = $null -ne (Get-ChildItem -LiteralPath $Paths.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
    $layout = Test-Path -LiteralPath $Paths.GitHubLayout -PathType Leaf
    $log = Test-Path -LiteralPath (Join-Path $Paths.GitHubRoot 'UE4SS.log') -PathType Leaf
    $externalActive = $proxy -and $runtime

    Write-AuditValue 'Game folder' $Paths.Root
    Write-AuditValue 'GitHub proxy present' $proxy $(if ($proxy) { 'Good' } elseif ($runtime) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'GitHub runtime present' $runtime $(if ($runtime) { 'Good' } elseif ($proxy) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'Workshop DLL active' $workshopActive $(if ($externalActive -and $workshopActive) { 'Bad' } elseif ($workshopActive -or $externalActive) { 'Good' } else { 'Bad' })
    Write-AuditValue 'Disabled Workshop DLL found' $disabledWorkshop $(if ($externalActive -and $disabledWorkshop) { 'Good' } elseif ($externalActive) { 'Warning' } else { 'Neutral' })
    Write-AuditValue 'Mods junction present' $junction $(if ($externalActive -and $junction) { 'Good' } elseif ($externalActive) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'Junction target' $junctionTarget $(if ($junctionTarget -eq 'Correct') { 'Good' } elseif ($junction) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'MemberVariableLayout.ini present' $layout $(if ($externalActive -and $layout) { 'Good' } elseif ($externalActive) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'UE4SS log present' $log $(if ($log) { 'Good' } else { 'Neutral' })
}

function Show-RestorePreview {
    param([hashtable]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.GitHubMods -PathType Container)) { throw "GitHub Mods directory not found: $($Paths.GitHubMods)" }
    Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
    $disabled = Get-ChildItem -LiteralPath $Paths.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf) -and $null -eq $disabled) { throw 'No Workshop UE4SS.dll was found. Reinstall or update the Workshop mod before restoring.' }
    Write-Heading 'Restoration preview'
    Write-Host 'The helper will:'
    Write-Host '  - copy all current GitHub UE4SS mods into a timestamped backup;'
    Write-Host '  - remove only the verified Workshop Mods junction;'
    Write-Host '  - restore the mods into a normal Workshop Mods directory;'
    Write-Host '  - reactivate the Workshop UE4SS.dll;'
    Write-Host '  - move the GitHub runtime and proxy into the backup.'
    return $disabled
}

function Restore-WorkshopRuntime {
    param([hashtable]$Paths, [object]$DisabledDll)
    Assert-PalworldClosed
    $backup = New-BackupRoot $Paths 'Restore'
    $backupMods = Join-Path $backup 'Mods'
    $state = @{ JunctionRemoved=$false; WorkshopDirectoryCreated=$false; WorkshopDllRestored=$false; RuntimeMoved=$false; ProxyMoved=$false }
    try {
        Copy-Directory $Paths.GitHubMods $backupMods
        Save-BackupManifest $backup 'Restore' @{}
        Remove-VerifiedJunction $Paths.WorkshopMods $Paths.GitHubMods
        $state.JunctionRemoved = $true
        New-Item -ItemType Directory -Path $Paths.WorkshopMods | Out-Null
        $state.WorkshopDirectoryCreated = $true
        Copy-Directory $backupMods $Paths.WorkshopMods
        if (-not (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf)) {
            Move-Item -LiteralPath $DisabledDll.FullName -Destination $Paths.WorkshopDll
            $state.WorkshopDllRestored = $true
            $state.DisabledDllPath = $DisabledDll.FullName
        }
        if (Test-Path -LiteralPath $Paths.GitHubRoot -PathType Container) {
            Move-Item -LiteralPath $Paths.GitHubRoot -Destination (Join-Path $backup 'RemovedGitHubRuntime')
            $state.RuntimeMoved = $true
        }
        if (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf) {
            Move-Item -LiteralPath $Paths.GitHubProxy -Destination (Join-Path $backup 'Removed-dwmapi.dll')
            $state.ProxyMoved = $true
        }
        Write-Host ''
        Write-Host 'Workshop UE4SS was restored successfully.' -ForegroundColor Green
        Write-Host "GitHub runtime backup: $backup"
    } catch {
        Write-Host "Restoration failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Attempting to restore the GitHub workaround...' -ForegroundColor Yellow
        try {
            if ($state.RuntimeMoved -and (Test-Path -LiteralPath (Join-Path $backup 'RemovedGitHubRuntime'))) {
                Move-Item -LiteralPath (Join-Path $backup 'RemovedGitHubRuntime') -Destination $Paths.GitHubRoot
            }
            if ($state.ProxyMoved -and (Test-Path -LiteralPath (Join-Path $backup 'Removed-dwmapi.dll'))) {
                Move-Item -LiteralPath (Join-Path $backup 'Removed-dwmapi.dll') -Destination $Paths.GitHubProxy
            }
            if ($state.WorkshopDllRestored -and (Test-Path -LiteralPath $Paths.WorkshopDll)) {
                Move-Item -LiteralPath $Paths.WorkshopDll -Destination $state.DisabledDllPath
            }
            if ($state.WorkshopDirectoryCreated -and (Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container)) {
                Move-Item -LiteralPath $Paths.WorkshopMods -Destination (Join-Path $backup 'FailedWorkshopMods')
            }
            if ($state.JunctionRemoved) {
                New-Item -ItemType Directory -Path $Paths.GitHubMods -Force | Out-Null
                New-Item -ItemType Junction -Path $Paths.WorkshopMods -Target $Paths.GitHubMods | Out-Null
                Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods
            }
            Write-Host 'The GitHub workaround was restored. Failed files remain in the backup.' -ForegroundColor Yellow
        } catch {
            Write-Host "Automatic rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Do not launch Palworld. Inspect the backup: $backup" -ForegroundColor Red
        }
        throw 'The Workshop restoration was not completed.'
    }
}

function Get-ClientModDiagnostics {
    param([hashtable]$Paths)

    if (-not (Test-Path -LiteralPath $Paths.ManagedRoot -PathType Container)) { return @() }

    $packages = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($managed in Get-ChildItem -LiteralPath $Paths.ManagedRoot -Directory -ErrorAction SilentlyContinue) {
        $infoPath = Join-Path $managed.FullName 'Info.json'
        if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) { continue }
        try {
            $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
            $package = Get-SafePackageName $info.PackageName $infoPath
            [void]$packages.Add($package)
            $entries.Add([pscustomobject]@{ Managed=$managed; Info=$info; Package=$package; InfoPath=$infoPath })
        } catch {
            $entries.Add([pscustomobject]@{ Managed=$managed; Info=$null; Package=$managed.Name; InfoPath=$infoPath; Error=$_.Exception.Message })
        }
    }

    $results = foreach ($entry in $entries) {
        if ($null -eq $entry.Info) {
            [pscustomobject]@{
                Mod=$entry.Managed.Name
                Package=$entry.Package
                Types='Unknown'
                ServerRule='Unknown'
                Dependencies='Unknown'
                RuntimeState="Invalid Info.json: $($entry.Error)"
            }
            continue
        }

        $rules = @($entry.Info.InstallRule)
        $types = @($rules | ForEach-Object { [string]$_.Type } | Where-Object { $_ } | Sort-Object -Unique)
        $hasServerRule = @($rules | Where-Object { Test-IsServerRule $_ }).Count -gt 0
        $dependencies = @($entry.Info.Dependencies | ForEach-Object { [string]$_ } | Where-Object { $_ })
        $missing = @($dependencies | Where-Object { -not $packages.Contains($_) })

        $runtimeState = 'Not an UE4SS Lua package'
        if ('Lua' -in $types) {
            $destination = Join-Path $Paths.GitHubMods $entry.Package
            $mainLua = Join-Path $destination 'Scripts\main.lua'
            $mainDll = Join-Path $destination 'dlls\main.dll'
            if (-not (Test-Path -LiteralPath $mainLua -PathType Leaf) -and -not (Test-Path -LiteralPath $mainDll -PathType Leaf)) {
                $runtimeState = 'Content not deployed'
            } else {
                $runtimeState = switch (Get-Ue4ssModActivationState $Paths.GitHubMods $entry.Package) {
                    'EnabledFile' { 'Enabled (enabled.txt)' }
                    'ModsTxtEnabled' { 'Enabled (mods.txt)' }
                    'ModsTxtDisabled' { 'Disabled in mods.txt' }
                    'Unknown' { 'Activation state unknown' }
                    default { 'Deployed but not enabled' }
                }
            }
        } elseif ('PalSchema' -in $types) {
            $schemaPath = Join-Path $Paths.GitHubMods (Join-Path 'PalSchema\mods' $entry.Package)
            $runtimeState = if (Test-Path -LiteralPath $schemaPath -PathType Container) { 'PalSchema content deployed' } else { 'PalSchema content not deployed' }
        }

        [pscustomobject]@{
            Mod=[string]$entry.Info.ModName
            Package=$entry.Package
            Types=$(if ($types.Count) { $types -join ', ' } else { 'None' })
            ServerRule=$(if ($hasServerRule) { 'Yes' } else { 'No' })
            Dependencies=$(if ($missing.Count) { "Missing: $($missing -join ', ')" } elseif ($dependencies.Count) { 'Present' } else { 'No declared dependencies' })
            RuntimeState=$runtimeState
        }
    }
    return @($results)
}

function Test-ClientDiagnosticAliasMatch {
    param([string]$Text, [string]$Alias)
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Alias) -or $Alias.Length -lt 4) { return $false }
    if ($Alias -in @('Error','Fatal','Client','Palworld','Windows','Win64','UE4SS','dwmapi','Scripts','Content','main','Mods')) { return $false }
    $pattern = '(?i)(?<![A-Za-z0-9_])' + [regex]::Escape($Alias) + '(?![A-Za-z0-9_])'
    return [regex]::IsMatch($Text, $pattern)
}

function Get-ClientLogAnalysis {
    param([hashtable]$Paths)
    $logCandidates = @(
        (Join-Path $Paths.GitHubRoot 'UE4SS.log'),
        (Join-Path $Paths.WorkshopRoot 'UE4SS.log')
    )
    $log = $logCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($null -eq $log) { return [pscustomobject]@{ Log=$null; Errors=@(); Suspects=@(); Unmapped=@() } }

    $tail = @(Get-Content -LiteralPath $log -Tail 2500 -ErrorAction Stop)
    $normalized = [regex]::Replace(($tail -join "`n"), '(?=\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})', "`n")
    $lines = @($normalized -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $sessionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)Starting mods \(from mods\.txt') { $sessionStart = [Math]::Max(0, $i - 80) }
    }
    if ($sessionStart -ge 0) { $lines = @($lines | Select-Object -Skip $sessionStart) }

    $mods = @(Get-ClientModDiagnostics $Paths)
    $errorPattern = '(?i)(\[(?:error|fatal)\]|\berror\b|\bfatal\b|\bexception\b|\bfailed\b|\bfailure\b|\bcrash(?:ed)?\b|\bcould not\b|\bunable to\b|timed out|access violation|stack traceback)'
    $errors = New-Object System.Collections.Generic.List[object]
    $unmapped = New-Object System.Collections.Generic.List[object]
    $suspectMap = @{}
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch $errorPattern) { continue }
        $record = [pscustomobject]@{ Index=$i; Line=$lines[$i] }
        $errors.Add($record)
        $matches = @($mods | Where-Object {
            (Test-ClientDiagnosticAliasMatch $record.Line $_.Package) -or
            (Test-ClientDiagnosticAliasMatch $record.Line $_.Mod)
        })
        if ($matches.Count -eq 0) { $unmapped.Add($record); continue }
        foreach ($mod in $matches) {
            if (-not $suspectMap.ContainsKey($mod.Package)) {
                $suspectMap[$mod.Package] = [pscustomobject]@{
                    Mod=$mod.Mod; Package=$mod.Package; Errors=0;
                    Lines=(New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase))
                }
            }
            $entry = $suspectMap[$mod.Package]
            $entry.Errors++
            $cleanLine = [regex]::Replace($record.Line, '^\[\d{4}-\d{2}-\d{2}\s+[^\]]+\]\s*', '')
            [void]$entry.Lines.Add($cleanLine)
        }
    }
    $suspects = @($suspectMap.Values | ForEach-Object {
        [pscustomobject]@{ Mod=$_.Mod; Package=$_.Package; Errors=$_.Errors; Lines=@($_.Lines) }
    } | Sort-Object @{Expression='Errors';Descending=$true}, Package)
    return [pscustomobject]@{ Log=$log; Errors=$errors.ToArray(); Suspects=$suspects; Unmapped=$unmapped.ToArray() }
}

function Show-ClientLogAnalysis {
    param([hashtable]$Paths)
    Write-Heading 'Recent UE4SS log diagnosis'
    $analysis = Get-ClientLogAnalysis $Paths
    if ($null -eq $analysis.Log) {
        Write-Host 'No UE4SS.log file was found. Launch the game once, reproduce the problem, then run this report again.' -ForegroundColor Yellow
        return
    }
    Write-Host "Log: $($analysis.Log)" -ForegroundColor DarkGray
    if ($analysis.Errors.Count -eq 0) {
        Write-Host 'No obvious error keywords were found in the current log session.' -ForegroundColor Green
        return
    }
    if ($analysis.Suspects.Count -gt 0) {
        Write-Host ''
        Write-Host 'Mods directly named by errors:' -ForegroundColor Yellow
        $analysis.Suspects | Select-Object Mod,Package,Errors | Format-Table -AutoSize -Wrap
        Write-Host 'These errors belong to the named mod, although they do not necessarily mean the whole mod stopped working.' -ForegroundColor DarkGray
        foreach ($suspect in $analysis.Suspects) {
            Write-Host ''
            Write-Host "$($suspect.Mod) [$($suspect.Package)]" -ForegroundColor Yellow
            foreach ($line in @($suspect.Lines | Select-Object -First 8)) {
                $displayLine = [string]$line
                if ($displayLine.Length -gt 900) { $displayLine = $displayLine.Substring(0, 900) + '...' }
                Write-Host "  $displayLine" -ForegroundColor Red
            }
        }
    }
    if ($analysis.Unmapped.Count -gt 0) {
        Write-Host ''
        Write-Host 'Other errors with no reliable installed-mod match:' -ForegroundColor Yellow
        foreach ($error in @($analysis.Unmapped | Select-Object -First 12)) {
            $displayLine = [string]$error.Line
            if ($displayLine.Length -gt 900) { $displayLine = $displayLine.Substring(0, 900) + '...' }
            Write-Host "  $displayLine" -ForegroundColor Red
        }
    }
}

function Show-MultiplayerDiagnostics {
    param([hashtable]$Paths)

    Write-Heading 'Client and co-op diagnostics'
    Write-Host 'This report does not change any files.' -ForegroundColor DarkGray
    Write-Host ''

    $externalDll = Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf
    $externalProxy = Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf
    $workshopDll = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    $externalActive = $externalDll -and $externalProxy

    $junctionState = 'Missing'
    if (Test-IsJunction $Paths.WorkshopMods) {
        try { Assert-JunctionTarget $Paths.WorkshopMods $Paths.GitHubMods; $junctionState = 'Correct' }
        catch { $junctionState = "Incorrect: $($_.Exception.Message)" }
    } elseif (Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container) {
        $junctionState = 'Normal directory'
    }

    $twoRuntimes = $externalActive -and $workshopDll
    $layout = Test-Path -LiteralPath $Paths.GitHubLayout -PathType Leaf
    Write-AuditValue 'External UE4SS runtime active' $externalActive $(if ($externalActive) { 'Good' } elseif ($workshopDll) { 'Neutral' } else { 'Bad' })
    Write-AuditValue 'External UE4SS.dll present' $externalDll $(if ($externalDll -eq $externalProxy) { $(if ($externalDll) { 'Good' } else { 'Neutral' }) } else { 'Bad' })
    Write-AuditValue 'dwmapi.dll proxy present' $externalProxy $(if ($externalDll -eq $externalProxy) { $(if ($externalProxy) { 'Good' } else { 'Neutral' }) } else { 'Bad' })
    Write-AuditValue 'Workshop UE4SS.dll active' $workshopDll $(if ($twoRuntimes) { 'Bad' } elseif ($workshopDll -or $externalActive) { 'Good' } else { 'Bad' })
    Write-AuditValue 'Two UE4SS runtimes active' $twoRuntimes $(if ($twoRuntimes) { 'Bad' } else { 'Good' })
    Write-AuditValue 'Workshop Mods path' $junctionState $(if ($junctionState -eq 'Correct') { 'Good' } elseif ($externalActive) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'MemberVariableLayout.ini present' $layout $(if ($externalActive -and $layout) { 'Good' } elseif ($externalActive) { 'Bad' } else { 'Neutral' })

    if ($externalActive -and $workshopDll) {
        Write-Host 'CRITICAL: Both UE4SS runtimes appear active. This can cause an immediate crash.' -ForegroundColor Red
    } elseif ($externalDll -xor $externalProxy) {
        Write-Host 'WARNING: The external runtime is incomplete; UE4SS.dll and dwmapi.dll must be present together.' -ForegroundColor Yellow
    }

    Write-Heading 'Installed Workshop mod report'
    $mods = @(Get-ClientModDiagnostics $Paths)
    if ($mods.Count) { Write-ClientModReport $mods }
    else { Write-Host 'No deployed Workshop metadata was found.' }

    Show-ClientLogAnalysis $Paths

    Write-Host ''
    Write-Host 'A server rule only means that the package declares server-side installation support.' -ForegroundColor DarkGray
    Write-Host 'It does not guarantee multiplayer compatibility. If UE4SS alone works, re-enable additional mods one at a time.' -ForegroundColor DarkGray
}

function Select-ExperimentalBuild {
    while ($true) {
        Clear-Host
        Write-Heading 'Choose the UE4SS build to install'
        Write-Host '1. Palworld-specific Experimental build (recommended)'
        Write-Host '   Best compatibility in the tested Palworld client/server combinations.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '2. Official Experimental build'
        Write-Host '   Newest upstream Experimental version; use it as an alternative when needed.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '3. Return to the main menu'
        Write-Host ''
        switch ((Read-Host 'Choose a build').Trim()) {
            '1' { return $script:Builds.Palworld }
            '2' { return $script:Builds.Official }
            '3' { return $null }
            default { }
        }
    }
}

function Invoke-AutomaticInstall {
    $build = Select-ExperimentalBuild
    if ($null -eq $build) { Write-Host 'Installation cancelled. No game files were changed.'; return }
    $paths = Get-Paths
    $package = $null
    try {
        $package = Get-ExperimentalPackage $build
        Show-InstallPreview $paths $package
        Write-Host ''
        Write-Host 'Only the reviewed archive for the selected Experimental build is accepted. Stable, DEV and every other asset are excluded.' -ForegroundColor Yellow
        if (Read-YesNo 'Install or update Experimental UE4SS now?') { Install-ExperimentalPackage $paths $package }
        else { Write-Host 'Installation cancelled. No game files were changed.' }
    } finally {
        if ($null -ne $package -and (Test-Path -LiteralPath $package.TempRoot)) { Remove-Item -LiteralPath $package.TempRoot -Recurse -Force }
    }
}

function Initialize-GameRoot {
    if (Test-GameRoot $script:GameRoot) { return }
    $found = @(Find-PalworldInstallations)
    if ($found.Count -eq 1) { $script:GameRoot = $found[0] }
}

function Write-TestedRuntimeCombinations {
    Write-Heading 'TESTED CLIENT / SERVER COMBINATIONS'
    Write-Host 'Best tested default: Palworld-specific Experimental on both client and server.' -ForegroundColor Green
    Write-Host ''
    Write-Host ('{0,-29} {1,-29} {2}' -f 'Client runtime','Server runtime','Observed result') -ForegroundColor Cyan
    Write-Host ('{0,-29} {1,-29} {2}' -f ('-' * 28),('-' * 28),('-' * 24)) -ForegroundColor DarkCyan
    $rows = @(
        [pscustomobject]@{ Client='Palworld-specific'; Server='Palworld-specific'; Result='Best tested combination'; Color='Green' },
        [pscustomobject]@{ Client='Palworld-specific'; Server='Official Experimental'; Result='Tested mods worked'; Color='Green' },
        [pscustomobject]@{ Client='Palworld-specific'; Server='Workshop UE4SS'; Result='Tested mods worked'; Color='Green' },
        [pscustomobject]@{ Client='Official Experimental'; Server='Palworld-specific'; Result='Tested mods worked'; Color='Green' },
        [pscustomobject]@{ Client='Official Experimental'; Server='Official Experimental'; Result='Partial: PalSchema worked; direct Lua did not'; Color='Yellow' },
        [pscustomobject]@{ Client='Official Experimental'; Server='Workshop UE4SS'; Result='Partial: PalSchema worked; direct Lua did not'; Color='Yellow' }
    )
    foreach ($row in $rows) {
        Write-Host ('{0,-29} {1,-29} {2}' -f $row.Client,$row.Server,$row.Result) -ForegroundColor $row.Color
    }
    Write-Host ''
    Write-Host 'Specifically, Bigger Palbox (PalSchema) worked while Infinite Weight In Camp (direct Lua) did not.' -ForegroundColor DarkGray
    Write-Host 'These are observations from the tested mod set, not universal compatibility guarantees.' -ForegroundColor DarkGray
}

function Show-ClientInstructions {
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host '                     INSTRUCTIONS / READ ME' -ForegroundColor Yellow
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'FIRST INSTALLATION' -ForegroundColor Cyan
    Write-Host '  1. Close Palworld completely.'
    Write-Host '  2. Use option 1 and install the Palworld-specific Experimental build.'
    Write-Host '  3. Read the preview and confirm only when the detected folder is correct.'
    Write-Host '  4. Use option 3 to check the finished installation.'
    Write-Host '  5. Start Palworld and test your mods.'
    Write-Host ''
    Write-Host 'AFTER SUBSCRIBING TO NEW WORKSHOP MODS' -ForegroundColor Cyan
    Write-Host '  Let Palworld deploy them, close the game, then use option 2 to synchronize them.'
    Write-Host ''
    Write-Host 'IF SOMETHING STOPS WORKING' -ForegroundColor Cyan
    Write-Host '  Use option 4 for a read-only diagnostic. Try the Palworld-specific build when a mod behaves differently with the official build.'
    Write-Host '  Option 5 restores the normal Workshop runtime. It does not unsubscribe from Workshop items.'
    Write-Host ''
    Write-Host 'The helper does not require administrator rights. File-changing operations create timestamped backups.' -ForegroundColor DarkGray
    Write-TestedRuntimeCombinations
    Write-Heading 'CREDITS AND OFFICIAL DOWNLOAD'
    Write-Host 'Original scripts and helpers by:' -ForegroundColor Cyan
    Write-Host '  ZdradaKali (GitHub): https://github.com/ZdradaKali'
    Write-Host '  Yani Neco (Steam)  : https://steamcommunity.com/id/0peraGX/'
    Write-Host '  hess_ch (Discord)'
    Write-Host 'Three names, still the same asshole.' -ForegroundColor DarkMagenta
    Write-Host 'Official project: https://github.com/ZdradaKali/Palworld-UE4SS-Workshop-Helper' -ForegroundColor Green
    Write-Host ''
    Write-Host 'SECURITY: Copies obtained from any other source are unverified and may have been modified.' -ForegroundColor Yellow
    Write-Host 'Do not run an unverified copy; download a fresh release from the official GitHub project.' -ForegroundColor Yellow
}

function Invoke-MenuAction {
    param([scriptblock]$Action)
    Clear-Host
    try { & $Action }
    catch { Write-Host ''; Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    Wait-ForMenu
}

### CLIENT HELPER ENTRYPOINT ###
try {
    $Host.UI.RawUI.WindowTitle = "Palworld UE4SS Workshop Helper v$($script:HelperVersion)"
    Initialize-GameRoot
    $finished = $false
    while (-not $finished) {
        Clear-Host
        Write-Host "Palworld UE4SS Workshop Helper v$($script:HelperVersion)" -ForegroundColor Cyan
        Write-Host 'Experimental UE4SS - Windows Steam client version' -ForegroundColor DarkGray
        Write-Host 'By ZdradaKali (GitHub) / Yani Neco (Steam) / hess_ch (Discord)' -ForegroundColor DarkMagenta
        Write-Host ''
        if (Test-GameRoot $script:GameRoot) {
            $homePaths = Get-Paths
            $runtime = Get-InstalledRuntimeSummary $homePaths
            Write-Host "Selected installation: $($script:GameRoot)" -ForegroundColor DarkGray
            Write-Host 'Installed UE4SS: ' -NoNewline -ForegroundColor DarkGray
            Write-Host $runtime.Text -ForegroundColor $runtime.Color
            Write-Host ''
        } else {
            Write-Host 'Selected installation: Not selected yet' -ForegroundColor DarkGray
            Write-Host 'Installed UE4SS: Select an installation first' -ForegroundColor DarkGray
            Write-Host ''
        }
        Write-Host '1. Install or update Experimental UE4SS automatically'
        Write-Host '2. Synchronize new Workshop UE4SS mods'
        Write-Host '3. Check the current installation'
        Write-Host '4. Run client and co-op diagnostics'
        Write-Host '5. Restore the normal Workshop UE4SS runtime'
        Write-Host '6. Select a different Palworld installation folder'
        Write-Host '7. >>> INSTRUCTIONS / READ ME <<<' -ForegroundColor Yellow
        Write-Host '8. Exit'
        Write-Host ''
        switch ((Read-Host 'Choose an option').Trim()) {
            '1' { Invoke-MenuAction { Invoke-AutomaticInstall } }
            '2' { Invoke-MenuAction { Invoke-Synchronization (Get-Paths) } }
            '3' { Invoke-MenuAction { Show-Status (Get-Paths) } }
            '4' { Invoke-MenuAction { Show-MultiplayerDiagnostics (Get-Paths) } }
            '5' { Invoke-MenuAction { $p=Get-Paths; $d=Show-RestorePreview $p; if (Read-YesNo 'Restore Workshop UE4SS now?') { Restore-WorkshopRuntime $p $d } else { Write-Host 'Restoration cancelled. No files were changed.' } } }
            '6' { Invoke-MenuAction { $script:GameRoot=$null; Select-GameRoot; Write-Host "Selected: $($script:GameRoot)" -ForegroundColor Green } }
            '7' { Invoke-MenuAction { Show-ClientInstructions } }
            '8' { $finished = $true }
            default { }
        }
    }
} catch {
    Write-Host ''
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
