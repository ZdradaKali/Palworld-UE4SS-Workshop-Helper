$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Get-EmbeddedPayloadDefinitions {
    param([string]$Path, [string]$EntryPointMarker)
    $content = [IO.File]::ReadAllText((Resolve-Path $Path))
    $payloadMarker = '### POWERSHELL PAYLOAD ###'
    $payloadIndex = $content.LastIndexOf($payloadMarker)
    if ($payloadIndex -lt 0) { throw "Payload marker not found in $Path" }
    $payload = $content.Substring($payloadIndex + $payloadMarker.Length)
    $entryPointIndex = $payload.LastIndexOf($EntryPointMarker)
    if ($entryPointIndex -lt 0) { throw "Entry-point marker not found in $Path" }
    $payload.Substring(0, $entryPointIndex)
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$serverHelper = Join-Path $repositoryRoot 'Palworld-UE4SS-Dedicated-Server-Helper.cmd'
$clientHelper = Join-Path $repositoryRoot 'Palworld-UE4SS-Workshop-Helper.cmd'

$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp "Palworld-UE4SS-Helper-Tests-$([guid]::NewGuid().ToString('N'))"
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTestRoot.StartsWith($systemTemp + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The generated test directory is outside the system temporary directory.'
}

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null

    . ([scriptblock]::Create((Get-EmbeddedPayloadDefinitions $serverHelper '### SERVER HELPER ENTRYPOINT ###')))
    function Assert-ServerClosed { }

    $serverRoot = Join-Path $testRoot 'PalServer'
    $win64 = Join-Path $serverRoot 'Pal\Binaries\Win64'
    New-Item -ItemType Directory -Path $win64 -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $serverRoot 'PalServer.exe') | Out-Null
    New-Item -ItemType File -Path (Join-Path $win64 'PalServer-Win64-Shipping-Cmd.exe') | Out-Null
    $helperBesideServer = Join-Path $serverRoot 'Palworld-UE4SS-Dedicated-Server-Helper.cmd'
    New-Item -ItemType File -Path $helperBesideServer | Out-Null
    $script:ServerRoot = $serverRoot
    $paths = Get-ServerPaths

    Assert-True (Test-ServerRoot $serverRoot) 'The fake Windows dedicated-server root should be recognized.'
    Assert-True ((Get-ServerRootFromLocation (Join-Path $win64 'PalServer-Win64-Shipping-Cmd.exe')) -eq $serverRoot) 'The server root should be derived from a PalServer executable path.'
    $previousHelperFile = $env:PALWORLD_SERVER_HELPER_FILE
    try {
        $env:PALWORLD_SERVER_HELPER_FILE = $helperBesideServer
        Assert-True (@(Find-PalServerInstallations | Where-Object { $_ -eq $serverRoot }).Count -eq 1) 'Automatic discovery should find a server beside the helper file.'
    } finally {
        $env:PALWORLD_SERVER_HELPER_FILE = $previousHelperFile
    }
    Assert-True ((Get-ServerExecutable $paths) -eq (Join-Path $serverRoot 'PalServer.exe')) 'The guided deployment should select the normal PalServer launcher first.'
    Assert-True ((Get-FixedTableCell '123456789' 8) -eq '12345...') 'Long colored table cells should be truncated predictably.'
    Assert-True (-not (Test-DiagnosticAliasMatch 'Fatal error while starting PalServer' 'Error')) 'Generic diagnostic words must never identify a package.'
    Assert-True (-not (Test-DiagnosticAliasMatch 'ServerLuaExtended failed' 'ServerLua')) 'A package alias must not match inside a longer identifier.'
    Assert-True (Test-DiagnosticAliasMatch '...\Mods\ServerLua\Scripts\main.lua failed' 'ServerLua') 'A delimited package path should be a direct diagnostic match.'

    New-Item -ItemType Directory -Path $paths.ModsRoot -Force | Out-Null
    @(
        '[PalModSettings]',
        '; preserved comment',
        'bGlobalEnableMod=false',
        'ActiveModList=ExistingPackage'
    ) | Set-Content -LiteralPath $paths.PalModSettings -Encoding UTF8

    $worldParent = Split-Path -Parent $paths.WorldSettings
    New-Item -ItemType Directory -Path $worldParent -Force | Out-Null
    @'
