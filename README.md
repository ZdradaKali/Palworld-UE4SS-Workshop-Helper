# Palworld UE4SS Workshop Helper

A small Windows helper for using a working Experimental UE4SS build without breaking Palworld's Workshop dependency detection.

I originally made it to accompany my Steam guide because copying several large PowerShell blocks by hand was not particularly convenient.

## Important

This helper uses the Palworld-specific Experimental release from [`Okaetsu/RE-UE4SS`](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld).

Version 2.1.0 accepts only:

```text
Tag:   experimental-palworld
Asset: UE4SS-Palworld.zip
```

The archive SHA-256 is pinned in the helper. If the release asset changes, the helper stops and asks you to download an updated helper instead of installing an unreviewed archive.

This is for the **Windows Steam client version of Palworld**. It is not a dedicated-server installer.

## What it does

The helper can:

- Find your Palworld installation, including installations in another Steam library.
- Download and install the reviewed Palworld-specific Experimental UE4SS build.
- Keep your existing `UE4SS-settings.ini`.
- Move existing Workshop UE4SS mods into the correct location.
- Create and verify the required Mods junction.
- Disable the Workshop runtime DLL without deleting it.
- Verify that `MemberVariableLayout.ini` is present.
- Create missing `enabled.txt` files for compatible Workshop mods.
- Check whether the current setup looks correct.
- Return to the normal Workshop runtime later.
- Create backups before changing anything important.

Everything is contained in one `.cmd` file. The PowerShell source is embedded inside it as plain text and can be inspected with any text editor.

## How to use it

1. Download and extract the latest release ZIP.
2. Close Palworld completely.
3. Run `Palworld-UE4SS-Workshop-Helper.cmd`.
4. Choose `Install or update Experimental UE4SS automatically`.
5. Read the summary and confirm if everything looks correct.

The tool returns to the main menu after each operation.

If you install more UE4SS Workshop mods later, use:

```text
Synchronize new Workshop UE4SS mods
```

## Download checks

Before installing anything, the helper checks:

- the GitHub repository, release tag and exact asset name;
- the release and download URLs;
- the downloaded file size;
- the SHA-256 digest published by GitHub;
- the additional SHA-256 value pinned in this helper release;
- every path stored inside the ZIP;
- the expected `dwmapi.dll`, `ue4ss\UE4SS.dll` and `ue4ss\MemberVariableLayout.ini` files.

If anything is unexpected, the helper stops instead of trying to guess.

The downloaded UE4SS files are not executed by the helper. They are checked, extracted and copied into the Palworld folder for the game to load later.

## Backups

Backups are placed directly inside the selected Palworld installation folder. Their names look like this:

```text
_UE4SS-Helper-Backup-20260804-120000-Install
_UE4SS-Helper-Backup-20260804-120000-Restore
```

Keep the latest backup until you have launched the game a few times and confirmed that your mods still work.

## PowerShell warning

The launcher uses `ExecutionPolicy Bypass` only for the PowerShell process it starts. It does not change your Windows execution policy.

The embedded PowerShell source begins after this line inside the `.cmd` file:

```text
### POWERSHELL PAYLOAD ###
```

Feel free to read it before running anything.

## A few limitations

- Palworld must be closed before the helper can change files.
- Internet access is required for automatic installation.
- The Workshop version of UE4SS must remain installed and enabled for dependency detection.
- The helper does not configure or support dedicated servers.
- Future Palworld, Workshop or UE4SS updates may require a new helper release.
- This cannot account for every unusual or manually modified installation.

If Windows or your antivirus displays a warning, check where the file came from instead of blindly dismissing it.

## Credits

- [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) is maintained by the UE4SS project and its contributors.
- The [Palworld-specific Experimental release](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld) is provided by Okaetsu.

## Disclaimer

This is an unofficial community tool. It is not affiliated with Pocketpair, Valve, GitHub, Okaetsu or the RE-UE4SS project.
