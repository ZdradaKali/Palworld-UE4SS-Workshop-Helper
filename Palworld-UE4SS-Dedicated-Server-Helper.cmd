@echo off
rem Original scripts and helpers by ZdradaKali (GitHub) / Yani Neco (Steam) / hess_ch (Discord).
rem Official source: https://github.com/ZdradaKali/Palworld-UE4SS-Workshop-Helper
rem Copies from any other source are unverified and may have been modified.
setlocal
title Palworld UE4SS Dedicated Server Helper
set "PALWORLD_SERVER_HELPER_FILE=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$p=$env:PALWORLD_SERVER_HELPER_FILE; $c=[IO.File]::ReadAllText($p); $m='### POWERSHELL PAYLOAD ###'; $i=$c.LastIndexOf($m); if($i -lt 0){throw 'Embedded PowerShell payload not found.'}; & ([scriptblock]::Create($c.Substring($i+$m.Length)))"
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
$script:ServerAppId = '2394010'
$script:ServerRoot = $null
$script:Builds = [ordered]@{
    Palworld = [pscustomobject]@{
        Key = 'Palworld'
        DisplayName = 'Palworld-specific Experimental build'
        Owner = 'Okaetsu'
        Repository = 'RE-UE4SS'
        Tag = 'experimental-palworld'
        AssetName = 'UE4SS-Palworld.zip'
        TrustedSha256 = '768A45718FBB9E429AC5CC3CE4A139A1B7B468BFF31B4A136AE483D725ACA1CA'
    }
    Official = [pscustomobject]@{
        Key = 'Official'
        DisplayName = 'Official Experimental build'
        Owner = 'UE4SS-RE'
        Repository = 'RE-UE4SS'
        Tag = 'experimental-latest'
        AssetName = 'UE4SS_v3.0.1-1018-g662df915.zip'
        TrustedSha256 = '590AE4C6463DB61497123B9ED35373596C39FB27F736E2078A02B476599671BA'
    }
}

function Write-Heading {
    param([string]$Text)
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('-' * $Text.Length) -ForegroundColor DarkCyan
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
    Write-Host ("{0,-49}: " -f $Label) -NoNewline
    Write-Host ([string]$Value) -ForegroundColor $color
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

function Normalize-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $clean = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').TrimEnd('\', '/'))
    try { return [IO.Path]::GetFullPath($clean) } catch { return $null }
}

function Test-ServerRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $win64 = Join-Path $Path 'Pal\Binaries\Win64'
    if (-not (Test-Path -LiteralPath $win64 -PathType Container)) { return $false }
    foreach ($candidate in @(
        (Join-Path $Path 'PalServer.exe'),
        (Join-Path $win64 'PalServer-Win64-Shipping-Cmd.exe'),
        (Join-Path $win64 'PalServer-Win64-Shipping.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $true }
    }
    return $false
}

function Get-ServerSelectionStatePath {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $null }
    return Join-Path $env:LOCALAPPDATA 'Palworld-UE4SS-Workshop-Helper\selected-server.txt'
}

function Get-SavedServerRoot {
    $statePath = Get-ServerSelectionStatePath
    if (-not $statePath -or -not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try {
        $saved = Normalize-Path ([IO.File]::ReadAllText($statePath))
        if (Test-ServerRoot $saved) { return $saved }
    } catch { }
    return $null
}

function Save-ServerRootSelection {
    param([string]$Path)
    if (-not (Test-ServerRoot $Path)) { return }
    $statePath = Get-ServerSelectionStatePath
    if (-not $statePath) { return }
    try {
        $stateDirectory = Split-Path -Parent $statePath
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        [IO.File]::WriteAllText($statePath, (Normalize-Path $Path), (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Get-ServerRootFromLocation {
    param([string]$Path)
    $current = Normalize-Path $Path
    if (-not $current) { return $null }
    if (Test-Path -LiteralPath $current -PathType Leaf) { $current = Split-Path -Parent $current }
    for ($depth = 0; $depth -lt 7 -and $current; $depth++) {
        if (Test-ServerRoot $current) { return $current }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
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
                $valueProperty = $key.PSObject.Properties[$property]
                if ($null -eq $valueProperty) { continue }
                $value = Normalize-Path ([string]$valueProperty.Value)
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
                $library = Normalize-Path ($match.Groups[1].Value -replace '\\\\', '\')
                if ($library -and (Test-Path -LiteralPath $library -PathType Container)) { $roots.Add($library) }
            }
        } catch { }
    }
    return @($roots | Sort-Object -Unique)
}

function Find-PalServerInstallations {
    $candidates = New-Object System.Collections.Generic.List[string]
    $addCandidate = {
        param([string]$Candidate)
        $normalized = Normalize-Path $Candidate
        if ($normalized -and (Test-ServerRoot $normalized)) { $candidates.Add($normalized) }
    }

    foreach ($location in @(
        (Get-SavedServerRoot),
        $env:PALSERVER_ROOT,
        $env:PALWORLD_SERVER_HELPER_FILE,
        ([Environment]::CurrentDirectory),
        ((Get-Location).Path)
    )) {
        $root = Get-ServerRootFromLocation $location
        if ($root) { & $addCandidate $root }
    }

    foreach ($process in @(Get-RunningServerProcesses)) {
        try {
            $root = Get-ServerRootFromLocation $process.Path
            if ($root) { & $addCandidate $root }
        } catch { }
    }

    foreach ($steamRoot in Get-SteamRoots) {
        $steamApps = if ((Split-Path -Leaf $steamRoot) -ieq 'steamapps') { $steamRoot } else { Join-Path $steamRoot 'steamapps' }
        $manifest = Join-Path $steamApps "appmanifest_$($script:ServerAppId).acf"
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            try {
                $content = Get-Content -LiteralPath $manifest -Raw
                $match = [regex]::Match($content, '"installdir"\s+"([^"]+)"')
                if ($match.Success) {
                    $candidate = Normalize-Path (Join-Path $steamApps (Join-Path 'common' $match.Groups[1].Value))
                    & $addCandidate $candidate
                }
            } catch { }
        }
        $defaultCandidate = Normalize-Path (Join-Path $steamApps 'common\PalServer')
        & $addCandidate $defaultCandidate
    }

    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        if (-not $drive.IsReady -or $drive.DriveType -ne [IO.DriveType]::Fixed) { continue }
        foreach ($relativePath in @(
            'PalServer',
            'Servers\PalServer',
            'Games\PalServer',
            'SteamCMD\PalServer',
            'SteamCMD\steamapps\common\PalServer'
        )) {
            & $addCandidate (Join-Path $drive.RootDirectory.FullName $relativePath)
        }
    }
    return @($candidates | Sort-Object -Unique)
}

function Select-ServerRoot {
    param([switch]$ForceChoice)
    if (-not $ForceChoice) {
        $saved = Get-SavedServerRoot
        if ($saved) {
            $script:ServerRoot = $saved
            Write-Host "Using the previously selected Palworld dedicated server: $saved" -ForegroundColor Green
            return
        }
    }

    $found = @(Find-PalServerInstallations)
    if ($found.Count -eq 1 -and -not $ForceChoice) {
        Write-Host "Detected Palworld dedicated server: $($found[0])" -ForegroundColor Green
        $script:ServerRoot = $found[0]
        Save-ServerRootSelection $script:ServerRoot
        return
    } elseif ($found.Count -gt 0) {
        Write-Host 'Multiple Windows dedicated-server installations were detected:'
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1). $($found[$i])" }
        Write-Host '  M. Enter a path manually'
        while ($true) {
            $selection = (Read-Host 'Choose a server installation').Trim()
            if ($selection -match '^\d+$') {
                $index = [int]$selection - 1
                if ($index -ge 0 -and $index -lt $found.Count) {
                    $script:ServerRoot = $found[$index]
                    Save-ServerRootSelection $script:ServerRoot
                    return
                }
            }
            if ($selection -match '^(?i)m$') { break }
            Write-Host 'Invalid selection.' -ForegroundColor Yellow
        }
    }

    while ($true) {
        Write-Host ''
        Write-Host 'Select the folder containing PalServer.exe. SteamCMD installations can be entered manually.' -ForegroundColor DarkGray
        $manual = Normalize-Path (Read-Host 'Paste the Windows PalServer installation folder path')
        if (Test-ServerRoot $manual) {
            $script:ServerRoot = $manual
            Save-ServerRootSelection $script:ServerRoot
            return
        }
        Write-Host 'That folder does not contain a supported Windows PalServer executable and Pal\Binaries\Win64.' -ForegroundColor Yellow
    }
}

function Get-ServerPaths {
    if (-not (Test-ServerRoot $script:ServerRoot)) { Select-ServerRoot }
    $root = $script:ServerRoot
    return @{
        Root = $root
        Win64 = Join-Path $root 'Pal\Binaries\Win64'
        ModsRoot = Join-Path $root 'Mods'
        WorkshopStage = Join-Path $root 'Mods\Workshop'
        ManagedRoot = Join-Path $root 'Mods\ManagedMods'
        WorkshopRuntime = Join-Path $root 'Mods\NativeMods\UE4SS'
        WorkshopMods = Join-Path $root 'Mods\NativeMods\UE4SS\Mods'
        WorkshopDll = Join-Path $root 'Mods\NativeMods\UE4SS\UE4SS.dll'
        WorkshopLayout = Join-Path $root 'Mods\NativeMods\UE4SS\MemberVariableLayout.ini'
        ExternalRoot = Join-Path $root 'Pal\Binaries\Win64\ue4ss'
        ExternalMods = Join-Path $root 'Pal\Binaries\Win64\ue4ss\Mods'
        ExternalDll = Join-Path $root 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
        ExternalProxy = Join-Path $root 'Pal\Binaries\Win64\dwmapi.dll'
        ExternalLayout = Join-Path $root 'Pal\Binaries\Win64\ue4ss\MemberVariableLayout.ini'
        RuntimeMarker = Join-Path $root 'Pal\Binaries\Win64\ue4ss\Palworld-UE4SS-Helper-runtime.json'
        PalModSettings = Join-Path $root 'Mods\PalModSettings.ini'
        WorldSettings = Join-Path $root 'Pal\Saved\Config\WindowsServer\PalWorldSettings.ini'
        SavedLogs = Join-Path $root 'Pal\Saved\Logs'
        CrashRoot = Join-Path $root 'Pal\Saved\Crashes'
        HelperRoot = Join-Path $root '_UE4SS-Server-Helper'
        BackupsRoot = Join-Path $root '_UE4SS-Server-Helper\Backups'
        HelperLogs = Join-Path $root '_UE4SS-Server-Helper\Logs'
        LegacyHelperLogs = Join-Path $root '_UE4SS-Server-Helper-Logs'
    }
}

function Assert-ServerClosed {
    $running = @(Get-RunningServerProcesses)
    if ($running.Count -gt 0) { throw 'The Palworld dedicated server is running. Stop it completely and try again.' }
}

function Get-RunningServerProcesses {
    $names = @('PalServer', 'PalServer-Win64-Shipping', 'PalServer-Win64-Shipping-Cmd')
    return @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in $names })
}

