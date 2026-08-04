# Palworld UE4SS Workshop Helper

A small Windows helper for using a working Experimental UE4SS build without breaking Palworld's Workshop dependency detection.

I originally made it to accompany my Steam guide because copying several large PowerShell blocks by hand was not particularly convenient.

## Important

This helper supports two reviewed Experimental UE4SS builds. The [official Experimental release](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest) is the recommended default because it is the newest upstream version.

The [Palworld-specific Experimental release](https://github.com/Okaetsu/RE-UE4SS/releases/tag/experimental-palworld) is available as an alternative for mods that specifically require it, such as PalSchema, or if the official build causes a compatibility problem.

Version 2.1.0 accepts only these reviewed archives:

```text
Official: UE4SS-RE/RE-UE4SS, experimental-latest
          UE4SS_v3.0.1-1018-g662df915.zip

Palworld: Okaetsu/RE-UE4SS, experimental-palworld
          UE4SS-Palworld.zip
```

Both archive SHA-256 values are pinned in the helper. If either release asset changes, the helper stops and asks you to download an updated helper instead of installing an unreviewed archive. It does not fall back to or silently select another build.

This is for the **Windows Steam client version of Palworld**. It is not a dedicated-server installer.

## What it does

The helper can:

- Find your Palworld installation, including installations in another Steam library.
- Let you choose and install either reviewed Experimental UE4SS build.
- Build a clean runtime when installing or switching builds, so files left by the previous build cannot remain active.
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
5. Choose the official build unless a mod requires the Palworld-specific build or you are troubleshooting a compatibility problem.
6. Read the summary and confirm if everything looks correct.

The tool returns to the main menu after each operation.

You can run the installation option again later and choose the other build. The helper prepares the replacement separately, preserves your mods and `UE4SS-settings.ini`, then moves the previous runtime into the new backup before installing the replacement. It does not extract one provider's runtime over the other.

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
- the additional SHA-256 value pinned for the selected build in this helper release;
- every path stored inside the ZIP;
- the expected `dwmapi.dll` and `ue4ss\UE4SS.dll` files.

If anything is unexpected, the helper stops instead of trying to guess.

The helper also makes sure `MemberVariableLayout.ini` exists. The Palworld-specific archive already includes it; when using the official archive, the helper copies the Workshop version if necessary.

The downloaded UE4SS files are not executed by the helper. They are checked, extracted and copied into the Palworld folder for the game to load later.

## Backups

Backups are placed directly inside the selected Palworld installation folder. Their names look like this:

```text
_UE4SS-Helper-Backup-20260804-120000-Install
_UE4SS-Helper-Backup-20260804-120000-Restore
```

Keep the latest backup until you have launched the game a few times and confirmed that your mods still work.

If a clean replacement fails after the old runtime has been moved, the helper attempts to put the previous runtime, proxy DLL and junction state back automatically. Failed replacement files are retained in the backup for inspection.

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
