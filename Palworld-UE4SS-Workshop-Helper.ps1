[CmdletBinding()]
param(
    [ValidateSet('Status', 'Setup', 'Sync', 'Restore')]
    [string]$Action = 'Status',
    [string]$GameRoot,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-GameRoot {
    param([string]$RequestedRoot)
    if ([string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $RequestedRoot = Read-Host 'Paste the Palworld installation folder path'
    }
    $root = $RequestedRoot.Trim().Trim('"').TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $root 'Pal\Binaries\Win64') -PathType Container)) {
        throw "This does not appear to be a valid Palworld installation folder: $root"
    }
    return [IO.Path]::GetFullPath($root)
}

function Test-IsJunction {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($null -ne $item -and $item.LinkType -eq 'Junction')
}

function Assert-JunctionTarget {
    param([string]$Path, [string]$ExpectedTarget)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.LinkType -ne 'Junction') { throw "Expected a junction: $Path" }
    $target = [IO.Path]::GetFullPath([string]@($item.Target)[0]).TrimEnd('\')
    $expected = [IO.Path]::GetFullPath($ExpectedTarget).TrimEnd('\')
    if ($target -ine $expected) { throw "The junction points to '$target' instead of '$expected'." }
}

function Copy-DirectorySafely {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1
    $code = $LASTEXITCODE
    if ($code -ge 8) { throw "Robocopy failed with exit code $code while copying '$Source'." }
}

function Get-SafePackageName {
    param([object]$Value, [string]$InfoPath)
    $name = [string]$Value
    if ([string]::IsNullOrWhiteSpace($name) -or
        $name -in @('.', '..') -or
        $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $name.Contains('\') -or $name.Contains('/') -or [IO.Path]::IsPathRooted($name)) {
        throw "Unsafe or invalid PackageName in '$InfoPath': '$name'"
    }
    return $name
}

function Show-Status {
    param([hashtable]$P)
    $junction = Test-IsJunction $P.WorkshopMods
    [pscustomobject]@{
        'GitHub proxy present' = Test-Path -LiteralPath $P.GitHubProxy -PathType Leaf
        'GitHub runtime present' = Test-Path -LiteralPath $P.GitHubDll -PathType Leaf
        'Workshop DLL active' = Test-Path -LiteralPath $P.WorkshopDll -PathType Leaf
        'Workshop DLL disabled' = $null -ne (Get-ChildItem -LiteralPath $P.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        'Mods junction present' = $junction
    } | Format-List
    if ($junction) { Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods }
}

function Invoke-Setup {
    param([hashtable]$P, [bool]$DoApply)
    if (-not (Test-Path -LiteralPath $P.GitHubDll -PathType Leaf)) {
        throw "GitHub UE4SS was not found. Extract it first: $($P.GitHubDll)"
    }
    if (-not (Test-Path -LiteralPath $P.WorkshopRoot -PathType Container)) {
        throw "Workshop UE4SS was not found: $($P.WorkshopRoot)"
    }
    if (Test-IsJunction $P.WorkshopMods) {
        Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods
        Write-Host 'The Mods junction is already configured correctly.'
    } else {
        Write-Host "Would merge: $($P.WorkshopMods) -> $($P.GitHubMods)"
        Write-Host "Would replace the Workshop Mods directory with a junction."
        if ($DoApply) {
            New-Item -ItemType Directory -Path $P.GitHubMods -Force | Out-Null
            if (Test-Path -LiteralPath $P.WorkshopMods -PathType Container) {
                Copy-DirectorySafely $P.WorkshopMods $P.GitHubMods
                $backup = "$($P.WorkshopMods).pre-junction-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Move-Item -LiteralPath $P.WorkshopMods -Destination $backup
                try {
                    New-Item -ItemType Junction -Path $P.WorkshopMods -Target $P.GitHubMods | Out-Null
                    Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods
                } catch {
                    if (Test-Path -LiteralPath $P.WorkshopMods) { & cmd.exe /d /c rmdir "$($P.WorkshopMods)" | Out-Null }
                    Move-Item -LiteralPath $backup -Destination $P.WorkshopMods
                    throw
                }
                Write-Host "Original Workshop Mods directory preserved at: $backup"
            } else {
                New-Item -ItemType Junction -Path $P.WorkshopMods -Target $P.GitHubMods | Out-Null
                Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods
            }
        }
    }
    if (Test-Path -LiteralPath $P.WorkshopDll -PathType Leaf) {
        $disabled = "$($P.WorkshopDll).workshop-disabled"
        if (Test-Path -LiteralPath $disabled) { $disabled += ".$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
        Write-Host "Would disable Workshop runtime: $($P.WorkshopDll) -> $disabled"
        if ($DoApply) { Move-Item -LiteralPath $P.WorkshopDll -Destination $disabled }
    } else {
        Write-Host 'Workshop UE4SS.dll is already absent or disabled.'
    }
}

function Invoke-Sync {
    param([hashtable]$P, [bool]$DoApply)
    foreach ($required in @($P.ManagedRoot, $P.GitHubMods, $P.WorkshopMods)) {
        if (-not (Test-Path -LiteralPath $required -PathType Container)) { throw "Required directory not found: $required" }
    }
    Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods
    $internal = @('UE4SSExperimentalPW','BPML_GenericFunctions','BPModLoaderMod','CheatManagerEnablerMod','ConsoleCommandsMod','ConsoleEnablerMod','Keybinds','LineTraceMod','SplitScreenMod','PalSchema','shared')
    $results = foreach ($managed in Get-ChildItem -LiteralPath $P.ManagedRoot -Directory) {
        $infoPath = Join-Path $managed.FullName 'Info.json'
        if (-not (Test-Path -LiteralPath $infoPath -PathType Leaf)) { continue }
        try {
            $info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
            $types = @($info.InstallRule | ForEach-Object Type | Select-Object -Unique)
            $package = Get-SafePackageName $info.PackageName $infoPath
            if ('Lua' -notin $types -or $package -in $internal) { continue }
            $destination = Join-Path $P.GitHubMods $package
            $mainLua = Join-Path $destination 'Scripts\main.lua'
            $mainDll = Join-Path $destination 'dlls\main.dll'
            $enabled = Join-Path $destination 'enabled.txt'
            if (-not (Test-Path -LiteralPath $mainLua -PathType Leaf) -and -not (Test-Path -LiteralPath $mainDll -PathType Leaf)) {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Content not deployed yet; launch Palworld once' }; continue
            }
            if (Test-Path -LiteralPath $enabled -PathType Leaf) {
                [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result='Already enabled' }; continue
            }
            if ($DoApply) { New-Item -ItemType File -Path $enabled -ErrorAction Stop | Out-Null }
            [pscustomobject]@{ Mod=$info.ModName; Package=$package; Result=$(if ($DoApply) {'enabled.txt created'} else {'Would create enabled.txt'}) }
        } catch {
            [pscustomobject]@{ Mod=$managed.Name; Package=''; Result="Skipped: $($_.Exception.Message)" }
        }
    }
    if ($null -eq $results) { Write-Host 'No applicable Workshop UE4SS mods were found.' }
    else { $results | Sort-Object Package | Format-Table -AutoSize -Wrap }
}

function Invoke-Restore {
    param([hashtable]$P, [bool]$DoApply)
    if (-not (Test-Path -LiteralPath $P.GitHubMods -PathType Container)) { throw "GitHub Mods directory not found: $($P.GitHubMods)" }
    $disabled = Get-ChildItem -LiteralPath $P.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not (Test-Path -LiteralPath $P.WorkshopDll -PathType Leaf) -and $null -eq $disabled) {
        throw 'No active or disabled Workshop UE4SS.dll was found. Reinstall or update the Workshop mod first.'
    }
    if (Test-IsJunction $P.WorkshopMods) { Assert-JunctionTarget $P.WorkshopMods $P.GitHubMods }
    elseif (Test-Path -LiteralPath $P.WorkshopMods) { throw "The Workshop Mods path is not the expected junction: $($P.WorkshopMods)" }
    $backupRoot = Join-Path $P.Root "_UE4SS-GitHub-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Would back up GitHub UE4SS and mods to: $backupRoot"
    Write-Host 'Would remove the junction, restore a normal Workshop Mods directory, and reactivate the Workshop DLL.'
    if (-not $DoApply) { return }
    $backupMods = Join-Path $backupRoot 'Mods'
    Copy-DirectorySafely $P.GitHubMods $backupMods
    if (Test-IsJunction $P.WorkshopMods) {
        & cmd.exe /d /c rmdir "$($P.WorkshopMods)"
        if ($LASTEXITCODE -ne 0 -or (Test-Path -LiteralPath $P.WorkshopMods)) { throw 'The Mods junction could not be removed.' }
    }
    New-Item -ItemType Directory -Path $P.WorkshopMods -Force | Out-Null
    Copy-DirectorySafely $backupMods $P.WorkshopMods
    if (-not (Test-Path -LiteralPath $P.WorkshopDll -PathType Leaf)) { Move-Item -LiteralPath $disabled.FullName -Destination $P.WorkshopDll }
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    if (Test-Path -LiteralPath $P.GitHubProxy -PathType Leaf) { Move-Item -LiteralPath $P.GitHubProxy -Destination $backupRoot }
    if (Test-Path -LiteralPath $P.GitHubRoot -PathType Container) { Move-Item -LiteralPath $P.GitHubRoot -Destination (Join-Path $backupRoot 'ue4ss') }
    Write-Host "Workshop UE4SS restored. Backup: $backupRoot"
}

$root = Get-GameRoot $GameRoot
$paths = @{
    Root=$root
    ManagedRoot=Join-Path $root 'Mods\ManagedMods'
    WorkshopRoot=Join-Path $root 'Mods\NativeMods\UE4SS'
    WorkshopMods=Join-Path $root 'Mods\NativeMods\UE4SS\Mods'
    WorkshopDll=Join-Path $root 'Mods\NativeMods\UE4SS\UE4SS.dll'
    GitHubRoot=Join-Path $root 'Pal\Binaries\Win64\ue4ss'
    GitHubMods=Join-Path $root 'Pal\Binaries\Win64\ue4ss\Mods'
    GitHubDll=Join-Path $root 'Pal\Binaries\Win64\ue4ss\UE4SS.dll'
    GitHubProxy=Join-Path $root 'Pal\Binaries\Win64\dwmapi.dll'
}

Write-Host "`nPalworld folder: $root"
Write-Host "Action: $Action"
Write-Host $(if ($Apply) {'Mode: APPLY - changes are enabled'} else {'Mode: PREVIEW - no changes will be made'})
Write-Host ''

switch ($Action) {
    'Status'  { Show-Status $paths }
    'Setup'   { Invoke-Setup $paths ([bool]$Apply) }
    'Sync'    { Invoke-Sync $paths ([bool]$Apply) }
    'Restore' { Invoke-Restore $paths ([bool]$Apply) }
}

if (-not $Apply -and $Action -ne 'Status') { Write-Host "`nPreview complete. Run the matching APPLY launcher only after reviewing the output." }