function Get-ServerExecutable {
    param([hashtable]$Paths)
    foreach ($candidate in @(
        (Join-Path $Paths.Root 'PalServer.exe'),
        (Join-Path $Paths.Win64 'PalServer-Win64-Shipping-Cmd.exe'),
        (Join-Path $Paths.Win64 'PalServer-Win64-Shipping.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw 'No supported PalServer executable was found in the selected server folder.'
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
        target = 'WindowsDedicatedServer'
        operation = $Operation
        createdUtc = [DateTime]::UtcNow.ToString('o')
        serverRoot = $script:ServerRoot
    }
    foreach ($key in $Extra.Keys) { $manifest[$key] = $Extra[$key] }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $BackupRoot 'backup-manifest.json') -Encoding UTF8
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
    $externalDll = Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf
    $externalProxy = Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf
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

function Get-PalModSettingsState {
    param([hashtable]$Paths)
    $lines = @()
    if (Test-Path -LiteralPath $Paths.PalModSettings -PathType Leaf) {
        $lines = @(Get-Content -LiteralPath $Paths.PalModSettings)
    }
    $global = $null
    $workshopRoot = $null
    $active = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $lines) {
        if ($line -match '^\s*bGlobalEnableMod\s*=\s*(.+?)\s*$') { $global = $matches[1] }
        elseif ($line -match '^\s*ActiveModList\s*=\s*(.+?)\s*$') {
            $value = $matches[1].Trim().Trim('"')
            if (-not [string]::IsNullOrWhiteSpace($value)) { [void]$active.Add($value) }
        } elseif ($line -match '^\s*WorkshopRootDir\s*=\s*(.+?)\s*$') {
            $workshopRoot = Normalize-Path $matches[1]
        }
    }
    return [pscustomobject]@{
        Exists = Test-Path -LiteralPath $Paths.PalModSettings -PathType Leaf
        Lines = $lines
        GlobalEnable = $global
        Active = $active
        WorkshopRoot = $workshopRoot
    }
}

function Get-WorldAllowClientMod {
    param([hashtable]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.WorldSettings -PathType Leaf)) { return 'Configuration file missing' }
    $raw = Get-Content -LiteralPath $Paths.WorldSettings -Raw
    try { $bounds = Get-OptionSettingsBounds $raw }
    catch { return 'Configuration not recognized' }
    $content = $raw.Substring($bounds.Open + 1, $bounds.Close - $bounds.Open - 1)
    $match = [regex]::Match($content, '(?i)\bbAllowClientMod\s*=\s*(True|False)')
    if (-not $match.Success) { return 'Not explicitly configured' }
    return $match.Groups[1].Value
}

function Get-OptionSettingsBounds {
    param([string]$Raw)
    $match = [regex]::Match($Raw, '(?im)^\s*OptionSettings\s*=\s*\(')
    if (-not $match.Success) { throw 'OptionSettings=(...) was not found.' }
    $open = $Raw.IndexOf('(', $match.Index)
    $depth = 0
    $quoted = $false
    for ($i = $open; $i -lt $Raw.Length; $i++) {
        $character = $Raw[$i]
        if ($character -eq '"' -and ($i -eq 0 -or $Raw[$i - 1] -ne '\')) {
            $quoted = -not $quoted
            continue
        }
        if ($quoted) { continue }
        if ($character -eq '(') { $depth++; continue }
        if ($character -eq ')') {
            $depth--
            if ($depth -eq 0) { return [pscustomobject]@{ Open=$open; Close=$i } }
            if ($depth -lt 0) { break }
        }
    }
    throw 'OptionSettings=(...) is malformed or incomplete.'
}

function Get-WorkshopRoots {
    param([hashtable]$Paths, [object]$SettingsState)
    $roots = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Paths.WorkshopStage -PathType Container) { $roots.Add($Paths.WorkshopStage) }
    if ($SettingsState.WorkshopRoot -and (Test-Path -LiteralPath $SettingsState.WorkshopRoot -PathType Container)) {
        $roots.Add($SettingsState.WorkshopRoot)
    }
    return @($roots | Sort-Object -Unique)
}

function Get-ServerWorkshopPackages {
    param([hashtable]$Paths)
    $settings = Get-PalModSettingsState $Paths
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-WorkshopRoots $Paths $settings) {
        foreach ($folder in Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue) {
            $infoPath = Join-Path $folder.FullName 'Info.json'
            if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) { continue }
            $workshopId = if ($folder.Name -match '^\d+$') { $folder.Name } else { 'Unknown' }
            try {
                $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
                $package = Get-SafePackageName $info.PackageName $infoPath
                $rules = @($info.InstallRule)
                $serverRules = @($rules | Where-Object { Test-IsServerRule $_ })
                $serverTypes = @($serverRules | ForEach-Object { [string]$_.Type } | Where-Object { $_ } | Sort-Object -Unique)
                $allTypes = @($rules | ForEach-Object { [string]$_.Type } | Where-Object { $_ } | Sort-Object -Unique)
                $dependencies = @($info.Dependencies | ForEach-Object { [string]$_ } | Where-Object { $_ })
                $results.Add([pscustomobject]@{
                    ModName = [string]$info.ModName
                    Package = $package
                    WorkshopID = $workshopId
                    Version = [string]$info.Version
                    Info = $info
                    InfoPath = $infoPath
                    SourceRoot = $root
                    SourceFolder = $folder.FullName
                    AllTypes = $allTypes
                    ServerRules = $serverRules
                    ServerTypes = $serverTypes
                    Dependencies = $dependencies
                    Error = $null
                })
            } catch {
                $results.Add([pscustomobject]@{
                    ModName = $folder.Name
                    Package = $folder.Name
                    WorkshopID = $workshopId
                    Version = ''
                    Info = $null
                    InfoPath = $infoPath
                    SourceRoot = $root
                    SourceFolder = $folder.FullName
                    AllTypes = @()
                    ServerRules = @()
                    ServerTypes = @()
                    Dependencies = @()
                    Error = $_.Exception.Message
                })
            }
        }
    }
    return $results.ToArray()
}

function Get-ServerPackageReport {
    param([hashtable]$Paths)
    $settings = Get-PalModSettingsState $Paths
    $records = @(Get-ServerWorkshopPackages $Paths)
    $available = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $records) { if ($null -eq $record.Error) { [void]$available.Add($record.Package) } }

    $duplicates = @($records | Group-Object Package | Where-Object Count -gt 1 | ForEach-Object Name)
    $externalActive = (Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf) -and (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf)
    $workshopActive = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    $report = foreach ($record in $records) {
        $missingDependencies = @($record.Dependencies | Where-Object { -not $available.Contains($_) })
        $manifest = Join-Path $Paths.ManagedRoot (Join-Path $record.Package 'InstallManifest.json')
        $deployed = Test-Path -LiteralPath $manifest -PathType Leaf
        $runtimeState = if ($record.Error) {
            'Invalid metadata'
        } elseif ($record.ServerRules.Count -eq 0) {
            'Not server-compatible'
        } elseif ('UE4SS' -in $record.ServerTypes) {
            if ($externalActive) { 'External runtime active' }
            elseif ($workshopActive) { 'Workshop runtime active' }
            else { 'No active runtime' }
        } elseif ('Lua' -in $record.ServerTypes) {
            $luaRoot = Join-Path $Paths.ExternalMods $record.Package
            $luaContent = (Test-Path -LiteralPath (Join-Path $luaRoot 'Scripts\main.lua') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path $luaRoot 'dlls\main.dll') -PathType Leaf)
            $luaActivation = Get-Ue4ssModActivationState $Paths.ExternalMods $record.Package
            $workshopLuaRoot = Join-Path $Paths.WorkshopMods $record.Package
            $workshopLuaContent = (Test-Path -LiteralPath (Join-Path $workshopLuaRoot 'Scripts\main.lua') -PathType Leaf) -or
                (Test-Path -LiteralPath (Join-Path $workshopLuaRoot 'dlls\main.dll') -PathType Leaf)
            $workshopLuaActivation = Get-Ue4ssModActivationState $Paths.WorkshopMods $record.Package
            if ($externalActive -and $luaContent -and $luaActivation -eq 'EnabledFile') { 'External enabled' }
            elseif ($externalActive -and $luaContent -and $luaActivation -eq 'ModsTxtEnabled') { 'External enabled (mods.txt)' }
            elseif ($externalActive -and $luaContent -and $luaActivation -eq 'ModsTxtDisabled') { 'External disabled in mods.txt' }
            elseif ($externalActive -and $luaContent) { 'External not enabled' }
            elseif ($externalActive -and $deployed) { 'Not synchronized' }
            elseif ($workshopActive -and $workshopLuaContent -and $workshopLuaActivation -eq 'EnabledFile') { 'Workshop enabled' }
            elseif ($workshopActive -and $workshopLuaContent -and $workshopLuaActivation -eq 'ModsTxtEnabled') { 'Workshop enabled (mods.txt)' }
            elseif ($workshopActive -and $workshopLuaContent -and $workshopLuaActivation -eq 'ModsTxtDisabled') { 'Workshop disabled in mods.txt' }
            elseif ($workshopActive -and $workshopLuaContent) { 'Workshop not enabled' }
            elseif ($workshopActive -and $deployed) { 'Workshop content missing' }
            elseif ($luaContent) { 'Copied; runtime inactive' }
            elseif ($deployed) { 'Not synchronized' }
            else { 'Not deployed' }
        } elseif ('PalSchema' -in $record.ServerTypes) {
            $schemaRoot = Join-Path $Paths.ExternalMods (Join-Path 'PalSchema\mods' $record.Package)
            $workshopSchemaRoot = Join-Path $Paths.WorkshopMods (Join-Path 'PalSchema\mods' $record.Package)
            if ($externalActive -and (Test-Path -LiteralPath $schemaRoot -PathType Container)) { 'External synchronized' }
            elseif ($externalActive -and $deployed) { 'Not synchronized' }
            elseif ($workshopActive -and (Test-Path -LiteralPath $workshopSchemaRoot -PathType Container)) { 'Workshop deployed' }
            elseif ($workshopActive -and $deployed) { 'Workshop content missing' }
            elseif (Test-Path -LiteralPath $schemaRoot -PathType Container) { 'Copied; runtime inactive' }
            elseif ($deployed) { 'Not synchronized' }
            else { 'Not deployed' }
        } elseif (@($record.ServerTypes | Where-Object { $_ -in @('LogicMods','Paks') }).Count -gt 0) {
            'Managed by Palworld'
        } else {
            'No helper action'
        }
        [pscustomobject]@{
            Mod = $record.ModName
            Package = $record.Package
            WorkshopID = $record.WorkshopID
            ServerTypes = $(if ($record.Error) { 'Invalid metadata' } elseif ($record.ServerTypes.Count) { $record.ServerTypes -join ', ' } else { 'Not server-compatible' })
            Active = $settings.Active.Contains($record.Package)
            Deployed = $deployed
            RuntimeState = $runtimeState
            Dependencies = $(if ($missingDependencies.Count) { "Missing: $($missingDependencies -join ', ')" } elseif ($record.Dependencies.Count) { 'Present' } else { 'No declared dependencies' })
            Duplicate = $record.Package -in $duplicates
            Error = $record.Error
        }
    }
    return @($report)
}

