@echo off
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

$script:HelperVersion = '2.0.0'
$script:GitHubOwner = 'UE4SS-RE'
$script:GitHubRepository = 'RE-UE4SS'
$script:RequiredTag = 'experimental-latest'
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
    return (Test-Path -LiteralPath (Join-Path $Path 'Pal\Binaries\Win64') -PathType Container)
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
        GitHubRoot = Join-Path $root 'Pal\Binaries\Win64\ue4ss'
        GitHubMods = Join-Path $root 'Pal\Binaries\Win64\ue4ss\Mods'
        GitHubDll = Join-Path $root 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
        GitHubProxy = Join-Path $root 'Pal\Binaries\Win64\dwmapi.dll'
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
    $base = Join-Path $Paths.Root "_UE4SS-Helper-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$Operation"
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

function Get-ExperimentalRelease {
    $api = "https://api.github.com/repos/$($script:GitHubOwner)/$($script:GitHubRepository)/releases/tags/$($script:RequiredTag)"
    Write-Host 'Checking the official UE4SS-RE/RE-UE4SS experimental release...'
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = "Palworld-UE4SS-Workshop-Helper/$($script:HelperVersion)" }
    $release = Invoke-RestMethod -Uri $api -Headers $headers -UseBasicParsing -TimeoutSec 30
    if ([string]$release.tag_name -ne $script:RequiredTag) { throw "GitHub returned unexpected tag: $($release.tag_name)" }
    if ([string]$release.html_url -notlike 'https://github.com/UE4SS-RE/RE-UE4SS/releases/*') { throw 'GitHub returned an unexpected release URL.' }
    $assets = @($release.assets | Where-Object {
        $_.name -match '(?i)\.zip$' -and
        $_.name -notmatch '(?i)(zdev|\bdev\b|debug|symbols?|pdb|source|custom|mapgen)' -and
        $_.browser_download_url -like 'https://github.com/UE4SS-RE/RE-UE4SS/releases/download/*'
    })
    if ($assets.Count -ne 1) {
        $names = @($assets | ForEach-Object name) -join ', '
        throw "Expected exactly one normal Experimental UE4SS ZIP, but found $($assets.Count): $names. The release layout may have changed; no file was downloaded."
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
    $releaseInfo = Get-ExperimentalRelease
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
        Test-ZipEntries $zipPath
        New-Item -ItemType Directory -Path $extractPath | Out-Null
        [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
        $layout = Get-ExtractedLayout $extractPath
        return [pscustomobject]@{
            TempRoot=$tempRoot
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

function Show-InstallPreview {
    param([hashtable]$Paths, [object]$Package)
    Write-Heading 'Installation preview'
    Write-Host "Game folder : $($Paths.Root)"
    Write-Host "Source      : $($Package.DownloadUrl)"
    Write-Host "Required tag: $($Package.Tag)"
    Write-Host "Asset       : $($Package.AssetName)"
    Write-Host "Size        : $([Math]::Round($Package.AssetSize / 1MB, 2)) MB"
    Write-Host "SHA-256     : $($Package.Sha256)"
    Write-Host ''
    Write-Host 'The helper will:'
    Write-Host '  - back up the current GitHub UE4SS runtime and proxy, if present;'
    Write-Host '  - preserve an existing UE4SS-settings.ini;'
    Write-Host '  - merge existing Workshop UE4SS mods into the GitHub Mods directory;'
    Write-Host '  - replace the Workshop Mods directory with a verified junction;'
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
    $state = @{ JunctionCreated=$false; WorkshopMoved=$false; WorkshopDllDisabled=$false; HadGitHubRoot=$false; HadProxy=$false; HadJunction=(Test-IsJunction $Paths.WorkshopMods) }
    try {
        if (Test-Path -LiteralPath $Paths.GitHubRoot -PathType Container) {
            $state.HadGitHubRoot = $true
            Copy-Directory $Paths.GitHubRoot (Join-Path $backup 'PreviousGitHubRuntime')
        }
        if (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf) {
            $state.HadProxy = $true
            Copy-Item -LiteralPath $Paths.GitHubProxy -Destination (Join-Path $backup 'Previous-dwmapi.dll')
        }
        Save-BackupManifest $backup 'Install' @{ sourceTag=$Package.Tag; sourceAsset=$Package.AssetName; sourceSha256=$Package.Sha256 }

        if ((Test-Path -LiteralPath $Paths.WorkshopMods -PathType Container) -and -not (Test-IsJunction $Paths.WorkshopMods)) {
            Copy-Directory $Paths.WorkshopMods $Paths.GitHubMods
        }
        Copy-Ue4ssOverlay $Package.Layout.Ue4ssSource $Paths.GitHubRoot
        Copy-Item -LiteralPath $Package.Layout.ProxySource -Destination $Paths.GitHubProxy -Force
        if (-not (Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf) -or -not (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf)) {
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
            if (Test-Path -LiteralPath $Paths.GitHubRoot -PathType Container) {
                Move-Item -LiteralPath $Paths.GitHubRoot -Destination (Join-Path $backup 'FailedPartialGitHubRuntime')
            }
            if ($state.HadGitHubRoot) { Copy-Directory (Join-Path $backup 'PreviousGitHubRuntime') $Paths.GitHubRoot }
            if (Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf) {
                Move-Item -LiteralPath $Paths.GitHubProxy -Destination (Join-Path $backup 'Failed-dwmapi.dll') -Force
            }
            if ($state.HadProxy) { Copy-Item -LiteralPath (Join-Path $backup 'Previous-dwmapi.dll') -Destination $Paths.GitHubProxy }
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
    if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.', '..') -or
        $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $name.Contains('\') -or $name.Contains('/') -or [IO.Path]::IsPathRooted($name)) {
        throw "Unsafe or invalid PackageName in '$InfoPath': '$name'"
    }
    return $name
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
            if (Test-Path -LiteralPath $enabled -PathType Leaf) {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Already enabled' }; continue
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
    $preview = @(Get-SyncResults $Paths $false)
    if ($preview.Count -eq 0) { Write-Host 'No applicable Workshop UE4SS mods were found.'; return }
    $preview | Sort-Object Package | Format-Table -AutoSize -Wrap
    if (@($preview | Where-Object Result -eq 'Would create enabled.txt').Count -eq 0) { return }
    if (-not (Read-YesNo 'Create the missing enabled.txt files now?')) { return }
    Assert-PalworldClosed
    Write-Heading 'Synchronization result'
    @(Get-SyncResults $Paths $true) | Sort-Object Package | Format-Table -AutoSize -Wrap
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
    [pscustomobject]@{
        'Game folder' = $Paths.Root
        'GitHub proxy present' = Test-Path -LiteralPath $Paths.GitHubProxy -PathType Leaf
        'GitHub runtime present' = Test-Path -LiteralPath $Paths.GitHubDll -PathType Leaf
        'Workshop DLL active' = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
        'Disabled Workshop DLL found' = $null -ne (Get-ChildItem -LiteralPath $Paths.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        'Mods junction present' = $junction
        'Junction target' = $junctionTarget
        'UE4SS log present' = Test-Path -LiteralPath (Join-Path $Paths.GitHubRoot 'UE4SS.log') -PathType Leaf
    } | Format-List
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

function Invoke-AutomaticInstall {
    $paths = Get-Paths
    $package = $null
    try {
        $package = Get-ExperimentalPackage
        Show-InstallPreview $paths $package
        Write-Host ''
        Write-Host 'Only the official Experimental release is accepted. Stable and DEV builds are excluded.' -ForegroundColor Yellow
        if (Read-YesNo 'Install or update Experimental UE4SS now?') { Install-ExperimentalPackage $paths $package }
        else { Write-Host 'Installation cancelled. No game files were changed.' }
    } finally {
        if ($null -ne $package -and (Test-Path -LiteralPath $package.TempRoot)) { Remove-Item -LiteralPath $package.TempRoot -Recurse -Force }
    }
}

function Invoke-MenuAction {
    param([scriptblock]$Action)
    Clear-Host
    try { & $Action }
    catch { Write-Host ''; Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
    Wait-ForMenu
}

try {
    $Host.UI.RawUI.WindowTitle = "Palworld UE4SS Workshop Helper v$($script:HelperVersion)"
    $finished = $false
    while (-not $finished) {
        Clear-Host
        Write-Host "Palworld UE4SS Workshop Helper v$($script:HelperVersion)" -ForegroundColor Cyan
        Write-Host 'Experimental UE4SS only - Windows Steam version' -ForegroundColor DarkGray
        Write-Host ''
        if ($script:GameRoot) { Write-Host "Selected installation: $($script:GameRoot)" -ForegroundColor DarkGray; Write-Host '' }
        Write-Host '1. Install or update Experimental UE4SS automatically'
        Write-Host '2. Synchronize new Workshop UE4SS mods'
        Write-Host '3. Check the current installation'
        Write-Host '4. Restore the normal Workshop UE4SS runtime'
        Write-Host '5. Select a different Palworld installation folder'
        Write-Host '6. Exit'
        Write-Host ''
        switch ((Read-Host 'Choose an option').Trim()) {
            '1' { Invoke-MenuAction { Invoke-AutomaticInstall } }
            '2' { Invoke-MenuAction { Invoke-Synchronization (Get-Paths) } }
            '3' { Invoke-MenuAction { Show-Status (Get-Paths) } }
            '4' { Invoke-MenuAction { $p=Get-Paths; $d=Show-RestorePreview $p; if (Read-YesNo 'Restore Workshop UE4SS now?') { Restore-WorkshopRuntime $p $d } else { Write-Host 'Restoration cancelled. No files were changed.' } } }
            '5' { Invoke-MenuAction { $script:GameRoot=$null; Select-GameRoot; Write-Host "Selected: $($script:GameRoot)" -ForegroundColor Green } }
            '6' { $finished = $true }
            default { }
        }
    }
} catch {
    Write-Host ''
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