[/Script/Pal.PalGameWorldSettings]
OptionSettings=(ServerName="Fixture (QA)",bAllowClientMod=False)
[UnrelatedSection]
Value=(ThisMustRemainUntouched=True)
'@ | Set-Content -LiteralPath $paths.WorldSettings -Encoding UTF8

    Set-PalModSettingsContent $paths @('ExistingPackage', 'UE4SSExperimentalPW', 'ServerLua')
    $palModText = Get-Content -LiteralPath $paths.PalModSettings -Raw
    Assert-True ($palModText -match '(?im)^bGlobalEnableMod=true\r?$') 'Global mod loading should be enabled.'
    Assert-True (($palModText | Select-String -Pattern '(?im)^ActiveModList=ExistingPackage\r?$' -AllMatches).Matches.Count -eq 1) 'Existing ActiveModList entries should be preserved without duplication.'
    Assert-True ($palModText -match '(?im)^ActiveModList=UE4SSExperimentalPW\r?$') 'UE4SS should be added to ActiveModList.'
    Assert-True ($palModText -match '(?im)^ActiveModList=ServerLua\r?$') 'The server Lua fixture should be added to ActiveModList.'
    Assert-True ($palModText -match '; preserved comment') 'Comments in PalModSettings.ini should be preserved.'

    Set-AllowClientMod $paths
    $worldText = Get-Content -LiteralPath $paths.WorldSettings -Raw
    Assert-True ($worldText -match 'bAllowClientMod=True') 'bAllowClientMod should be enabled.'
    Assert-True ($worldText -notmatch 'bAllowClientMod=False') 'The old bAllowClientMod value should be replaced.'
    Assert-True ($worldText -match 'ServerName="Fixture \(QA\)"') 'Parentheses inside a quoted server name should be preserved.'
    Assert-True ($worldText -match 'Value=\(ThisMustRemainUntouched=True\)') 'Configuration after OptionSettings should remain untouched.'

    $reservedNameRejected = $false
    try { [void](Get-SafePackageName 'CON.example' 'fixture') } catch { $reservedNameRejected = $true }
    Assert-True $reservedNameRejected 'Windows reserved device names should be rejected as package names.'

    function Write-FixturePackage {
        param(
            [string]$Folder,
            [string]$Package,
            [string]$Type,
            [object]$Server,
            [string[]]$Dependencies
        )
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        $rule = [ordered]@{ Type=$Type; Targets=@('.') }
        if ($null -ne $Server) { $rule.IsServer = $Server }
        [ordered]@{
            ModName = "$Package fixture"
            PackageName = $Package
            Version = '1.0.0'
            Dependencies = $Dependencies
            InstallRule = @($rule)
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Folder 'Info.json') -Encoding UTF8
    }

    $ue4ssStage = Join-Path $paths.WorkshopStage '3625223587'
    $serverLuaStage = Join-Path $paths.WorkshopStage '1000000001'
    $clientOnlyStage = Join-Path $paths.WorkshopStage '1000000002'
    $malformedStage = Join-Path $paths.WorkshopStage '1000000003'
    Write-FixturePackage $ue4ssStage 'UE4SSExperimentalPW' 'UE4SS' $true @()
    Write-FixturePackage $serverLuaStage 'ServerLua' 'Lua' $true @('UE4SSExperimentalPW')
    Write-FixturePackage $clientOnlyStage 'ClientOnlyLua' 'Lua' $false @('UE4SSExperimentalPW')
    Write-FixturePackage $malformedStage 'StringFalseLua' 'Lua' 'false' @('UE4SSExperimentalPW')

    $deployedServerLua = Join-Path $paths.WorkshopMods 'ServerLua\Scripts'
    New-Item -ItemType Directory -Path $deployedServerLua -Force | Out-Null
    'print("fixture")' | Set-Content -LiteralPath (Join-Path $deployedServerLua 'main.lua') -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path (Split-Path -Parent $deployedServerLua) 'enabled.txt') | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $paths.ManagedRoot 'ServerLua') -Force | Out-Null
    '{}' | Set-Content -LiteralPath (Join-Path $paths.ManagedRoot 'ServerLua\InstallManifest.json') -Encoding UTF8

    $records = @(Get-ServerWorkshopPackages $paths)
    Assert-True ($records.Count -eq 4) 'All four staged Workshop packages should be discovered.'
    Assert-True (($records | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).WorkshopID -eq '1000000001') 'The numeric Workshop folder ID should be retained with the package metadata.'
    Assert-True (@($records | Where-Object Package -eq 'ServerLua' | Where-Object { $_.ServerTypes -contains 'Lua' }).Count -eq 1) 'ServerLua should expose a server Lua rule.'
    Assert-True (@($records | Where-Object Package -eq 'ClientOnlyLua' | Where-Object { $_.ServerRules.Count -eq 0 }).Count -eq 1) 'Client-only packages should not be treated as server-compatible.'
    Assert-True (@($records | Where-Object Package -eq 'StringFalseLua' | Where-Object { $_.ServerRules.Count -eq 0 }).Count -eq 1) 'A malformed string value must not be treated as an IsServer boolean.'

    $syncDestination = Join-Path $testRoot 'SynchronizedMods'
    $syncPlan = @(Get-ServerSyncPlan $paths $syncDestination)
    Assert-True (@($syncPlan | Where-Object Package -eq 'ServerLua').Count -eq 1) 'ServerLua should appear in the synchronization plan.'
    Assert-True (@($syncPlan | Where-Object Package -eq 'ClientOnlyLua').Count -eq 0) 'Client-only Lua packages should not be synchronized to the server runtime.'
    Assert-True (@($syncPlan | Where-Object Package -eq 'StringFalseLua').Count -eq 0) 'Malformed server rules should not be synchronized to the server runtime.'
    Copy-ServerSyncPlan $syncPlan
    Assert-True (Test-Path -LiteralPath (Join-Path $syncDestination 'ServerLua\Scripts\main.lua') -PathType Leaf) 'Server Lua content should be copied.'
    Assert-True (Test-Path -LiteralPath (Join-Path $syncDestination 'ServerLua\enabled.txt') -PathType Leaf) 'Server Lua content should be enabled.'
    Remove-Item -LiteralPath (Join-Path $syncDestination 'ServerLua\enabled.txt') -Force
    'ServerLua : 0' | Set-Content -LiteralPath (Join-Path $syncDestination 'mods.txt') -Encoding UTF8
    Copy-ServerSyncPlan $syncPlan
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $syncDestination 'ServerLua\enabled.txt') -PathType Leaf)) 'Server synchronization must respect an explicit disabled entry in mods.txt.'

    New-Item -ItemType Directory -Path $paths.WorkshopRuntime -Force | Out-Null
    'workshop-runtime' | Set-Content -LiteralPath $paths.WorkshopDll -Encoding UTF8
    'layout' | Set-Content -LiteralPath $paths.WorkshopLayout -Encoding UTF8

    $packageWin64 = Join-Path $testRoot 'Package\Win64'
    $packageUe4ss = Join-Path $packageWin64 'ue4ss'
    New-Item -ItemType Directory -Path (Join-Path $packageUe4ss 'Mods') -Force | Out-Null
    'external-runtime' | Set-Content -LiteralPath (Join-Path $packageUe4ss 'UE4SS.dll') -Encoding UTF8
    'layout' | Set-Content -LiteralPath (Join-Path $packageUe4ss 'MemberVariableLayout.ini') -Encoding UTF8
    '[General]' | Set-Content -LiteralPath (Join-Path $packageUe4ss 'UE4SS-settings.ini') -Encoding UTF8
    'proxy' | Set-Content -LiteralPath (Join-Path $packageWin64 'dwmapi.dll') -Encoding UTF8
    $package = [pscustomobject]@{
        BuildKey='Fixture'
        BuildName='Fixture build'
        Repository='fixture/repository'
        Tag='fixture'
        AssetName='fixture.zip'
        Sha256=('0' * 64)
        Layout=[pscustomobject]@{
            Win64Source=$packageWin64
            Ue4ssSource=$packageUe4ss
            ProxySource=(Join-Path $packageWin64 'dwmapi.dll')
        }
    }

    Install-ExperimentalServerPackage $paths $package
    Assert-True (Test-Path -LiteralPath $paths.BackupsRoot -PathType Container) 'Server backups should be grouped under the dedicated helper folder.'
    Assert-True (@(Get-ChildItem -LiteralPath $serverRoot -Filter '_UE4SS-Server-Helper-Backup-*' -Directory -ErrorAction SilentlyContinue).Count -eq 0) 'New server backups must not clutter the PalServer root.'
    Assert-True (Test-Path -LiteralPath $paths.ExternalDll -PathType Leaf) 'The external server runtime should be installed.'
    Assert-True (Test-Path -LiteralPath $paths.ExternalProxy -PathType Leaf) 'The external proxy should be installed.'
    Assert-True (Test-Path -LiteralPath $paths.RuntimeMarker -PathType Leaf) 'The installed server runtime should contain its helper provenance record.'
    Assert-True ((Get-InstalledRuntimeSummary $paths).Text -eq 'Fixture build [fixture]') 'The server home screen should identify the installed runtime build and tag.'
    Assert-True (-not (Test-Path -LiteralPath $paths.WorkshopDll -PathType Leaf)) 'The Workshop runtime DLL should be disabled.'
    Assert-True ($null -ne (Get-ChildItem -LiteralPath $paths.WorkshopRuntime -Filter 'UE4SS.dll.workshop-disabled*' -File | Select-Object -First 1)) 'The disabled Workshop DLL should be retained.'
    Assert-True (Test-Path -LiteralPath (Join-Path $paths.ExternalMods 'ServerLua\enabled.txt') -PathType Leaf) 'Already deployed server Lua content should be synchronized during installation.'
    $installedServerReport = @(Get-ServerPackageReport $paths)
    Assert-True (($installedServerReport | Where-Object Package -eq 'UE4SSExperimentalPW' | Select-Object -First 1).RuntimeState -eq 'External runtime active') 'The audit should identify the active external UE4SS runtime.'
    Assert-True (($installedServerReport | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).WorkshopID -eq '1000000001') 'The server report should expose the Workshop folder ID.'
    Assert-True (($installedServerReport | Where-Object Package -eq 'UE4SSExperimentalPW' | Select-Object -First 1).Dependencies -eq 'No declared dependencies') 'Packages with no dependency metadata should use an unambiguous report label.'
    Assert-True (($installedServerReport | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).RuntimeState -eq 'External enabled') 'The audit should identify synchronized and enabled server Lua content.'
    Remove-Item -LiteralPath (Join-Path $paths.ExternalMods 'ServerLua\enabled.txt') -Force
    'ServerLua : 1' | Set-Content -LiteralPath (Join-Path $paths.ExternalMods 'mods.txt') -Encoding UTF8
    $modsTxtServerReport = @(Get-ServerPackageReport $paths)
    Assert-True (($modsTxtServerReport | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).RuntimeState -eq 'External enabled (mods.txt)') 'The server audit should recognize a Lua mod enabled through mods.txt.'
    Write-ServerPackageReport $installedServerReport

    @'