function Get-FixedTableCell {
    param([object]$Value, [int]$Width)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($text.Length -gt $Width) {
        if ($Width -le 3) { return $text.Substring(0, $Width) }
        $text = $text.Substring(0, $Width - 3) + '...'
    }
    return $text.PadRight($Width)
}

function Write-ServerPackageReport {
    param([object[]]$Report)
    $columns = @(
        [pscustomobject]@{ Name='Mod'; Label='Mod'; Width=34 },
        [pscustomobject]@{ Name='WorkshopID'; Label='Workshop ID'; Width=12 },
        [pscustomobject]@{ Name='Package'; Label='Package'; Width=26 },
        [pscustomobject]@{ Name='ServerTypes'; Label='Server types'; Width=22 },
        [pscustomobject]@{ Name='Active'; Label='Active'; Width=7 },
        [pscustomobject]@{ Name='Deployed'; Label='Deployed'; Width=9 },
        [pscustomobject]@{ Name='RuntimeState'; Label='Runtime state'; Width=26 },
        [pscustomobject]@{ Name='Dependencies'; Label='Dependencies'; Width=25 }
    )

    foreach ($column in $columns) {
        Write-Host (Get-FixedTableCell $column.Label $column.Width) -NoNewline -ForegroundColor Cyan
        Write-Host ' ' -NoNewline
    }
    Write-Host ''
    foreach ($column in $columns) {
        Write-Host (('-' * $column.Width) + ' ') -NoNewline -ForegroundColor DarkCyan
    }
    Write-Host ''

    foreach ($row in @($Report | Sort-Object Package)) {
        foreach ($column in $columns) {
            $value = $row.($column.Name)
            $color = 'Gray'
            if ($column.Name -in @('Active','Deployed')) {
                $color = if ([bool]$value) { 'Green' } else { 'Red' }
            } elseif ($column.Name -eq 'RuntimeState') {
                $color = switch -Regex ([string]$value) {
                    '^(External enabled(?: \(mods\.txt\))?|External synchronized|External runtime active|Workshop runtime active|Workshop enabled(?: \(mods\.txt\))?|Workshop deployed|Managed by Palworld)$' { 'Green'; break }
                    '^(Invalid metadata|No active runtime|External not enabled|External disabled in mods\.txt|Workshop not enabled|Workshop disabled in mods\.txt|Workshop content missing|Not synchronized|Not deployed)$' { 'Red'; break }
                    '^(Copied; runtime inactive|Not server-compatible)$' { 'Yellow'; break }
                    default { 'DarkGray' }
                }
            } elseif ($column.Name -eq 'Dependencies') {
                $color = if ([string]$value -like 'Missing:*') { 'Red' } elseif ([string]$value -eq 'Present') { 'Green' } else { 'DarkGray' }
            }
            Write-Host (Get-FixedTableCell $value $column.Width) -NoNewline -ForegroundColor $color
            Write-Host ' ' -NoNewline
        }
        Write-Host ''
    }

    foreach ($duplicate in @($Report | Where-Object Duplicate)) {
        Write-Host "WARNING: Duplicate package name detected: $($duplicate.Package)" -ForegroundColor Yellow
    }
    foreach ($missing in @($Report | Where-Object { $_.Dependencies -like 'Missing:*' })) {
        Write-Host "Missing dependencies for $($missing.Package): $($missing.Dependencies.Substring(8).Trim())" -ForegroundColor Red
    }
    Write-Host ''
    Write-Host 'Server types: only install-rule types explicitly marked IsServer=true in Info.json.' -ForegroundColor DarkGray
    Write-Host 'Active: listed in PalModSettings.ini. Deployed: Palworld created the package InstallManifest.json.' -ForegroundColor DarkGray
}

function Test-DiagnosticAliasMatch {
    param([string]$Text, [string]$Alias)
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Alias) -or $Alias.Length -lt 4) { return $false }
    if ($Alias -in @('Error','Fatal','Server','PalServer','Windows','Win64','UE4SS','dwmapi','Scripts','Content','main','Mods','LogicMods','Paks')) {
        return $false
    }
    $pattern = '(?i)(?<![A-Za-z0-9_])' + [regex]::Escape($Alias) + '(?![A-Za-z0-9_])'
    return [regex]::IsMatch($Text, $pattern)
}

function Get-ServerLogAnalysis {
    param(
        [hashtable]$Paths,
        [DateTime]$ModifiedSince = [DateTime]::MinValue,
        [string]$LogPath
    )

    $candidatePaths = if ([string]::IsNullOrWhiteSpace($LogPath)) {
        @(
            (Join-Path $Paths.ExternalRoot 'UE4SS.log'),
            (Join-Path $Paths.WorkshopRuntime 'UE4SS.log'),
            (Join-Path $Paths.Root 'Pal\Saved\Logs\PalServer.log')
        )
    } else { @($LogPath) }
    $logCandidates = @($candidatePaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ } |
        Where-Object { $_.LastWriteTime -ge $ModifiedSince })

    if (-not $logCandidates.Count) {
        return [pscustomobject]@{ Log=$null; Lines=@(); Errors=@(); Suspects=@(); Unmapped=@() }
    }

    $log = $logCandidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $tail = @(Get-Content -LiteralPath $log.FullName -Tail 2500 -ErrorAction Stop)
    $normalized = [regex]::Replace(($tail -join "`n"), '(?=\[\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})', "`n")
    $lines = @($normalized -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    $sessionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)Starting mods \(from mods\.txt') { $sessionStart = [Math]::Max(0, $i - 80) }
    }
    if ($sessionStart -ge 0) { $lines = @($lines | Select-Object -Skip $sessionStart) }

    $settings = Get-PalModSettingsState $Paths
    $packages = @(Get-ServerWorkshopPackages $Paths | Where-Object {
        -not $_.Error -and $settings.Active.Contains($_.Package)
    })
    $errorPattern = '(?i)(\[(?:error|fatal)\]|\bfatal\b|\bexception\b|\bfailed\b|\bfailure\b|\bcrash(?:ed)?\b|\bcould not\b|\bunable to\b|access violation|stack traceback)'
    $errors = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch $errorPattern) { continue }
        $severity = if ($lines[$i] -match '(?i)(\[fatal\]|\bfatal\b|access violation|unhandled exception|\bcrash(?:ed)?\b)') { 'Fatal' } else { 'Error' }
        $errors.Add([pscustomobject]@{ Index=$i; Severity=$severity; Line=$lines[$i] })
    }

    $suspectMap = @{}
    $unmapped = New-Object System.Collections.Generic.List[object]
    foreach ($error in $errors) {
        $direct = New-Object System.Collections.Generic.List[object]
        foreach ($package in $packages) {
            $aliases = @([string]$package.Package)
            if (-not [string]::IsNullOrWhiteSpace($package.ModName) -and $package.ModName.Length -ge 4) {
                $aliases += [string]$package.ModName
            }
            foreach ($rule in @($package.ServerRules)) {
                if ($null -eq $rule) { continue }
                $targetsProperty = $rule.PSObject.Properties['Targets']
                if ($null -eq $targetsProperty) { continue }
                foreach ($target in @($targetsProperty.Value)) {
                    $targetText = [string]$target
                    foreach ($candidate in @($targetText, [IO.Path]::GetFileName($targetText), [IO.Path]::GetFileNameWithoutExtension($targetText))) {
                        if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate.Length -ge 4 -and
                            $candidate -notin @('Scripts','Content','main','Mods')) { $aliases += $candidate }
                    }
                }
            }
            $aliases = @($aliases | Sort-Object -Unique)
            if (@($aliases | Where-Object { Test-DiagnosticAliasMatch $error.Line $_ }).Count -gt 0) {
                $direct.Add($package)
            }
        }

        $matches = @($direct.ToArray())
        $confidence = 'Direct reference'
        if ($matches.Count -eq 0) {
            $confidence = 'Nearby activity only'
            $start = [Math]::Max(0, $error.Index - 10)
            $context = @($lines | Select-Object -Skip $start -First ($error.Index - $start))
            for ($c = $context.Count - 1; $c -ge 0 -and $matches.Count -eq 0; $c--) {
                if ($context[$c] -notmatch '(?i)(Starting Lua mod|Loading mod:|\[Lua\])') { continue }
                $matches = @($packages | Where-Object {
                    $contextLine = $context[$c]
                    (Test-DiagnosticAliasMatch $contextLine $_.Package) -or
                    (-not [string]::IsNullOrWhiteSpace($_.ModName) -and $_.ModName.Length -ge 4 -and
                        (Test-DiagnosticAliasMatch $contextLine $_.ModName))
                })
            }
        }

        if ($matches.Count -eq 0) {
            $unmapped.Add($error)
            continue
        }
        foreach ($package in $matches) {
            if (-not $suspectMap.ContainsKey($package.Package)) {
                $suspectMap[$package.Package] = [pscustomobject]@{
                    Mod=$package.ModName
                    Package=$package.Package
                    WorkshopID=$package.WorkshopID
                    Confidence=$confidence
                    Fatal=0
                    Errors=0
                    Lines=(New-Object System.Collections.Generic.List[string])
                }
            }
            $entry = $suspectMap[$package.Package]
            if ($confidence -eq 'Direct reference') { $entry.Confidence = 'Direct reference' }
            if ($error.Severity -eq 'Fatal') { $entry.Fatal++ } else { $entry.Errors++ }
            if (-not $entry.Lines.Contains($error.Line)) { $entry.Lines.Add($error.Line) }
        }
    }

    $suspects = @($suspectMap.Values | Sort-Object @{Expression='Fatal';Descending=$true}, @{Expression='Errors';Descending=$true}, Package)
    return [pscustomobject]@{
        Log=$log.FullName
        Lines=$lines
        Errors=$errors.ToArray()
        Suspects=$suspects
        Unmapped=$unmapped.ToArray()
    }
}

