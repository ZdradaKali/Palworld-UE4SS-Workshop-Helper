# Palworld UE4SS Workshop Helper

A small Windows helper for using the Experimental GitHub build of RE-UE4SS without breaking Palworld's Workshop dependency detection.

It was originally made to accompany my Steam guide, mostly because copying several large PowerShell blocks by hand was not particularly convenient.

## Important

This workaround requires the **Experimental** build of RE-UE4SS.

The helper only downloads `experimental-latest` from the official [`UE4SS-RE/RE-UE4SS`](https://github.com/UE4SS-RE/RE-UE4SS) repository. It will not install a stable or DEV build.

This is for the **Windows Steam version of Palworld**.

## What it does

The helper can:

- Find your Palworld installation, including installations in another Steam library.
- Download and install the latest Experimental UE4SS build.
- Keep your existing `UE4SS-settings.ini`.
- Move existing Workshop UE4SS mods into the correct location.
- Create and verify the required Mods junction.
- Disable the Workshop runtime DLL without deleting it.
- Create missing `enabled.txt` files for compatible Workshop mods.
- Check whether the current setup looks correct.
- Return to the normal Workshop runtime later.
- Create backups before changing anything important.

Everything is contained in one `.cmd` file. The PowerShell source is embedded inside it as plain text and can be inspected with any text editor.

## How to use it

1. Download and extract the latest release ZIP.
2. Close Palworld completely.
3. Run `Palworld-UE4SS-Workshop-Helper-v2.0.0.cmd`.
4. Choose `Install or update Experimental UE4SS automatically`.
5. Read the summary and confirm if everything looks correct.

The tool returns to the main menu after each operation.

If you install more UE4SS Workshop mods later, use:

```text
Synchronize new Workshop UE4SS mods
```

## What gets downloaded

The installer checks the official GitHub release tagged:

```text
experimental-latest
```

It ignores DEV builds, debug files, symbols, source archives and unrelated ZIP files.

Before installing anything, it checks:

- the repository and release URLs;
- the downloaded file size;
- the SHA-256 digest published by GitHub, when available;
- the paths stored inside the ZIP;
- the expected `dwmapi.dll` and `ue4ss\UE4SS.dll` files.

If the release contains something unexpected, the helper stops instead of trying to guess.

The downloaded UE4SS files are never executed by the helper. They are only checked, extracted and copied into the Palworld folder.

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
- Internet access is required for automatic installation and updates.
- The Workshop version of UE4SS must remain installed and enabled for dependency detection.
- Future Palworld, Workshop or UE4SS updates may require changes to the helper.
- This cannot account for every unusual or manually modified installation.

If Windows or your antivirus displays a warning, check where the file came from instead of blindly dismissing it.

## Disclaimer

This is an unofficial community tool. It is not affiliated with Pocketpair, Valve, GitHub or the RE-UE4SS project.