[2026-08-05 12:00:00.0000000] Starting mods (from mods.txt (fixture)) load order...
[2026-08-05 12:00:00.1000000] Starting Lua mod 'ServerLua'
[2026-08-05 12:00:00.2000000] [Lua] [ServerLua] ERROR: fixture failure in server mod
...\ue4ss\Mods\ServerLua\Scripts\main.lua:42: fixture stack line
'@ | Set-Content -LiteralPath (Join-Path $paths.ExternalRoot 'UE4SS.log') -Encoding UTF8
    $logAnalysis = Get-ServerLogAnalysis $paths
    $serverLuaSuspect = $logAnalysis.Suspects | Where-Object Package -eq 'ServerLua' | Select-Object -First 1
    Assert-True ($null -ne $serverLuaSuspect) 'The log audit should map a directly referenced error to its Workshop package.'
    Assert-True ($serverLuaSuspect.Confidence -eq 'Direct reference') 'A package named in an error should receive direct-reference confidence.'
    Assert-True ($serverLuaSuspect.WorkshopID -eq '1000000001') 'A correlated log suspect should include the Workshop folder ID.'
    Assert-True ($serverLuaSuspect.Errors -eq 1) 'The directly referenced fixture error should be counted once.'
    Assert-True ($null -eq (Get-ServerLogAnalysis $paths (Get-Date).AddMinutes(1)).Log) 'The startup monitor should ignore logs that were not modified during its current run.'

    New-Item -ItemType Directory -Path $paths.HelperLogs -Force | Out-Null
    $oldConsole = Join-Path $paths.HelperLogs 'PalServer-session-20000101-000000-000-stdout.log'
    '[FATAL] old session must not be selected' | Set-Content -LiteralPath $oldConsole -Encoding UTF8
    (Get-Item -LiteralPath $oldConsole).LastWriteTime = (Get-Date).AddDays(-30)
    $consoleOut = Join-Path $paths.HelperLogs 'PalServer-session-20260806-001500-000-stdout.log'
    $consoleErr = Join-Path $paths.HelperLogs 'PalServer-session-20260806-001500-000-stderr.log'
    "[ERROR] ServerLua failed while starting from the guided console" | Set-Content -LiteralPath $consoleOut -Encoding UTF8
    '' | Set-Content -LiteralPath $consoleErr -Encoding UTF8
    New-Item -ItemType Directory -Path $paths.LegacyHelperLogs -Force | Out-Null
    $legacyConsole = Join-Path $paths.LegacyHelperLogs 'PalServer-session-20260806-001459-000-stdout.log'
    '[LOG] legacy development log fixture' | Set-Content -LiteralPath $legacyConsole -Encoding UTF8

    New-Item -ItemType Directory -Path $paths.SavedLogs -Force | Out-Null
    '[FATAL] CreateBoundSocket failed because the address is already in use' | Set-Content -LiteralPath (Join-Path $paths.SavedLogs 'PalServer.log') -Encoding UTF8

    $crashFolder = Join-Path $paths.CrashRoot 'UECC-fixture'
    New-Item -ItemType Directory -Path $crashFolder -Force | Out-Null
    '<CrashContext><ErrorMessage>Fatal error: access violation in UE4SS.dll</ErrorMessage></CrashContext>' |
        Set-Content -LiteralPath (Join-Path $crashFolder 'CrashContext.runtime-xml') -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path $crashFolder 'fixture.dmp') | Out-Null

    $fullAnalysis = Get-ServerFullLogAnalysis $paths (Get-Date).AddMinutes(-2) @($consoleOut, $consoleErr)
    Assert-True (
        @($fullAnalysis.Logs | Where-Object Path -eq $consoleOut).Count -eq 1 -and
        @($fullAnalysis.Logs | Where-Object Path -eq $consoleErr).Count -eq 1
    ) 'Both guided stdout and stderr should be included in a full diagnosis.'
    Assert-True (@($fullAnalysis.Logs | Where-Object Label -eq 'PalServer saved log').Count -eq 1) 'Native PalServer saved logs should be included in a full diagnosis.'
    Assert-True (@($fullAnalysis.Logs | Where-Object Label -eq 'Unreal crash report').Count -eq 1) 'Textual Unreal crash reports should be included in a full diagnosis.'
    Assert-True (@($fullAnalysis.Logs | Where-Object Path -eq $legacyConsole).Count -eq 1) 'Logs from the previous development folder should remain readable during migration.'
    Assert-True (@($fullAnalysis.Suspects | Where-Object Package -eq 'ServerLua').Count -eq 1) 'A mod named by the captured PalServer console should be correlated.'
    Assert-True (($fullAnalysis.Suspects | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).WorkshopID -eq '1000000001') 'The full diagnosis should preserve the suspect Workshop folder ID.'
    Assert-True (@($fullAnalysis.Hints | Where-Object Finding -like 'A network port*').Count -eq 1) 'Port conflicts should produce an environment hint.'
    Assert-True (@($fullAnalysis.Hints | Where-Object Finding -like 'UE4SS.dll*').Count -eq 1) 'Runtime crash signatures should be explained without blaming a mod.'
    Assert-True ($fullAnalysis.CrashArtifacts.Count -eq 2) 'The crash context and minidump should both be reported as crash artifacts.'
    Assert-True (@(Get-ServerDiagnosticFiles $paths | Where-Object Path -eq $oldConsole).Count -eq 0) 'Historical guided sessions should not be mixed into the latest-session audit.'

    Restore-WorkshopServerRuntime $paths
    Assert-True (-not (Test-Path -LiteralPath $paths.ExternalProxy -PathType Leaf)) 'The external proxy should be removed during restoration.'
    Assert-True (-not (Test-Path -LiteralPath $paths.ExternalRoot -PathType Container)) 'The external runtime should be moved into the restoration backup.'
    Assert-True (Test-Path -LiteralPath $paths.WorkshopDll -PathType Leaf) 'The Workshop runtime DLL should be restored.'
    Assert-True ((Get-InstalledRuntimeSummary $paths).Text -eq 'Palworld Workshop UE4SS runtime') 'The server home screen should identify the restored Workshop runtime.'
    $restoredServerReport = @(Get-ServerPackageReport $paths)
    Assert-True (($restoredServerReport | Where-Object Package -eq 'ServerLua' | Select-Object -First 1).RuntimeState -eq 'Workshop enabled') 'The audit should recognize Lua content used directly by the restored Workshop runtime.'
    Invoke-ServerSynchronization $paths
    Assert-True (Test-Path -LiteralPath $paths.WorkshopDll -PathType Leaf) 'Synchronization should be a harmless no-op while the Workshop runtime is active.'

    Remove-Item Function:\Write-FixturePackage -ErrorAction SilentlyContinue
    . ([scriptblock]::Create((Get-EmbeddedPayloadDefinitions $clientHelper '### CLIENT HELPER ENTRYPOINT ###')))
    function Assert-PalworldClosed { }

    $clientRoot = Join-Path $testRoot 'PalworldClient'
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\ClientFixture\Scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\PalSchema\Scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Mods\ManagedMods\ClientFixture') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Mods\ManagedMods\PalSchema') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Mods\NativeMods\UE4SS') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $clientRoot 'Palworld.exe') | Out-Null
    'runtime' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\UE4SS.dll') -Encoding UTF8
    'proxy' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\dwmapi.dll') -Encoding UTF8
    'layout' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\MemberVariableLayout.ini') -Encoding UTF8
    'print("client")' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\ClientFixture\Scripts\main.lua') -Encoding UTF8
    'print("schema")' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\PalSchema\Scripts\main.lua') -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\ClientFixture\enabled.txt') | Out-Null
    'PalSchema : 1' | Set-Content -LiteralPath (Join-Path $clientRoot 'Pal\Binaries\Win64\ue4ss\Mods\mods.txt') -Encoding UTF8
    [ordered]@{
        ModName='Client fixture'
        PackageName='ClientFixture'
        Dependencies=@('UE4SSExperimentalPW')
        InstallRule=@([ordered]@{Type='Lua';Targets=@('./Scripts')})
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $clientRoot 'Mods\ManagedMods\ClientFixture\Info.json') -Encoding UTF8
    [ordered]@{
        ModName='PalSchema fixture'
        PackageName='PalSchema'
        Dependencies=@('UE4SSExperimentalPW')
        InstallRule=@([ordered]@{Type='Lua';Targets=@('./Scripts');IsServer=$true})
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $clientRoot 'Mods\ManagedMods\PalSchema\Info.json') -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $clientRoot 'Mods\ManagedMods\UE4SSExperimentalPW') -Force | Out-Null
    [ordered]@{
        ModName='UE4SS fixture'
        PackageName='UE4SSExperimentalPW'
        Dependencies=$null
        InstallRule=@([ordered]@{Type='UE4SS';Targets=@('.')})
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $clientRoot 'Mods\ManagedMods\UE4SSExperimentalPW\Info.json') -Encoding UTF8

    $script:GameRoot = $clientRoot
    $clientPaths = Get-Paths
    Assert-True (Test-GameRoot $clientRoot) 'The fake Palworld client root should be recognized.'
    Assert-True (-not (Test-GameRoot $serverRoot)) 'The dedicated-server folder must not be accepted by the client helper.'

    'workshop-runtime' | Set-Content -LiteralPath $clientPaths.WorkshopDll -Encoding UTF8
    'layout' | Set-Content -LiteralPath $clientPaths.WorkshopLayout -Encoding UTF8
    Install-ExperimentalPackage $clientPaths $package
    Assert-True (Test-Path -LiteralPath $clientPaths.BackupsRoot -PathType Container) 'Client backups should be grouped under the dedicated helper folder.'
    Assert-True (@(Get-ChildItem -LiteralPath $clientRoot -Filter '_UE4SS-Helper-Backup-*' -Directory -ErrorAction SilentlyContinue).Count -eq 0) 'New client backups must not clutter the Palworld root.'
    Assert-True (Test-Path -LiteralPath $clientPaths.GitHubDll -PathType Leaf) 'The external client runtime should be installed.'
    Assert-True (Test-Path -LiteralPath $clientPaths.GitHubProxy -PathType Leaf) 'The external client proxy should be installed.'
    Assert-True (Test-Path -LiteralPath $clientPaths.RuntimeMarker -PathType Leaf) 'The installed client runtime should contain its helper provenance record.'
    Assert-True ((Get-InstalledRuntimeSummary $clientPaths).Text -eq 'Fixture build [fixture]') 'The client home screen should identify the installed runtime build and tag.'
    Assert-True (Test-IsJunction $clientPaths.WorkshopMods) 'The client Workshop Mods path should become a junction.'
    Assert-JunctionTarget $clientPaths.WorkshopMods $clientPaths.GitHubMods
    Assert-True (-not (Test-Path -LiteralPath $clientPaths.WorkshopDll -PathType Leaf)) 'The client Workshop runtime DLL should be disabled.'

    $clientReport = @(Get-ClientModDiagnostics $clientPaths)
    $clientFixture = $clientReport | Where-Object Package -eq 'ClientFixture' | Select-Object -First 1
    Assert-True ($null -ne $clientFixture) 'The client diagnostic should discover the fixture mod.'
    Assert-True ($clientFixture.RuntimeState -eq 'Enabled (enabled.txt)') 'The client diagnostic should recognize Lua content enabled by enabled.txt.'
    Assert-True ($clientFixture.Dependencies -eq 'Present') 'The client diagnostic should recognize an installed dependency.'
    $palSchemaFixture = $clientReport | Where-Object Package -eq 'PalSchema' | Select-Object -First 1
    Assert-True ($palSchemaFixture.RuntimeState -eq 'Enabled (mods.txt)') 'The client diagnostic should not report PalSchema as disabled when mods.txt enables the framework.'
    Remove-Item -LiteralPath (Join-Path $clientPaths.GitHubMods 'ClientFixture\enabled.txt') -Force
    @('PalSchema : 1','ClientFixture : 0') | Set-Content -LiteralPath (Join-Path $clientPaths.GitHubMods 'mods.txt') -Encoding UTF8
    $disabledSyncResult = Get-SyncResults $clientPaths $true | Where-Object Package -eq 'ClientFixture' | Select-Object -First 1
    Assert-True ($disabledSyncResult.Result -eq 'Disabled in mods.txt; left unchanged') 'Client synchronization should report an explicit mods.txt disable without overriding it.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $clientPaths.GitHubMods 'ClientFixture\enabled.txt') -PathType Leaf)) 'Client synchronization must not override an explicit disabled entry in mods.txt.'
    New-Item -ItemType File -Path (Join-Path $clientPaths.GitHubMods 'ClientFixture\enabled.txt') | Out-Null
    Assert-True (-not (Test-ClientDiagnosticAliasMatch 'Fatal error in Palworld' 'Error')) 'Generic client log words must not identify a mod.'

    @'