function Get-ServerDiagnosticFiles {
    param(
        [hashtable]$Paths,
        [DateTime]$ModifiedSince = [DateTime]::MinValue,
        [string[]]$ExtraLogPaths = @()
    )
    $files = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sourceCutoff = $ModifiedSince
    $latestHelperLogs = @()
    $helperLogRoots = @($Paths.HelperLogs, $Paths.LegacyHelperLogs) | Sort-Object -Unique
    $allHelperLogs = @($helperLogRoots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Filter 'PalServer-session-*.log' -File -ErrorAction SilentlyContinue
    } | Sort-Object LastWriteTime -Descending)
    if ($ModifiedSince -eq [DateTime]::MinValue) {
        if ($allHelperLogs.Count -gt 0) {
            $latestSession = $allHelperLogs[0].BaseName -replace '-(?:stdout|stderr)$',''
            $latestHelperLogs = @($allHelperLogs | Where-Object { ($_.BaseName -replace '-(?:stdout|stderr)$','') -eq $latestSession })
            $sourceCutoff = ($latestHelperLogs | Sort-Object CreationTime | Select-Object -First 1).CreationTime.AddSeconds(-5)
        }
    }
    $addFile = {
        param([string]$Path, [string]$Label)
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
        $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.LastWriteTime -lt $sourceCutoff) { return }
        $full = [IO.Path]::GetFullPath($item.FullName)
        if ($seen.Add($full)) {
            $files.Add([pscustomobject]@{ Path=$full; Label=$Label; CreationTime=$item.CreationTime; LastWriteTime=$item.LastWriteTime; Length=$item.Length })
        }
    }

    & $addFile (Join-Path $Paths.ExternalRoot 'UE4SS.log') 'External UE4SS log'
    & $addFile (Join-Path $Paths.WorkshopRuntime 'UE4SS.log') 'Workshop UE4SS log'

    if (Test-Path -LiteralPath $Paths.SavedLogs -PathType Container) {
        $savedLogs = @(Get-ChildItem -LiteralPath $Paths.SavedLogs -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.log','.txt','.json') -and $_.LastWriteTime -ge $sourceCutoff } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 20)
        foreach ($file in $savedLogs) { & $addFile $file.FullName 'PalServer saved log' }
    }

    if (Test-Path -LiteralPath $Paths.CrashRoot -PathType Container) {
        $crashCutoff = if ($sourceCutoff -eq [DateTime]::MinValue) { (Get-Date).AddDays(-7) } else { $sourceCutoff }
        $crashText = @(Get-ChildItem -LiteralPath $Paths.CrashRoot -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { ($_.Extension -in @('.log','.txt','.xml') -or $_.Name -ieq 'CrashContext.runtime-xml') -and $_.LastWriteTime -ge $crashCutoff } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 20)
        foreach ($file in $crashText) { & $addFile $file.FullName 'Unreal crash report' }
    }

    $helperLogs = if ($ModifiedSince -eq [DateTime]::MinValue) { @($latestHelperLogs) } else {
        @($allHelperLogs | Where-Object { $_.LastWriteTime -ge $sourceCutoff })
    }
    foreach ($file in $helperLogs) { & $addFile $file.FullName 'Guided PalServer console' }

    foreach ($path in @($ExtraLogPaths)) { & $addFile $path 'Guided PalServer console' }
    return @($files.ToArray() | Sort-Object LastWriteTime -Descending)
}

function Get-RecentPalServerCrashArtifacts {
    param([hashtable]$Paths, [DateTime]$ModifiedSince = [DateTime]::MinValue)
    if (-not (Test-Path -LiteralPath $Paths.CrashRoot -PathType Container)) { return @() }
    $cutoff = if ($ModifiedSince -eq [DateTime]::MinValue) { (Get-Date).AddDays(-7) } else { $ModifiedSince }
    return @(Get-ChildItem -LiteralPath $Paths.CrashRoot -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -ge $cutoff -and
            ($_.Extension -in @('.dmp','.ue4crash') -or $_.Name -ieq 'CrashContext.runtime-xml')
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 12 |
        ForEach-Object { [pscustomobject]@{ Time=$_.LastWriteTime; File=$_.FullName; Size=$_.Length } })
}

function Get-RecentPalServerWindowsEvents {
    param([DateTime]$ModifiedSince = [DateTime]::MinValue)
    $cutoff = if ($ModifiedSince -eq [DateTime]::MinValue) { (Get-Date).AddDays(-7) } else { $ModifiedSince }
    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName='Application'; StartTime=$cutoff; Id=@(1000,1001,1026) } -MaxEvents 200 -ErrorAction Stop |
            Where-Object { $_.Message -match '(?i)PalServer(?:-Win64-Shipping(?:-Cmd)?)?\.exe' } |
            Sort-Object TimeCreated -Descending | Select-Object -First 12 |
            ForEach-Object {
                [pscustomobject]@{
                    Time=$_.TimeCreated
                    Id=$_.Id
                    Provider=$_.ProviderName
                    Line=([regex]::Replace([string]$_.Message, '\s+', ' ').Trim())
                }
            })
    } catch { return @() }
}

function Get-ServerFullLogAnalysis {
    param(
        [hashtable]$Paths,
        [DateTime]$ModifiedSince = [DateTime]::MinValue,
        [string[]]$ExtraLogPaths = @(),
        [switch]$IncludeWindowsEvents
    )
    $sources = @(Get-ServerDiagnosticFiles $Paths $ModifiedSince $ExtraLogPaths)
    $incidentSince = $ModifiedSince
    if ($incidentSince -eq [DateTime]::MinValue) {
        $guidedSources = @($sources | Where-Object Label -eq 'Guided PalServer console')
        if ($guidedSources.Count -gt 0) {
            $incidentSince = ($guidedSources | Sort-Object CreationTime | Select-Object -First 1).CreationTime.AddSeconds(-5)
        }
    }
    $allErrors = New-Object System.Collections.Generic.List[object]
    $allUnmapped = New-Object System.Collections.Generic.List[object]
    $suspectMap = @{}

    foreach ($source in $sources) {
        try { $single = Get-ServerLogAnalysis $Paths $ModifiedSince $source.Path }
        catch {
            $unreadable = [pscustomobject]@{
                Source=$source.Path; SourceLabel=$source.Label; Severity='Error';
                Line="The helper could not read this diagnostic source: $($_.Exception.Message)"
            }
            $allErrors.Add($unreadable)
            $allUnmapped.Add($unreadable)
            continue
        }
        foreach ($error in @($single.Errors)) {
            $error | Add-Member -NotePropertyName Source -NotePropertyValue $source.Path -Force
            $error | Add-Member -NotePropertyName SourceLabel -NotePropertyValue $source.Label -Force
            $allErrors.Add($error)
        }
        foreach ($error in @($single.Unmapped)) {
            $error | Add-Member -NotePropertyName Source -NotePropertyValue $source.Path -Force
            $error | Add-Member -NotePropertyName SourceLabel -NotePropertyValue $source.Label -Force
            $allUnmapped.Add($error)
        }
        foreach ($suspect in @($single.Suspects)) {
            if (-not $suspectMap.ContainsKey($suspect.Package)) {
                $suspectMap[$suspect.Package] = [pscustomobject]@{
                    Mod=$suspect.Mod; Package=$suspect.Package; WorkshopID=$suspect.WorkshopID; Confidence=$suspect.Confidence;
                    Fatal=0; Errors=0;
                    Sources=(New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase));
                    Lines=(New-Object System.Collections.Generic.List[string])
                }
            }
            $entry = $suspectMap[$suspect.Package]
            if ($suspect.Confidence -eq 'Direct reference') { $entry.Confidence = 'Direct reference' }
            $entry.Fatal += [int]$suspect.Fatal
            $entry.Errors += [int]$suspect.Errors
            [void]$entry.Sources.Add($source.Label)
            foreach ($line in @($suspect.Lines)) {
                $decorated = "[$($source.Label)] $line"
                if (-not $entry.Lines.Contains($decorated)) { $entry.Lines.Add($decorated) }
            }
        }
    }

    $windowsEvents = @()
    if ($IncludeWindowsEvents) {
        $windowsEvents = @(Get-RecentPalServerWindowsEvents $incidentSince)
        foreach ($event in $windowsEvents) {
            $record = [pscustomobject]@{
                Index=-1; Severity='Fatal'; Line=$event.Line; Source='Windows Application event log';
                SourceLabel='Windows crash event'; Time=$event.Time
            }
            $allErrors.Add($record)
            $allUnmapped.Add($record)
        }
    }

    $hintRules = @(
        [pscustomobject]@{ Pattern='(?i)out of memory|ran out of memory|memory allocation.*failed'; Text='Memory exhaustion is mentioned. This may be a server resource problem rather than one specific mod.' },
        [pscustomobject]@{ Pattern='(?i)address already in use|CreateBoundSocket|bind.*(?:failed|could not)|port.*(?:failed|unavailable)'; Text='A network port or socket failure is mentioned. Check for another server instance or a port conflict.' },
        [pscustomobject]@{ Pattern='(?i)dwmapi\.dll'; Text='The UE4SS proxy DLL is named in the failure. This points to runtime startup, but does not identify a specific mod.' },
        [pscustomobject]@{ Pattern='(?i)UE4SS\.dll'; Text='UE4SS.dll is named in the failure. The runtime is involved, but the line alone does not identify a specific mod.' },
        [pscustomobject]@{ Pattern='(?i)access violation|0xc0000005'; Text='A native access violation is reported. Load order or an interaction between native components may be involved.' },
        [pscustomobject]@{ Pattern='(?i)missing (?:file|module)|module.*not found|dependency.*(?:missing|not found)'; Text='A missing file, module or dependency is mentioned.' }
    )
    $hints = New-Object System.Collections.Generic.List[object]
    $seenHints = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($error in $allErrors) {
        foreach ($rule in $hintRules) {
            if ($error.Line -match $rule.Pattern -and $seenHints.Add($rule.Text)) {
                $hints.Add([pscustomobject]@{ Finding=$rule.Text; Source=$error.SourceLabel; Line=$error.Line })
            }
        }
    }

    $suspects = @($suspectMap.Values | ForEach-Object {
        [pscustomobject]@{
            Mod=$_.Mod; Package=$_.Package; WorkshopID=$_.WorkshopID; Confidence=$_.Confidence; Fatal=$_.Fatal; Errors=$_.Errors;
            Sources=(@($_.Sources) -join ', '); Lines=$_.Lines
        }
    } | Sort-Object @{Expression='Fatal';Descending=$true}, @{Expression='Errors';Descending=$true}, Package)

    return [pscustomobject]@{
        Log=$(if ($sources.Count) { $sources[0].Path } else { $null })
        Logs=$sources
        Errors=$allErrors.ToArray()
        Suspects=$suspects
        Unmapped=$allUnmapped.ToArray()
        Hints=$hints.ToArray()
        CrashArtifacts=@(Get-RecentPalServerCrashArtifacts $Paths $incidentSince)
        WindowsEvents=$windowsEvents
    }
}

