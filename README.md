# Palworld UE4SS Workshop Helper

This repository contains two standalone Windows helpers for running an Experimental UE4SS build without breaking Palworld's Workshop dependency detection:

- `Palworld-UE4SS-Workshop-Helper.cmd` for the normal Steam game, co-op hosts and players joining multiplayer;
- `Palworld-UE4SS-Dedicated-Server-Helper.cmd` for a Windows dedicated server.

They are separate because the client and server use different folders and configuration files. Mixing both jobs into one menu would make it far too easy to change the wrong installation.

## Download

Get both helpers from the [latest GitHub release](https://github.com/ZdradaKali/Palworld-UE4SS-Workshop-Helper/releases/latest).

The CMD files contain their complete PowerShell source as readable plain text. Neither helper asks for administrator rights.

## Upgrading from 2.1.0

If your client setup already works, installing version 2.2.0 does **not** mean that UE4SS must be installed again. Replace the old helper, then use Status or Diagnostics if you want to check the current setup.

Run the installation option again only if you want to update or switch the UE4SS build, or if the report says the runtime needs repair.

The dedicated-server helper is new in 2.2.0. Version 2.1.0 never configured a dedicated server, so there is no server migration to perform.

## Which UE4SS build should I use?

Both helpers accept two reviewed Experimental builds:

- [Palworld-specific Experimental](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld) — the recommended starting point based on the combinations tested below;
- [Official Experimental](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest) — the newest upstream alternative.

Version 2.2.0 accepts only these exact release assets:

```text
Palworld-specific: Okaetsu/RE-UE4SS, experimental-palworld
                   UE4SS-Palworld.zip

Official:          UE4SS-RE/RE-UE4SS, experimental-latest
                   UE4SS_v3.0.1-1018-g662df915.zip
```

Their SHA-256 values are pinned inside both helpers. If an archive changes upstream, the download is rejected until the helper has been reviewed and updated. It will not silently fall back to another file or release.

### Tested client/server combinations

The most reliable combination in my tests was the Palworld-specific build on both the client and server.

| Client runtime | Server runtime | Observed result |
| --- | --- | --- |
| Palworld-specific | Palworld-specific | Best tested combination; tested mods worked |
| Palworld-specific | Official Experimental | Tested mods worked |
| Palworld-specific | Workshop UE4SS | Tested mods worked |
| Official Experimental | Palworld-specific | Tested mods worked |
| Official Experimental | Official Experimental | Partial: Bigger Palbox (PalSchema) worked; Infinite Weight In Camp (direct Lua) did not |
| Official Experimental | Workshop UE4SS | Partial: Bigger Palbox (PalSchema) worked; Infinite Weight In Camp (direct Lua) did not |

The client and server do not have to use the same provider. These are results from one real test setup and mod collection, not a promise that every mod will behave the same way after every Palworld update.

## Client helper

Use `Palworld-UE4SS-Workshop-Helper.cmd` for a normal Steam installation of Palworld.

It can:

- find Palworld in registered Steam libraries;
- install either reviewed Experimental build into a clean runtime;
- switch provider without mixing old and new runtime files;
- keep existing mods and `UE4SS-settings.ini`;
- create and verify the client `Mods` junction;
- disable the Workshop runtime DLL without deleting it;
- install or verify `MemberVariableLayout.ini`;
- synchronize compatible Workshop Lua mods;
- show the current setup and a read-only client/co-op diagnosis;
- restore the normal Workshop runtime later;
- create timestamped backups before important changes.

### First client installation

1. Close Palworld.
2. Run `Palworld-UE4SS-Workshop-Helper.cmd`.
3. Open `INSTRUCTIONS / READ ME` from option 7.
4. Choose `Install or update Experimental UE4SS automatically`.
5. Start with the Palworld-specific build unless you have a reason to use the official one.
6. Read the preview and confirm only if the detected game folder is correct.
7. Run Status, start the game and test your mods.

After subscribing to new UE4SS Workshop mods, let Palworld deploy them once, close the game, then run `Synchronize new Workshop UE4SS mods`.

### Lua activation and PalSchema

UE4SS supports two activation methods:

- an `enabled.txt` file inside the mod folder;
- a `PackageName : 1` entry in `Mods\mods.txt`.

The helper recognizes both. Synchronization will not add `enabled.txt` when a package is already enabled through `mods.txt`, and it will not override an explicit `PackageName : 0` entry.

PalSchema itself is a Lua framework and must be activated by one of those methods. Individual packages installed through PalSchema do not need their own `enabled.txt`.

See the official [UE4SS installation guide](https://docs.ue4ss.com/dev/installation-guide.html) and [Lua mod guide](https://docs.ue4ss.com/dev/guides/creating-a-lua-mod.html) for the underlying UE4SS behavior.

## Dedicated-server helper

Use `Palworld-UE4SS-Dedicated-Server-Helper.cmd` only for a Windows dedicated server whose files you can access directly. It does not support Linux servers or remote hosting panels that hide the server filesystem.

The helper follows [Pocketpair's server-side mod layout](https://docs.palworldgame.com/settings-and-operation/mod/). It reads `PalModSettings.ini` and selects only install rules explicitly marked `IsServer: true`. It never creates the client's `Mods` junction on a server.

It can:

- find common Steam and SteamCMD server installations, including `C:\PalServer`;
- audit the runtime, packages, server rules and dependencies without changing files;
- inspect UE4SS logs, PalServer logs, textual Unreal crash reports and PalServer-related Windows crash events;
- preserve existing `PalModSettings.ini` content while adding missing server packages;
- optionally set `bAllowClientMod=True`;
- start PalServer in a separate window, capture its output and monitor the deployment;
- install either reviewed Experimental build as the external server runtime;
- synchronize deployed server-compatible Lua and PalSchema content;
- disable a redeployed Workshop `UE4SS.dll` before it can run alongside the external runtime;
- restore the Workshop runtime later;
- make a backup and attempt rollback when an operation fails.

### First server installation

1. Install or stage the Workshop packages expected by your server setup.
2. Start PalServer once so it creates its normal folders, then stop it cleanly.
3. Run `Palworld-UE4SS-Dedicated-Server-Helper.cmd`.
4. Open `INSTRUCTIONS / READ ME` from option 7.
5. Run the read-only audit first.
6. Use the configuration option to add detected server-compatible packages to `ActiveModList`.
7. Let the helper start and monitor PalServer, or decline and use your normal launcher.
8. Install the Palworld-specific Experimental build, then audit again.

The helper checks its last valid selection, its own folder, a running PalServer process, Steam libraries and common SteamCMD locations. One result is selected automatically; several results produce a menu. A custom path is remembered under:

```text
%LOCALAPPDATA%\Palworld-UE4SS-Workshop-Helper\selected-server.txt
```

Option 6 changes it later.

### Guided start and logs

The guided start launches `PalServer.exe` without custom arguments. Decline it if your normal launcher adds arguments that your server needs.

Captured output is stored under:

```text
_UE4SS-Server-Helper\Logs
```

The audit reads only the newest guided session, so an old crash is not presented as part of a newer clean launch. Logs made by early 2.2 test builds under `_UE4SS-Server-Helper-Logs` are still recognized.

The helper never force-stops PalServer and does not enable a remote administration interface. Shut the server down normally when testing is finished. Pocketpair documents [`/Shutdown [Seconds] [MessageText]`](https://docs.palworldgame.com/settings-and-operation/commands/) as the graceful administrative command.

If you close the PalServer window before the monitor finishes its startup check, the report may say that the server stopped during startup even when you closed it yourself. The captured logs and final audit remain the useful evidence in that case.

### Synchronization is only for an external runtime

The server synchronization option copies deployed Lua and PalSchema content into an external Experimental UE4SS runtime. It therefore requires that external runtime to be installed first.

If the normal Workshop UE4SS runtime is active, Palworld already deploys its mods into the Workshop runtime. No extra synchronization is needed, and the helper reports a normal no-op instead of an error.

Run the audit after changing Workshop packages. Palworld can deploy the Workshop DLL again, and two active UE4SS runtimes can crash the server.

`bAllowClientMod=True` only allows clients to use their own mods. It does not make a client-only package server-compatible.

### Reading the diagnosis

The report separates three levels of evidence:

- **Direct reference:** an error names a package, mod or file declared by its server install rule.
- **Nearby activity only:** a package was the last recognizable mod activity before an error. This is a lead, not proof.
- **No reliable package match:** PalServer, Windows or Unreal recorded a failure without enough information to name one mod.

Package rows and correlated suspects include the numeric Workshop folder ID, making the matching folder under `Mods\Workshop` easier to find.

The diagnosis also recognizes common non-mod causes such as port conflicts, memory exhaustion, missing modules, access violations and failures naming `UE4SS.dll` or `dwmapi.dll`. It reports binary minidumps but does not decode them.

Logs can contain player names, Steam IDs, IP addresses and chat messages. Redact them before posting a report publicly.

## Runtime identification

Both main menus show the currently recorded UE4SS provider and release tag. New installations save this information as:

```text
Palworld-UE4SS-Helper-runtime.json
```

Older 2.2 test installations without that marker are identified from the newest usable helper backup when possible. If you replace runtime files manually, the displayed record may no longer describe what is actually installed.

## Download and archive checks

Before installation, both helpers verify:

- the allowed GitHub repository, tag, asset name and download URL;
- the archive size and GitHub digest;
- the extra SHA-256 pinned in the helper;
- every ZIP entry against path traversal;
- the expected `dwmapi.dll` and `ue4ss\UE4SS.dll` structure.

The download is not executed. It is checked, extracted and copied for Palworld or PalServer to load later.

The helper release ZIP contains only the two helper files and this README. It does not bundle or redistribute UE4SS; the selected archive is downloaded directly from its maintainer's GitHub release.

## Backups and restoration

Backups are grouped instead of being scattered across the game or server root:

```text
Palworld\_UE4SS-Helper\Backups\20260806-120000-Install
PalServer\_UE4SS-Server-Helper\Backups\20260806-120000-Install
```

Keep the newest backup until the game or server has started successfully a few times. Restore also moves the external runtime into a backup instead of deleting it.

Older `_UE4SS-Helper-Backup-*`, `_UE4SS-Server-Helper-Backup-*` and `_UE4SS-Server-Helper-Logs` folders are not moved or deleted automatically. You may archive them yourself after checking their contents.

## PowerShell and antivirus warnings

The complete PowerShell source begins after this marker in each CMD:

```text
### POWERSHELL PAYLOAD ###
```

The launcher uses `ExecutionPolicy Bypass` only for the PowerShell process it starts. It does not change the system policy.

An unsigned CMD containing PowerShell that downloads, extracts and copies DLLs can trigger heuristic antivirus warnings. Read the source, verify where the file came from, or follow the manual Steam guide if you do not trust it. Do not disable security software just to make the warning disappear.

## What has actually been tested?

The client workflow is the setup I use on my normal Steam installation of Palworld. The 2.2 client audit was also run against that installation with 23 Workshop packages.

The server helper was tested on a real local Windows PalServer installation with the same 23 staged packages and nine active server packages. The checks covered Workshop staging and deployment, `PalModSettings.ini`, client connection, Lua synchronization, PalSchema dependencies and visible gameplay effects. Tested effects included server-side weight changes, instant revival, technology points, Mercy Mode and a Bigger Palbox limit of 128 × 30 slots.

Configuration and synchronization were run repeatedly. The server was switched Palworld-specific → official → Palworld-specific, restored to Workshop UE4SS, and then reinstalled with both external builds. The listed client/server runtime combinations were tested separately. The same install/sync/restore lifecycle is also covered by an isolated fake installation in the automated tests.

This still cannot cover every host, mod collection or future update. Keep the backups and read the preview.

Other limitations:

- Palworld or PalServer must be closed before runtime files are changed.
- Automatic installation needs Internet access.
- The original UE4SS Workshop item must stay installed so existing Workshop dependencies continue to resolve.
- `IsServer: true` means Palworld may deploy that rule on a server; it is not a compatibility guarantee.
- The helpers cannot repair a broken, outdated or client-only mod.
- A native crash or conflict between several mods does not always leave enough evidence to name one culprit.

Run the automated validation with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Helpers.ps1
```

## Credits

- Original scripts and helpers by [ZdradaKali](https://github.com/ZdradaKali), also known as [Yani Neco](https://steamcommunity.com/id/0peraGX/) on Steam and `hess_ch` on Discord.

- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) is maintained by the UE4SS project and its contributors.
- The [Palworld-specific Experimental build](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld) is provided by Okaetsu.

The only official downloads for these helpers are this repository and its GitHub releases. Copies from other websites or file hosts are unverified and may have been modified. Download a fresh copy here instead of running one you cannot verify.

## Disclaimer

This is an unofficial community tool. It is not affiliated with Pocketpair, Valve, GitHub, Okaetsu or the RE-UE4SS project.
