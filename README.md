# Palworld UE4SS Workshop Helper

This Windows helper accompanies the Steam guide for using the GitHub Experimental build of RE-UE4SS while keeping Palworld Workshop dependency detection working.

## Safety model

- Preview is the default for every operation that can change files.
- Apply actions require an additional confirmation in the launcher.
- Setup copies existing mods before replacing the Workshop `Mods` directory with a junction. The original directory is retained as a timestamped backup.
- Sync creates only missing `enabled.txt` files for Workshop packages identified as Lua mods. Invalid package names and malformed metadata are skipped and reported.
- Restore creates a timestamped backup, removes only the verified junction, restores a normal Workshop Mods directory, and reactivates the Workshop DLL.
- The tool never downloads anything and does not request administrator rights.

## Requirements

- Windows Steam version of Palworld.
- Windows PowerShell 5.1 or newer.
- The Workshop version of UE4SS must remain installed.
- For Setup, extract the GitHub Experimental RE-UE4SS build into `Pal\Binaries\Win64` first.
- Close Palworld before applying Setup, Sync, or Restore.

## Usage

1. Extract the release ZIP.
2. Read `Palworld-UE4SS-Workshop-Helper.ps1` if you want to inspect the exact operations.
3. Double-click `Run-Helper.cmd`.
4. Run the preview for the desired action.
5. Run its Apply counterpart only if the preview is correct.

The launcher remains open after each action and returns to the main menu. Cancelling an Apply confirmation also returns to the menu. Choose **Cancel** from the main menu when you are finished.

The launcher uses `ExecutionPolicy Bypass` only for the PowerShell process it starts. It does not change the system execution policy. This is required because scripts extracted from an Internet-downloaded ZIP may otherwise be blocked by Windows PowerShell.

## Actions

- **Status:** reports which runtime files and junction are present.
- **Setup:** merges existing Workshop UE4SS mods into the GitHub runtime, creates the junction, and disables the Workshop runtime DLL.
- **Sync:** creates missing `enabled.txt` files for eligible Workshop UE4SS Lua/DLL mods.
- **Restore:** backs up the GitHub runtime and mods, removes the verified junction, restores the Workshop layout, and reactivates the Workshop DLL.

## Limitations

This helper cannot guarantee compatibility with every Workshop package or future Palworld/UE4SS release. Keep backups and inspect the preview. Antivirus or Windows security warnings should be investigated rather than dismissed blindly.