function Show-ServerLogAnalysis {
    param(
        [hashtable]$Paths,
        [DateTime]$ModifiedSince = [DateTime]::MinValue,
        [string[]]$ExtraLogPaths = @()
    )
    Write-Heading 'Full PalServer diagnosis'
    $analysis = Get-ServerFullLogAnalysis $Paths $ModifiedSince $ExtraLogPaths -IncludeWindowsEvents
    if ($analysis.Logs.Count -eq 0 -and $analysis.WindowsEvents.Count -eq 0 -and $analysis.CrashArtifacts.Count -eq 0) {
        Write-Host 'No PalServer, UE4SS, console, crash-report or Windows crash source was found for this session.' -ForegroundColor DarkGray
        return
    }

    if ($analysis.Logs.Count -gt 0) {
        Write-Host "Diagnostic sources checked: $($analysis.Logs.Count)" -ForegroundColor DarkGray
        foreach ($source in $analysis.Logs) {
            Write-Host "  - $($source.Label): $($source.Path)" -ForegroundColor DarkGray
        }
    }
    if ($analysis.Errors.Count -eq 0) {
        Write-Host 'No obvious textual error or fatal-crash signature was found in the examined session.' -ForegroundColor Green
    }

    if ($analysis.Suspects.Count -gt 0) {
        Write-Host ''
        Write-Host 'Potentially involved Workshop packages:' -ForegroundColor Yellow
        $analysis.Suspects | Select-Object Mod,WorkshopID,Package,Confidence,Fatal,Errors,Sources | Format-Table -AutoSize -Wrap
        Write-Host 'Direct reference: the error names the package, mod, or one of its declared target files.' -ForegroundColor DarkGray
        Write-Host 'Nearby activity only: the package was the last recognizable mod activity before the error. This is a lead, not proof.' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'Suspicious log lines:' -ForegroundColor Yellow
        foreach ($suspect in $analysis.Suspects) {
            if ($suspect.WorkshopID -and $suspect.WorkshopID -ne 'Unknown') {
                Write-Host "Workshop folder: $(Join-Path $Paths.WorkshopStage $suspect.WorkshopID)" -ForegroundColor Yellow
            }
            foreach ($line in @($suspect.Lines | Select-Object -First 8)) {
                $displayLine = [string]$line
                if ($displayLine.Length -gt 1200) { $displayLine = $displayLine.Substring(0, 1200) + '...' }
                Write-Host "[$($suspect.Package)] $displayLine" -ForegroundColor Red
            }
        }
    }

    if ($analysis.Unmapped.Count -gt 0) {
        Write-Host ''
        Write-Host 'Errors with no reliable Workshop package match:' -ForegroundColor Yellow
        $analysis.Unmapped | Select-Object -First 20 | ForEach-Object {
            $displayLine = [string]$_.Line
            if ($displayLine.Length -gt 1200) { $displayLine = $displayLine.Substring(0, 1200) + '...' }
            Write-Host "[$($_.SourceLabel)] $displayLine" -ForegroundColor Red
        }
        if ($analysis.Suspects.Count -eq 0) {
            Write-Host 'No individual mod can be named reliably from these records.' -ForegroundColor Yellow
        }
    }

    if ($analysis.Hints.Count -gt 0) {
        Write-Host ''
        Write-Host 'Runtime or environment clues:' -ForegroundColor Yellow
        foreach ($hint in $analysis.Hints) {
            Write-Host "  - $($hint.Finding)" -ForegroundColor Yellow
        }
    }

    if ($analysis.CrashArtifacts.Count -gt 0) {
        Write-Host ''
        Write-Host 'Recent Unreal crash artifacts:' -ForegroundColor Red
        foreach ($artifact in $analysis.CrashArtifacts) {
            Write-Host "  - $($artifact.Time.ToString('s'))  $($artifact.File)" -ForegroundColor Red
        }
        Write-Host 'Dump files prove that a native crash occurred, but this helper does not attempt to decode binary minidumps.' -ForegroundColor DarkGray
    }
}

function Show-ServerAudit {
    param([hashtable]$Paths)
    Write-Heading 'Windows dedicated-server audit'
    Write-Host 'This report does not change any files.' -ForegroundColor DarkGray

    $settings = Get-PalModSettingsState $Paths
    $externalDll = Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf
    $externalProxy = Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf
    $externalActive = $externalDll -and $externalProxy
    $workshopActive = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    $disabledWorkshop = $null -ne (Get-ChildItem -LiteralPath $Paths.WorkshopRuntime -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Select-Object -First 1)

    $globalValue = if ($null -eq $settings.GlobalEnable) { 'Not configured' } else { $settings.GlobalEnable }
    $globalEnabled = [string]$globalValue -match '^(?i:true)$'
    $allowClientMod = Get-WorldAllowClientMod $Paths
    $twoRuntimes = $externalActive -and $workshopActive
    $externalLayout = Test-Path -LiteralPath $Paths.ExternalLayout -PathType Leaf
    $workshopLayout = Test-Path -LiteralPath $Paths.WorkshopLayout -PathType Leaf

    Write-AuditValue 'Server folder' $Paths.Root
    Write-AuditValue 'PalModSettings.ini present' $settings.Exists $(if ($settings.Exists) { 'Good' } else { 'Bad' })
    Write-AuditValue 'bGlobalEnableMod' $globalValue $(if ($globalEnabled) { 'Good' } else { 'Bad' })
    Write-AuditValue 'ActiveModList entries' $settings.Active.Count $(if ($settings.Active.Count -gt 0) { 'Good' } else { 'Warning' })
    Write-AuditValue 'Configured WorkshopRootDir' $(if ($settings.WorkshopRoot) { $settings.WorkshopRoot } else { 'Default Mods\Workshop folder' })
    Write-AuditValue 'bAllowClientMod' $allowClientMod $(if ($allowClientMod -eq 'True') { 'Good' } else { 'Warning' })
    Write-AuditValue 'External UE4SS active' $externalActive $(if ($externalActive) { 'Good' } elseif ($workshopActive) { 'Neutral' } else { 'Bad' })
    Write-AuditValue 'External UE4SS.dll present' $externalDll $(if ($externalDll -eq $externalProxy) { $(if ($externalDll) { 'Good' } else { 'Neutral' }) } else { 'Bad' })
    Write-AuditValue 'dwmapi.dll proxy present' $externalProxy $(if ($externalDll -eq $externalProxy) { $(if ($externalProxy) { 'Good' } else { 'Neutral' }) } else { 'Bad' })
    Write-AuditValue 'Workshop UE4SS.dll active' $workshopActive $(if ($twoRuntimes) { 'Bad' } elseif ($workshopActive -or $externalActive) { 'Good' } else { 'Bad' })
    Write-AuditValue 'Disabled Workshop DLL found' $disabledWorkshop $(if ($externalActive -and $disabledWorkshop) { 'Good' } elseif ($externalActive) { 'Warning' } else { 'Neutral' })
    Write-AuditValue 'Two UE4SS runtimes active' $twoRuntimes $(if ($twoRuntimes) { 'Bad' } else { 'Good' })
    Write-AuditValue 'External MemberVariableLayout.ini present' $externalLayout $(if ($externalActive -and $externalLayout) { 'Good' } elseif ($externalActive) { 'Bad' } else { 'Neutral' })
    Write-AuditValue 'Workshop MemberVariableLayout.ini present' $workshopLayout $(if ($workshopActive -and $workshopLayout) { 'Good' } elseif ($workshopActive) { 'Bad' } else { 'Neutral' })

    if ($externalActive -and $workshopActive) {
        Write-Host 'CRITICAL: Both UE4SS runtimes appear active. Do not start the server until one is disabled.' -ForegroundColor Red
    } elseif ($externalDll -xor $externalProxy) {
        Write-Host 'WARNING: The external runtime is incomplete; UE4SS.dll and dwmapi.dll must be present together.' -ForegroundColor Yellow
    }
    if ((Get-WorldAllowClientMod $Paths) -ne 'True') {
        Write-Host 'NOTICE: Modded clients may be rejected unless bAllowClientMod is enabled for this server.' -ForegroundColor Yellow
    }

    Write-Heading 'Workshop package report'
    $report = @(Get-ServerPackageReport $Paths)
    if ($report.Count) {
        Write-ServerPackageReport $report
        foreach ($bad in $report | Where-Object Error) { Write-Host "Invalid metadata (Workshop $($bad.WorkshopID)): $($bad.Package): $($bad.Error)" -ForegroundColor Yellow }
    } else {
        Write-Host 'No Workshop package metadata was found in the configured server Workshop folders.' -ForegroundColor Yellow
    }

    Show-ServerLogAnalysis $Paths
}

