# Palworld UE4SS Workshop Helper

An interactive Windows helper for using the required Experimental build of RE-UE4SS while keeping Palworld Workshop dependency detection and UE4SS-dependent Workshop mods working.

The helper accompanies the Steam guide, but it can perform the complete installation, synchronization and restoration process automatically.

## Important

This workaround requires the **Experimental** RE-UE4SS build.

The helper downloads only the `experimental-latest` release from the official [`UE4SS-RE/RE-UE4SS`](https://github.com/UE4SS-RE/RE-UE4SS) repository. Stable releases are not used by this tool.

## Features

- Single interactive `.cmd` file with no separate PowerShell script.
- Automatic detection of the Palworld Steam installation.
- Support for Palworld installations outside the default Steam library.
- Automatic download of the official `experimental-latest` RE-UE4SS release.
- Automatic backup of an existing GitHub UE4SS installation.
- Preservation of an existing `UE4SS-settings.ini`.
- Merging of existing Workshop UE4SS mods into the GitHub runtime.
- Creation and verification of the Workshop Mods junction.
- Automatic disabling of the Workshop UE4SS runtime DLL.
- Automatic creation of missing `enabled.txt` files for eligible Workshop Lua/DLL mods.
- Installation and junction status checks.
- Safe restoration of the normal Workshop UE4SS runtime.
- Automatic rollback when an installation or restoration step fails.
- Interactive menu that remains open between operations.

## Requirements

- Windows Steam version of Palworld.
- Windows PowerShell 5.1 or newer.
- Internet access for automatic UE4SS installation or updates.
- The Workshop version of **UE4SS Experimental (Palworld)** must remain installed and enabled in Palworld's Mod Manager.
- Palworld must be closed before installation, synchronization or restoration.

The helper checks for a running Palworld process and refuses to modify the installation while the game is open.

## Usage

1. Download and extract the latest release ZIP.
2. Close Palworld completely.
3. Run `Palworld-UE4SS-Workshop-Helper-v2.0.0.cmd`.
4. Select **Install or update Experimental UE4SS automatically**.
5. Review the displayed release, asset, destination and SHA-256 information.
6. Confirm the installation.

The helper returns to the main menu when an operation finishes.

## Available actions

### Install or update Experimental UE4SS automatically

The helper:

1. Detects the Palworld installation.
2. Queries the official `UE4SS-RE/RE-UE4SS` GitHub release.
3. Selects only the normal ZIP from the `experimental-latest` tag.
4. Downloads and validates the archive.
5. Backs up the existing GitHub UE4SS runtime and proxy.
6. Preserves an existing `UE4SS-settings.ini`.
7. Merges existing Workshop UE4SS mods.
8. Creates and verifies the Mods junction.
9. Disables the Workshop runtime DLL without deleting it.
10. Creates missing `enabled.txt` files for eligible Workshop mods.

### Synchronize new Workshop UE4SS mods

Scans Palworld's Workshop metadata and creates only missing `enabled.txt` files for eligible Lua/DLL mods.

Unsafe package names and malformed metadata are rejected and reported. UE4SS internal modules, shared libraries and optional tools are excluded.

The helper shows a preview before creating any files.

### Check the current installation

Reports whether the following components are present and correctly configured:

- GitHub `dwmapi.dll` proxy;
- GitHub `ue4ss\UE4SS.dll` runtime;
- active or disabled Workshop runtime DLL;
- Workshop Mods junction;
- expected junction target;
- GitHub UE4SS log.

### Restore the normal Workshop UE4SS runtime

The helper:

1. Creates a timestamped backup of the GitHub runtime and installed mods.
2. Verifies the Workshop Mods junction and its target.
3. Removes only the verified junction.
4. Restores the mods into a normal Workshop directory.
5. Reactivates the Workshop UE4SS DLL.
6. Moves the GitHub runtime and proxy into the backup.

If restoration fails, the helper attempts to restore the previous GitHub workaround automatically.

## Download security

The automatic installer accepts releases only from:

```text
https://github.com/UE4SS-RE/RE-UE4SS
```

It requires the exact tag:

```text
experimental-latest
```

The helper excludes DEV, debug, symbols, source, custom-configuration and unrelated archives.

Before installation, it verifies:

- the GitHub release and download addresses;
- the downloaded file size;
- the SHA-256 digest published by GitHub, when available;
- every path stored inside the ZIP;
- the total extracted size;
- the presence of `dwmapi.dll`;
- the presence of `ue4ss\UE4SS.dll`;
- that the archive contains exactly one supported installation layout.

The downloaded UE4SS files are extracted and copied but never executed by the helper.

## PowerShell execution policy

The `.cmd` file contains its PowerShell code as plain text. It starts that embedded code using `ExecutionPolicy Bypass` only for the PowerShell process launched by the helper.

It does not change the Windows system or user execution policy.

You can inspect the complete embedded PowerShell source below the following marker inside the `.cmd` file:

```text
### POWERSHELL PAYLOAD ###
```

## Backups

Backups are stored inside the selected Palworld installation folder with names similar to:

```text
_UE4SS-Helper-Backup-20260804-120000-Install
_UE4SS-Helper-Backup-20260804-120000-Restore
```

Each backup contains a `backup-manifest.json` describing the operation, helper version, creation time and relevant source information.

Do not delete a backup until the game and all required mods have worked correctly for several sessions.

## Limitations

- The helper is intended only for the Windows Steam version of Palworld.
- Compatibility cannot be guaranteed for every Workshop package or future Palworld/UE4SS release.
- Automatic installation depends on GitHub and an available Internet connection.
- If the official Experimental release structure changes unexpectedly, the helper stops instead of guessing which archive to install.
- Antivirus or Windows security warnings should be investigated rather than dismissed blindly.
- Keep independent backups of important mod configurations and saved data.

## Disclaimer

This is an unofficial community helper. It is not affiliated with or endorsed by Pocketpair, Valve, Steam, GitHub or the RE-UE4SS project.