[2026-08-06 00:00:00.0000000] Starting mods (from mods.txt (fixture)) load order...[2026-08-06 00:00:00.1000000] [Lua] [ClientFixture] ERROR reading fixture property[2026-08-06 00:00:00.2000000] [Lua] [ClientFixture] observer timed out
'@ | Set-Content -LiteralPath (Join-Path $clientPaths.GitHubRoot 'UE4SS.log') -Encoding UTF8
    $clientLogAnalysis = Get-ClientLogAnalysis $clientPaths
    $clientLogSuspect = $clientLogAnalysis.Suspects | Where-Object Package -eq 'ClientFixture' | Select-Object -First 1
    Assert-True ($null -ne $clientLogSuspect) 'The client log diagnosis should map directly named errors to an installed Workshop package.'
    Assert-True ($clientLogSuspect.Errors -eq 2) 'Concatenated UE4SS timestamps should be split into two separate client errors.'
    Assert-True ($clientLogSuspect.Lines.Count -eq 2) 'Repeated client log output should be presented as readable individual lines.'

    $disabledClientDll = Get-ChildItem -LiteralPath $clientPaths.WorkshopRoot -Filter 'UE4SS.dll.workshop-disabled*' -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Restore-WorkshopRuntime $clientPaths $disabledClientDll
    Assert-True (-not (Test-Path -LiteralPath $clientPaths.GitHubProxy -PathType Leaf)) 'The external client proxy should be moved during restoration.'
    Assert-True (-not (Test-Path -LiteralPath $clientPaths.GitHubRoot -PathType Container)) 'The external client runtime should be moved during restoration.'
    Assert-True (-not (Test-IsJunction $clientPaths.WorkshopMods)) 'The restored client Workshop Mods path should be a normal directory.'
    Assert-True ((Get-InstalledRuntimeSummary $clientPaths).Text -eq 'Palworld Workshop UE4SS runtime') 'The client home screen should identify the restored Workshop runtime.'
    Assert-True (Test-Path -LiteralPath (Join-Path $clientPaths.WorkshopMods 'ClientFixture\enabled.txt') -PathType Leaf) 'The restored Workshop Mods directory should keep synchronized mod content.'
    Assert-True (Test-Path -LiteralPath $clientPaths.WorkshopDll -PathType Leaf) 'The client Workshop runtime DLL should be restored.'

    Write-Host 'All helper validation tests passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        $finalTarget = [IO.Path]::GetFullPath($testRoot)
        if (-not $finalTarget.StartsWith($systemTemp + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a test directory outside the system temporary directory.'
        }
        Remove-Item -LiteralPath $finalTarget -Recurse -Force
    }
}