function Invoke-GuidedServerDeployment {
    param([hashtable]$Paths, [string[]]$Packages)
    Assert-ServerClosed
    $externalActive = (Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf) -and (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf)
    $workshopActive = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    if ((Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf) -xor (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf)) {
        throw 'The external UE4SS runtime is incomplete. Repair it before starting PalServer.'
    }
    if ($externalActive -and $workshopActive) {
        Write-Host 'Both UE4SS runtimes are active. PalServer will not be started in this state.' -ForegroundColor Red
        if (Read-YesNo 'Run the synchronization action now so it can disable the Workshop runtime safely?') {
            Invoke-ServerSynchronization $Paths
        }
        $workshopActive = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
        if ($workshopActive) { throw 'The Workshop UE4SS.dll is still active. PalServer was not started.' }
    }

    $serverExe = Get-ServerExecutable $Paths
    $startedAt = Get-Date
    New-Item -ItemType Directory -Path $Paths.HelperLogs -Force | Out-Null
    $sessionName = "PalServer-session-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
    $consoleOutput = Join-Path $Paths.HelperLogs "$sessionName-stdout.log"
    $consoleErrors = Join-Path $Paths.HelperLogs "$sessionName-stderr.log"
    $sessionLogs = @($consoleOutput, $consoleErrors)

    Write-Heading 'Guided server deployment'
    Write-Host "Starting: $serverExe"
    Write-Host 'PalServer will open in its own window. Its standard output and errors are also captured for diagnosis.' -ForegroundColor DarkGray
    Write-Host "Console log: $consoleOutput" -ForegroundColor DarkGray
    Write-Host "Error log  : $consoleErrors" -ForegroundColor DarkGray
    $process = Start-Process -FilePath $serverExe -WorkingDirectory $Paths.Root -WindowStyle Normal -PassThru `
        -RedirectStandardOutput $consoleOutput -RedirectStandardError $consoleErrors

    $deadline = (Get-Date).AddMinutes(3)
    $ready = $false
    $earlyExit = $false
    $closedBeforeReady = $false
    $reportedErrors = $false
    $doubleRuntime = $false
    do {
        Start-Sleep -Seconds 2
        $running = @(Get-RunningServerProcesses)
        $missingManifests = @($Packages | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $Paths.ManagedRoot (Join-Path $_ 'InstallManifest.json')) -PathType Leaf)
        })
        $analysis = Get-ServerFullLogAnalysis $Paths $startedAt $sessionLogs
        if ($running.Count -eq 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge 8) {
            if ($missingManifests.Count -eq 0 -and $analysis.Errors.Count -eq 0 -and $analysis.CrashArtifacts.Count -eq 0) {
                $closedBeforeReady = $true
                $ready = $true
            } else {
                $earlyExit = $true
            }
            break
        }
        if ($externalActive -and (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf)) {
            $doubleRuntime = $true
            break
        }

        if ($analysis.Errors.Count -gt 0) {
            $reportedErrors = $true
            break
        }
        if ($missingManifests.Count -eq 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge 10) {
            $ready = $true
            break
        }
    } while ((Get-Date) -lt $deadline)

    if ($doubleRuntime) {
        Write-Host 'Palworld redeployed the Workshop UE4SS.dll while the external runtime was active.' -ForegroundColor Red
        Write-Host 'Shut the server down before using the synchronization action to disable the duplicate runtime.' -ForegroundColor Red
    } elseif ($closedBeforeReady) {
        Write-Host 'PalServer exited before the ten-second ready prompt.' -ForegroundColor Yellow
        Write-Host 'Deployment files are complete and no crash signature was found. If you closed the window yourself, this is expected.' -ForegroundColor Green
    } elseif ($earlyExit) {
        Write-Host 'PalServer stopped during startup.' -ForegroundColor Red
        Show-ServerLogAnalysis $Paths $startedAt $sessionLogs
    } elseif ($reportedErrors) {
        Write-Host 'The startup log contains one or more suspicious lines. The server was not stopped automatically.' -ForegroundColor Red
        Show-ServerLogAnalysis $Paths $startedAt $sessionLogs
    } elseif ($ready) {
        Write-Host 'All configured Workshop packages are deployed and no obvious startup error was detected.' -ForegroundColor Green
    } else {
        Write-Host 'The three-minute deployment wait expired. The server was not stopped automatically.' -ForegroundColor Yellow
        Show-ServerLogAnalysis $Paths $startedAt $sessionLogs
    }

    if (@(Get-RunningServerProcesses).Count -gt 0) {
        Write-Host ''
        Write-Host 'The server is still running. Test it now if needed.' -ForegroundColor Cyan
        Write-Host 'When finished, shut it down using your normal safe method (for example the official /Shutdown command), then press Enter here.' -ForegroundColor Yellow
        [void](Read-Host)
        if (@(Get-RunningServerProcesses).Count -gt 0) {
            Write-Host 'PalServer is still running. The helper will only perform the read-only audit.' -ForegroundColor Yellow
        } else {
            Start-Sleep -Seconds 1
            Write-Host 'PalServer has stopped. Running the final audit.' -ForegroundColor Green
        }
    }

    if ($ready -and @(Get-RunningServerProcesses).Count -eq 0 -and
        (Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf) -and
        (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf)) {
        $syncPlan = @(Get-ServerSyncPlan $Paths $Paths.ExternalMods)
        if (@($syncPlan | Where-Object Ready).Count -gt 0 -or (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf)) {
            Write-Host ''
            if (Read-YesNo 'Synchronize the deployed UE4SS mods into the external runtime now?') {
                Invoke-ServerSynchronization $Paths
            }
        }
    }
    Show-ServerAudit $Paths
}

function Set-PalModSettingsContent {
    param([hashtable]$Paths, [string[]]$Packages)
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Paths.PalModSettings -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $Paths.PalModSettings) { $lines.Add([string]$line) }
    }

    $headerIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[PalModSettings\]\s*$') { $headerIndex = $i; break }
    }
    if ($headerIndex -lt 0) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) { $lines.Add('') }
        $lines.Add('[PalModSettings]')
        $headerIndex = $lines.Count - 1
    }

    $sectionEnd = $lines.Count
    for ($i = $headerIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[.+\]\s*$') { $sectionEnd = $i; break }
    }

    $before = @($lines | Select-Object -First ($headerIndex + 1))
    $section = @($lines | Select-Object -Skip ($headerIndex + 1) -First ($sectionEnd - $headerIndex - 1))
    $after = @($lines | Select-Object -Skip $sectionEnd)

    $existingActive = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $cleanSection = New-Object System.Collections.Generic.List[string]
    foreach ($line in $section) {
        if ($line -match '^\s*bGlobalEnableMod\s*=') { continue }
        if ($line -match '^\s*ActiveModList\s*=\s*(.+?)\s*$') {
            $value = $matches[1].Trim().Trim('"')
            if ([string]::IsNullOrWhiteSpace($value) -or $existingActive.Contains($value)) { continue }
            [void]$existingActive.Add($value)
            $cleanSection.Add("ActiveModList=$value")
            continue
        }
        $cleanSection.Add($line)
    }

    foreach ($package in $Packages) {
        if ($existingActive.Add($package)) { $cleanSection.Add("ActiveModList=$package") }
    }

    $output = New-Object System.Collections.Generic.List[string]
    foreach ($line in $before) { $output.Add($line) }
    $output.Add('bGlobalEnableMod=true')
    foreach ($line in $cleanSection) { $output.Add($line) }
    foreach ($line in $after) { $output.Add($line) }

    New-Item -ItemType Directory -Path $Paths.ModsRoot -Force | Out-Null
    $output | Set-Content -LiteralPath $Paths.PalModSettings -Encoding UTF8
}

function Set-AllowClientMod {
    param([hashtable]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.WorldSettings -PathType Leaf)) {
        throw "PalWorldSettings.ini was not found: $($Paths.WorldSettings). Start the server once and configure it before enabling this option."
    }
    $raw = Get-Content -LiteralPath $Paths.WorldSettings -Raw
    $bounds = Get-OptionSettingsBounds $raw
    $content = $raw.Substring($bounds.Open + 1, $bounds.Close - $bounds.Open - 1)
    if ($content -match '(?i)\bbAllowClientMod\s*=\s*(True|False)') {
        $updatedContent = [regex]::Replace($content, '(?i)\bbAllowClientMod\s*=\s*(True|False)', 'bAllowClientMod=True')
    } else {
        $separator = if ([string]::IsNullOrWhiteSpace($content) -or $content.TrimEnd().EndsWith(',')) { '' } else { ',' }
        $updatedContent = $content + $separator + 'bAllowClientMod=True'
    }
    $updated = $raw.Substring(0, $bounds.Open + 1) + $updatedContent + $raw.Substring($bounds.Close)
    Set-Content -LiteralPath $Paths.WorldSettings -Value $updated -Encoding UTF8 -NoNewline
}

function Invoke-ServerConfiguration {
    param([hashtable]$Paths)
    $settings = Get-PalModSettingsState $Paths
    $records = @(Get-ServerWorkshopPackages $Paths | Where-Object { -not $_.Error -and $_.ServerRules.Count -gt 0 })
    if (-not $records.Count) { throw 'No server-compatible Workshop packages were found. Stage the Workshop items first, then try again.' }

    $packages = @($records.Package | Sort-Object -Unique)
    $missing = @($packages | Where-Object { -not $settings.Active.Contains($_) })

    Write-Heading 'Server configuration preview'
    Write-Host "PalModSettings.ini: $($Paths.PalModSettings)"
    Write-Host 'The helper will preserve existing entries, set bGlobalEnableMod=true, and add these server-compatible packages:'
    if ($missing.Count) { $missing | ForEach-Object { Write-Host "  - $_" } }
    else { Write-Host '  - No missing ActiveModList entries' -ForegroundColor DarkGray }
    Write-Host ''
    $enableClientMods = Read-YesNo 'Also set bAllowClientMod=True in PalWorldSettings.ini?'
    if ($enableClientMods) { Write-Host "World settings: $($Paths.WorldSettings)" }
    Write-Host ''
    if (-not (Read-YesNo 'Apply these server configuration changes?')) {
        Write-Host 'Configuration cancelled. No files were changed.'
        return
    }

    Assert-ServerClosed
    $backup = New-BackupRoot $Paths 'Configure'
    $hadPalModSettings = Test-Path -LiteralPath $Paths.PalModSettings -PathType Leaf
    $hadWorldSettings = Test-Path -LiteralPath $Paths.WorldSettings -PathType Leaf
    try {
        if ($hadPalModSettings) {
            Copy-Item -LiteralPath $Paths.PalModSettings -Destination (Join-Path $backup 'PalModSettings.ini')
        }
        if ($enableClientMods -and $hadWorldSettings) {
            Copy-Item -LiteralPath $Paths.WorldSettings -Destination (Join-Path $backup 'PalWorldSettings.ini')
        }
        Save-BackupManifest $backup 'Configure' @{ packages=$packages; enabledClientMods=$enableClientMods }
        Set-PalModSettingsContent $Paths $packages
        if ($enableClientMods) { Set-AllowClientMod $Paths }
        Write-Host ''
        Write-Host 'Server mod configuration updated successfully.' -ForegroundColor Green
        Write-Host "Backup: $backup"
        Write-Host 'PalServer must start once to deploy the configured packages.' -ForegroundColor Yellow
    } catch {
        Write-Host "Configuration failed: $($_.Exception.Message)" -ForegroundColor Red
        if (Test-Path -LiteralPath (Join-Path $backup 'PalModSettings.ini')) {
            Copy-Item -LiteralPath (Join-Path $backup 'PalModSettings.ini') -Destination $Paths.PalModSettings -Force
        } elseif (-not $hadPalModSettings -and (Test-Path -LiteralPath $Paths.PalModSettings -PathType Leaf)) {
            Remove-Item -LiteralPath $Paths.PalModSettings -Force
        }
        if (Test-Path -LiteralPath (Join-Path $backup 'PalWorldSettings.ini')) {
            Copy-Item -LiteralPath (Join-Path $backup 'PalWorldSettings.ini') -Destination $Paths.WorldSettings -Force
        }
        throw 'The server configuration was not completed. Previous files were restored where possible.'
    }

    Write-Host ''
    Write-Host 'The guided start uses PalServer.exe directly and does not add custom launch arguments.' -ForegroundColor DarkGray
    if (Read-YesNo 'Start PalServer now and monitor its deployment and startup log?') {
        Invoke-GuidedServerDeployment $Paths $packages
    } else {
        Write-Host 'Start the server yourself when ready, then run the audit after shutting it down.' -ForegroundColor DarkGray
    }
}

function Get-ExperimentalRelease {
    param([object]$Build)
    $api = "https://api.github.com/repos/$($Build.Owner)/$($Build.Repository)/releases/tags/$($Build.Tag)"
    Write-Host "Checking: $($Build.DisplayName)..."
    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = "Palworld-UE4SS-Server-Helper/$($script:HelperVersion)" }
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
        throw "Expected exactly one $($Build.AssetName) asset, but found $($assets.Count). No file was downloaded."
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
    if ($layouts.Count -ne 1) { throw "The archive does not contain exactly one supported dwmapi.dll plus ue4ss\UE4SS.dll layout. Found: $($layouts.Count)." }
    return $layouts[0]
}

function Get-ExperimentalPackage {
    param([object]$Build)
    $releaseInfo = Get-ExperimentalRelease $Build
    $asset = $releaseInfo.Asset
    $release = $releaseInfo.Release
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "Palworld-UE4SS-Server-Helper-$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $zipPath = Join-Path $tempRoot ([string]$asset.name)
    $extractPath = Join-Path $tempRoot 'extracted'
    try {
        Write-Host "Downloading: $($asset.name)"
        Invoke-WebRequest -Uri ([string]$asset.browser_download_url) -OutFile $zipPath -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = "Palworld-UE4SS-Server-Helper/$($script:HelperVersion)" }
        $actualLength = (Get-Item -LiteralPath $zipPath).Length
        if ($actualLength -ne [int64]$asset.size) { throw "Downloaded size mismatch. Expected $($asset.size), received $actualLength bytes." }
        $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($asset.PSObject.Properties.Name -contains 'digest' -and -not [string]::IsNullOrWhiteSpace([string]$asset.digest)) {
            $expectedHash = ([string]$asset.digest -replace '^(?i)sha256:', '').ToUpperInvariant()
            if ($hash -ne $expectedHash) { throw "SHA-256 mismatch. Expected $expectedHash, received $hash." }
        }
        if ($hash -ne $Build.TrustedSha256) {
            throw "The release archive has changed since this helper was reviewed. Expected $($Build.TrustedSha256), received $hash. Download an updated helper release."
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
        if ($relative -ieq 'UE4SS-settings.ini' -and (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
    }
}

function Ensure-PreparedMemberVariableLayout {
    param([hashtable]$Paths, [string]$PreparedRoot)
    $destination = Join-Path $PreparedRoot 'MemberVariableLayout.ini'
    if (Test-Path -LiteralPath $destination -PathType Leaf) { return 'Included in the selected archive' }
    foreach ($source in @($Paths.WorkshopLayout, $Paths.ExternalLayout)) {
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination $destination -Force
            if (Test-Path -LiteralPath $destination -PathType Leaf) { return "Preserved from: $source" }
        }
    }
    throw 'MemberVariableLayout.ini is missing from the archive, the Workshop runtime and the current external runtime.'
}

function Get-ServerSyncPlan {
    param([hashtable]$Paths, [string]$DestinationMods)
    $records = @(Get-ServerWorkshopPackages $Paths | Where-Object { -not $_.Error -and $_.ServerRules.Count -gt 0 })
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($record in $records) {
        foreach ($type in $record.ServerTypes) {
            $source = $null
            $destination = $null
            $handled = $false
            if ($type -ieq 'Lua' -and $record.Package -ine 'UE4SSExperimentalPW') {
                $source = Join-Path $Paths.WorkshopMods $record.Package
                $destination = Join-Path $DestinationMods $record.Package
                $handled = $true
            } elseif ($type -ieq 'PalSchema') {
                $source = Join-Path $Paths.WorkshopMods (Join-Path 'PalSchema\mods' $record.Package)
                $destination = Join-Path $DestinationMods (Join-Path 'PalSchema\mods' $record.Package)
                $handled = $true
            }
            if ($handled) {
                $plan.Add([pscustomobject]@{
                    Mod=$record.ModName
                    Package=$record.Package
                    Type=$type
                    Source=$source
                    Destination=$destination
                    Ready=Test-Path -LiteralPath $source -PathType Container
                    Result=$(if (Test-Path -LiteralPath $source -PathType Container) { 'Ready to synchronize' } else { 'Not deployed; restart the server once' })
                })
            }
        }
    }
    return $plan.ToArray()
}

function Copy-ServerSyncPlan {
    param([object[]]$Plan)
    foreach ($item in $Plan | Where-Object Ready) {
        $modsRoot = if ($item.Type -ieq 'Lua') { Split-Path -Parent $item.Destination } else { $null }
        $modsTxtState = if ($modsRoot) { Get-Ue4ssModsTxtState $modsRoot $item.Package } else { 'NotListed' }
        Copy-Directory $item.Source $item.Destination
        if ($item.Type -ieq 'Lua') {
            $mainLua = Join-Path $item.Destination 'Scripts\main.lua'
            $mainDll = Join-Path $item.Destination 'dlls\main.dll'
            $enabled = Join-Path $item.Destination 'enabled.txt'
            if ($modsTxtState -eq 'ModsTxtDisabled' -and (Test-Path -LiteralPath $enabled -PathType Leaf)) {
                Remove-Item -LiteralPath $enabled -Force
            }
            $activation = Get-Ue4ssModActivationState $modsRoot $item.Package
            if (((Test-Path -LiteralPath $mainLua -PathType Leaf) -or (Test-Path -LiteralPath $mainDll -PathType Leaf)) -and
                $activation -in @('NotEnabled','Unknown')) {
                New-Item -ItemType File -Path $enabled | Out-Null
            }
        }
    }
}

function Disable-WorkshopServerDll {
    param([hashtable]$Paths)
    if (-not (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf)) { return $null }
    $disabled = "$($Paths.WorkshopDll).workshop-disabled"
    if (Test-Path -LiteralPath $disabled) { $disabled += ".$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    Move-Item -LiteralPath $Paths.WorkshopDll -Destination $disabled
    return $disabled
}

function Show-InstallPreview {
    param([hashtable]$Paths, [object]$Package)
    Write-Heading 'Dedicated-server installation preview'
    Write-Host "Server folder: $($Paths.Root)"
    Write-Host "Build        : $($Package.BuildName)"
    Write-Host "Source       : $($Package.DownloadUrl)"
    Write-Host "Asset        : $($Package.AssetName)"
    Write-Host "SHA-256      : $($Package.Sha256)"
    Write-Host ''
    Write-Host 'The helper will:'
    Write-Host '  - preserve the current external runtime, mods and settings in a timestamped backup;'
    Write-Host '  - install a clean reviewed Experimental UE4SS archive beside the server executable;'
    Write-Host '  - copy already deployed server-compatible Lua and PalSchema packages into that runtime;'
    Write-Host '  - verify MemberVariableLayout.ini;'
    Write-Host '  - disable the deployed Workshop UE4SS.dll without deleting it;'
    Write-Host '  - leave LogicMods and Paks under Palworld server management.'
    Write-Host ''
    Write-Host 'No directory junction is created on the dedicated server.' -ForegroundColor Yellow
}

function Install-ExperimentalServerPackage {
    param([hashtable]$Paths, [object]$Package)
    Assert-ServerClosed
    $backup = New-BackupRoot $Paths 'Install'
    $state = @{
        OldRuntimeMoved=$false
        OldProxyMoved=$false
        NewRuntimeInstalled=$false
        NewProxyInstalled=$false
        WorkshopDllDisabled=$false
        DisabledDllPath=$null
    }
    try {
        Save-BackupManifest $backup 'Install' @{
            sourceBuild=$Package.BuildKey
            sourceRepository=$Package.Repository
            sourceTag=$Package.Tag
            sourceAsset=$Package.AssetName
            sourceSha256=$Package.Sha256
        }
        $preparedRoot = Join-Path $backup 'PreparedExternalRuntime'
        $preparedMods = Join-Path $preparedRoot 'Mods'
        New-Item -ItemType Directory -Path $preparedRoot | Out-Null

        if (Test-Path -LiteralPath $Paths.ExternalRoot -PathType Container) {
            Copy-Directory $Paths.ExternalMods $preparedMods
            $existingSettings = Join-Path $Paths.ExternalRoot 'UE4SS-settings.ini'
            if (Test-Path -LiteralPath $existingSettings -PathType Leaf) {
                Copy-Item -LiteralPath $existingSettings -Destination (Join-Path $preparedRoot 'UE4SS-settings.ini') -Force
            }
        }
        Copy-Ue4ssOverlay $Package.Layout.Ue4ssSource $preparedRoot
        $layoutResult = Ensure-PreparedMemberVariableLayout $Paths $preparedRoot
        Write-Host "MemberVariableLayout.ini: $layoutResult" -ForegroundColor DarkGray
        Save-RuntimeRecord (Join-Path $preparedRoot 'Palworld-UE4SS-Helper-runtime.json') $Package 'WindowsDedicatedServer'
        New-Item -ItemType Directory -Path $preparedMods -Force | Out-Null
        $syncPlan = @(Get-ServerSyncPlan $Paths $preparedMods)
        Copy-ServerSyncPlan $syncPlan

        if (-not (Test-Path -LiteralPath (Join-Path $preparedRoot 'UE4SS.dll') -PathType Leaf)) {
            throw 'The prepared runtime does not contain UE4SS.dll.'
        }
        if (Test-Path -LiteralPath $Paths.ExternalRoot -PathType Container) {
            Move-Item -LiteralPath $Paths.ExternalRoot -Destination (Join-Path $backup 'PreviousExternalRuntime')
            $state.OldRuntimeMoved = $true
        }
        if (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf) {
            Move-Item -LiteralPath $Paths.ExternalProxy -Destination (Join-Path $backup 'Previous-dwmapi.dll')
            $state.OldProxyMoved = $true
        }
        Move-Item -LiteralPath $preparedRoot -Destination $Paths.ExternalRoot
        $state.NewRuntimeInstalled = $true
        Copy-Item -LiteralPath $Package.Layout.ProxySource -Destination $Paths.ExternalProxy -Force
        $state.NewProxyInstalled = $true
        $disabled = Disable-WorkshopServerDll $Paths
        if ($disabled) {
            $state.WorkshopDllDisabled = $true
            $state.DisabledDllPath = $disabled
        }

        if (-not (Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf) -or
            -not (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf) -or
            -not (Test-Path -LiteralPath $Paths.ExternalLayout -PathType Leaf)) {
            throw 'External UE4SS verification failed after installation.'
        }
        Write-Host ''
        Write-Host 'Experimental UE4SS was installed for the Windows dedicated server.' -ForegroundColor Green
        Write-Host "Backup: $backup"
        Write-Host 'Run the audit after every Workshop deployment to make sure the Workshop DLL was not reactivated.' -ForegroundColor Yellow
    } catch {
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Attempting to restore the previous state...' -ForegroundColor Yellow
        try {
            if ($state.WorkshopDllDisabled -and (Test-Path -LiteralPath $state.DisabledDllPath) -and -not (Test-Path -LiteralPath $Paths.WorkshopDll)) {
                Move-Item -LiteralPath $state.DisabledDllPath -Destination $Paths.WorkshopDll
            }
            if ($state.NewRuntimeInstalled -and (Test-Path -LiteralPath $Paths.ExternalRoot -PathType Container)) {
                Move-Item -LiteralPath $Paths.ExternalRoot -Destination (Join-Path $backup 'FailedExternalRuntime')
            }
            if ($state.OldRuntimeMoved -and (Test-Path -LiteralPath (Join-Path $backup 'PreviousExternalRuntime'))) {
                Move-Item -LiteralPath (Join-Path $backup 'PreviousExternalRuntime') -Destination $Paths.ExternalRoot
            }
            if ($state.NewProxyInstalled -and (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf)) {
                Move-Item -LiteralPath $Paths.ExternalProxy -Destination (Join-Path $backup 'Failed-dwmapi.dll') -Force
            }
            if ($state.OldProxyMoved -and (Test-Path -LiteralPath (Join-Path $backup 'Previous-dwmapi.dll'))) {
                Move-Item -LiteralPath (Join-Path $backup 'Previous-dwmapi.dll') -Destination $Paths.ExternalProxy
            }
            Write-Host 'Previous state restored. Failed files remain in the backup.' -ForegroundColor Yellow
        } catch {
            Write-Host "Automatic rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Do not start the server. Inspect: $backup" -ForegroundColor Red
        }
        throw 'The dedicated-server UE4SS installation was not completed.'
    }
}

function Select-ExperimentalBuild {
    while ($true) {
        Clear-Host
        Write-Heading 'Choose the dedicated-server UE4SS build'
        Write-Host '1. Palworld-specific Experimental build (recommended for PalSchema)'
        Write-Host '2. Official Experimental build'
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

function Invoke-AutomaticServerInstall {
    $build = Select-ExperimentalBuild
    if ($null -eq $build) { return }
    $paths = Get-ServerPaths
    $package = $null
    try {
        $package = Get-ExperimentalPackage $build
        Show-InstallPreview $paths $package
        Write-Host ''
        Write-Host 'This workflow is for a local Windows dedicated server, not the normal game client.' -ForegroundColor Yellow
        if (Read-YesNo 'Install or update Experimental UE4SS on this server?') {
            Install-ExperimentalServerPackage $paths $package
        } else {
            Write-Host 'Installation cancelled. No server files were changed.'
        }
    } finally {
        if ($null -ne $package -and (Test-Path -LiteralPath $package.TempRoot)) {
            Remove-Item -LiteralPath $package.TempRoot -Recurse -Force
        }
    }
}

function Invoke-ServerSynchronization {
    param([hashtable]$Paths)
    $externalDll = Test-Path -LiteralPath $Paths.ExternalDll -PathType Leaf
    $externalProxy = Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf
    $workshopDll = Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf
    if ($externalDll -xor $externalProxy) {
        throw 'The external UE4SS installation is incomplete: UE4SS.dll and dwmapi.dll must be present together. Repair or restore the runtime before synchronizing.'
    }
    if (-not $externalDll -and -not $externalProxy) {
        Write-Heading 'Dedicated-server synchronization'
        if ($workshopDll) {
            Write-Host 'Nothing needs to be synchronized while the Workshop UE4SS runtime is active.' -ForegroundColor Green
            Write-Host 'Palworld already deploys compatible Lua and PalSchema content into the Workshop runtime folders.' -ForegroundColor DarkGray
            Write-Host 'This action is only needed when an external Experimental UE4SS runtime is installed.' -ForegroundColor DarkGray
        } else {
            Write-Host 'No active external or Workshop UE4SS runtime was found.' -ForegroundColor Yellow
            Write-Host 'Install an external Experimental runtime or restore the Workshop runtime before using UE4SS mods.' -ForegroundColor DarkGray
        }
        return
    }
    $plan = @(Get-ServerSyncPlan $Paths $Paths.ExternalMods)
    Write-Heading 'Dedicated-server synchronization preview'
    if ($plan.Count) { $plan | Sort-Object Package,Type | Select-Object Mod,Package,Type,Result | Format-Table -AutoSize -Wrap }
    else { Write-Host 'No server-compatible Lua or PalSchema packages were found.' }

    $workshopDllActive = $workshopDll
    if ($workshopDllActive) {
        Write-Host ''
        Write-Host 'The Workshop UE4SS.dll is active again and would be disabled to prevent a double runtime.' -ForegroundColor Yellow
    }
    if ((@($plan | Where-Object Ready).Count -eq 0) -and -not $workshopDllActive) { return }
    if (-not (Read-YesNo 'Apply the pending dedicated-server synchronization changes?')) { return }

    Assert-ServerClosed
    $backup = New-BackupRoot $Paths 'Synchronize'
    try {
        if (Test-Path -LiteralPath $Paths.ExternalMods -PathType Container) {
            Copy-Directory $Paths.ExternalMods (Join-Path $backup 'PreviousExternalMods')
        }
        Save-BackupManifest $backup 'Synchronize' @{}
        Copy-ServerSyncPlan $plan
        [void](Disable-WorkshopServerDll $Paths)
        Write-Host ''
        Write-Host 'Server-compatible UE4SS mod content synchronized successfully.' -ForegroundColor Green
        Write-Host "Backup: $backup"
    } catch {
        Write-Host "Synchronization failed: $($_.Exception.Message)" -ForegroundColor Red
        try {
            if (Test-Path -LiteralPath $Paths.ExternalMods -PathType Container) {
                Move-Item -LiteralPath $Paths.ExternalMods -Destination (Join-Path $backup 'FailedExternalMods')
            }
            if (Test-Path -LiteralPath (Join-Path $backup 'PreviousExternalMods') -PathType Container) {
                Move-Item -LiteralPath (Join-Path $backup 'PreviousExternalMods') -Destination $Paths.ExternalMods
            }
        } catch {
            Write-Host "Synchronization rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        throw 'The dedicated-server mod synchronization was not completed.'
    }
}

function Show-RestorePreview {
    param([hashtable]$Paths)
    Write-Heading 'Dedicated-server restoration preview'
    Write-Host 'The helper will:'
    Write-Host '  - move the external UE4SS runtime and dwmapi.dll into a timestamped backup;'
    Write-Host '  - reactivate the most recently disabled Workshop UE4SS.dll when available;'
    Write-Host '  - leave the server Workshop deployment and PalModSettings.ini untouched.'
    Write-Host ''
    Write-Host 'This restores the Workshop runtime even if that runtime is currently incompatible.' -ForegroundColor Yellow
}

function Restore-WorkshopServerRuntime {
    param([hashtable]$Paths)
    Assert-ServerClosed
    $disabled = Get-ChildItem -LiteralPath $Paths.WorkshopRuntime -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not (Test-Path -LiteralPath $Paths.ExternalRoot -PathType Container) -and
        -not (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf) -and
        $null -eq $disabled) {
        throw 'No external runtime or disabled Workshop UE4SS.dll was found.'
    }

    $backup = New-BackupRoot $Paths 'Restore'
    $state = @{ RuntimeMoved=$false; ProxyMoved=$false; WorkshopRestored=$false; DisabledPath=$null }
    try {
        Save-BackupManifest $backup 'Restore' @{}
        if (Test-Path -LiteralPath $Paths.ExternalRoot -PathType Container) {
            Move-Item -LiteralPath $Paths.ExternalRoot -Destination (Join-Path $backup 'RemovedExternalRuntime')
            $state.RuntimeMoved = $true
        }
        if (Test-Path -LiteralPath $Paths.ExternalProxy -PathType Leaf) {
            Move-Item -LiteralPath $Paths.ExternalProxy -Destination (Join-Path $backup 'Removed-dwmapi.dll')
            $state.ProxyMoved = $true
        }
        if (-not (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf) -and $null -ne $disabled) {
            Move-Item -LiteralPath $disabled.FullName -Destination $Paths.WorkshopDll
            $state.WorkshopRestored = $true
            $state.DisabledPath = $disabled.FullName
        }
        Write-Host ''
        Write-Host 'The dedicated server was restored to its Workshop UE4SS layout.' -ForegroundColor Green
        Write-Host "External runtime backup: $backup"
    } catch {
        Write-Host "Restoration failed: $($_.Exception.Message)" -ForegroundColor Red
        try {
            if ($state.WorkshopRestored -and (Test-Path -LiteralPath $Paths.WorkshopDll -PathType Leaf)) {
                Move-Item -LiteralPath $Paths.WorkshopDll -Destination $state.DisabledPath
            }
            if ($state.RuntimeMoved -and (Test-Path -LiteralPath (Join-Path $backup 'RemovedExternalRuntime'))) {
                Move-Item -LiteralPath (Join-Path $backup 'RemovedExternalRuntime') -Destination $Paths.ExternalRoot
            }
            if ($state.ProxyMoved -and (Test-Path -LiteralPath (Join-Path $backup 'Removed-dwmapi.dll'))) {
                Move-Item -LiteralPath (Join-Path $backup 'Removed-dwmapi.dll') -Destination $Paths.ExternalProxy
            }
        } catch {
            Write-Host "Restoration rollback also failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        throw 'The Workshop server runtime restoration was not completed.'
    }
}

function Initialize-ServerRoot {
    if (Test-ServerRoot $script:ServerRoot) { return }
    $saved = Get-SavedServerRoot
    if ($saved) { $script:ServerRoot = $saved; return }
    $found = @(Find-PalServerInstallations)
    if ($found.Count -eq 1) {
        $script:ServerRoot = $found[0]
        Save-ServerRootSelection $script:ServerRoot
    }
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

function Show-ServerInstructions {
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host '                     INSTRUCTIONS / READ ME' -ForegroundColor Yellow
    Write-Host ('=' * 72) -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'FIRST INSTALLATION' -ForegroundColor Cyan
    Write-Host '  1. Stop PalServer completely and use option 1 for the initial audit.'
    Write-Host '  2. Use option 2 to configure server-compatible Workshop packages.'
    Write-Host '  3. Let the guided start deploy them, test the server, then shut it down safely.'
    Write-Host '  4. Use option 3 to install the Palworld-specific Experimental build.'
    Write-Host '  5. Run option 1 again, start the server and test a client connection.'
    Write-Host ''
    Write-Host 'AFTER ADDING OR UPDATING WORKSHOP MODS' -ForegroundColor Cyan
    Write-Host '  Run option 2, let PalServer deploy the packages, shut it down, then use option 4 when an external runtime is active.'
    Write-Host '  Always audit again: Workshop deployment may reactivate its UE4SS.dll.'
    Write-Host ''
    Write-Host 'IMPORTANT' -ForegroundColor Cyan
    Write-Host '  Active=True only means the package is listed in PalModSettings.ini. Check RuntimeState and the log diagnosis too.'
    Write-Host '  Option 5 restores the Workshop runtime. LogicMods and Paks remain managed by Palworld.'
    Write-Host '  The helper never force-stops PalServer and creates timestamped backups before changes.'
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

### SERVER HELPER ENTRYPOINT ###
try {
    $Host.UI.RawUI.WindowTitle = "Palworld UE4SS Dedicated Server Helper v$($script:HelperVersion)"
    Initialize-ServerRoot
    $finished = $false
    while (-not $finished) {
        Clear-Host
        Write-Host "Palworld UE4SS Dedicated Server Helper v$($script:HelperVersion)" -ForegroundColor Cyan
        Write-Host 'Local Windows dedicated servers only' -ForegroundColor DarkGray
        Write-Host 'By ZdradaKali (GitHub) / Yani Neco (Steam) / hess_ch (Discord)' -ForegroundColor DarkMagenta
        Write-Host ''
        if (Test-ServerRoot $script:ServerRoot) {
            $homePaths = Get-ServerPaths
            $runtime = Get-InstalledRuntimeSummary $homePaths
            Write-Host "Selected server: $($script:ServerRoot)" -ForegroundColor DarkGray
            Write-Host 'Installed UE4SS: ' -NoNewline -ForegroundColor DarkGray
            Write-Host $runtime.Text -ForegroundColor $runtime.Color
            Write-Host ''
        } else {
            Write-Host 'Selected server: Not selected yet' -ForegroundColor DarkGray
            Write-Host 'Installed UE4SS: Select a server first' -ForegroundColor DarkGray
            Write-Host ''
        }
        Write-Host '1. Audit the current dedicated-server setup'
        Write-Host '2. Configure server-compatible Workshop packages'
        Write-Host '3. Install or update Experimental UE4SS on the server'
        Write-Host '4. Synchronize deployed server UE4SS mods (external runtime only)'
        Write-Host '5. Restore the Workshop UE4SS server runtime'
        Write-Host '6. Select a different PalServer installation folder'
        Write-Host '7. >>> INSTRUCTIONS / READ ME <<<' -ForegroundColor Yellow
        Write-Host '8. Exit'
        Write-Host ''
        switch ((Read-Host 'Choose an option').Trim()) {
            '1' { Invoke-MenuAction { Show-ServerAudit (Get-ServerPaths) } }
            '2' { Invoke-MenuAction { Invoke-ServerConfiguration (Get-ServerPaths) } }
            '3' { Invoke-MenuAction { Invoke-AutomaticServerInstall } }
            '4' { Invoke-MenuAction { Invoke-ServerSynchronization (Get-ServerPaths) } }
            '5' { Invoke-MenuAction { $p=Get-ServerPaths; Show-RestorePreview $p; if (Read-YesNo 'Restore the Workshop UE4SS server runtime now?') { Restore-WorkshopServerRuntime $p } else { Write-Host 'Restoration cancelled. No server files were changed.' } } }
            '6' { Invoke-MenuAction { $script:ServerRoot=$null; Select-ServerRoot -ForceChoice; Write-Host "Selected: $($script:ServerRoot)" -ForegroundColor Green } }
            '7' { Invoke-MenuAction { Show-ServerInstructions } }
            '8' { $finished = $true }
            default { }
        }
    }
} catch {
    Write-Host ''
    Write-Host "FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
