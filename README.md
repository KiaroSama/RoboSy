# RoboSy

Fast, portable Windows file-management helper for `robocopy` move/copy workflows, permanent deletion, and move-to-symlink relocation.

**Author:** Kiaro Sama

**GitHub:** <https://github.com/KiaroSama>

**Repository:** <https://github.com/KiaroSama/RoboSy>

**License:** MIT

**Platform:** Windows

## Description

RoboSy is an interactive PowerShell tool built around Windows `robocopy`. It provides a numbered terminal menu for moving, copying, permanently deleting, and relocating files or folders while leaving a symbolic link or junction at the original path.

It is designed for users who want a simple Windows terminal workflow without manually writing long `robocopy`, delete, or symbolic-link commands.

## Features

- Move files and folders with `robocopy`.
- Copy files and folders with `robocopy`.
- Permanently delete files or folders without using the Recycle Bin.
- Move data to a new location and leave a symbolic link or junction at the original path.
- Accept typed, pasted, or drag-and-dropped paths in normal terminal mode.
- Relaunch as Administrator by typing `admin` at prompts.
- Fall back from directory symbolic links to junctions when symlink creation is blocked.
- Print total elapsed time after each operation.
- Write daily log files next to the script, with fallback to `%LOCALAPPDATA%\RoboSy\logs`.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Windows built-in `robocopy.exe`
- Administrator rights or Windows Developer Mode for file symbolic links

## Safety Notes

RoboSy can move, copy, delete, and relink real files and folders. Test it on a small dummy folder before using it on important data.

Fast Delete is permanent and does not use the Recycle Bin. Always double-check source and target paths before confirming an operation.

RoboSy blocks drive roots, share roots, and protected root paths for destructive operations, but you should still review every path carefully.

## Installation

Clone the repository:

```powershell
git clone https://github.com/KiaroSama/RoboSy.git
cd RoboSy
```

Install the `RoboSy` command shim:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-RoboSyPath.ps1
```

Open a new terminal and run:

```powershell
RoboSy
```

You can also run RoboSy directly by double-clicking one of the launcher files:

| File | Use |
| --- | --- |
| `RoboSy.cmd` | Normal non-elevated launcher. Recommended when you need drag and drop. |
| `RoboSy Admin.cmd` | Elevated launcher for protected paths and file symbolic links. |

> Windows blocks drag and drop from Explorer into elevated Administrator terminals. Use normal mode when you need drag and drop.

## Usage

Run RoboSy, then choose an option from the main menu.

| Option | Action |
| :---: | --- |
| `1` | Move a file or folder with `robocopy`. This is the default option. |
| `2` | Copy a file or folder with `robocopy`. |
| `3` | Permanently delete a file or folder without the Recycle Bin. |
| `4` | Move an item to a target path, then create a symbolic link or junction at the original path. |

Prompt shortcuts:

| Input | Action |
| --- | --- |
| `0` | Go back to the previous menu or prompt. |
| `admin` | Relaunch RoboSy as Administrator. |
| `exit` or `quit` | Quit RoboSy. |

## Operations

### Move

The move operation uses `robocopy` to move a selected file or folder to a destination path.

Use this when you want RoboSy to transfer data and remove the original copy after a successful move.

### Copy

The copy operation uses `robocopy` to copy a selected file or folder to a destination path.

Use this when you want to keep the original item in place.

### Fast Delete

Option `3` permanently deletes the selected path.

Behavior:

- Files are deleted directly with `cmd.exe /d /c del /f /q /a`.
- Folders are purged with `robocopy /MIR /MT:32`, then the selected folder itself is removed.
- Drive roots, share roots, and protected root paths are blocked.
- Symbolic links and junctions are removed as links only. Their real targets are not followed.

### Move + Symlink

Option `4` asks for two paths:

1. **Original path**
   The path where the symbolic link or junction will live.
2. **Target path**
   The path where the real file or folder will live.

Behavior:

- If the original path exists and the target path does not exist, RoboSy moves the item to the target path and creates a link at the original path.
- If the original path is missing and the target path exists, RoboSy only creates the link.
- If both paths already exist, RoboSy stops without overwriting either path.
- If directory symlinks are unavailable, RoboSy tries a junction fallback.

## Marker File

After a successful Move + Symlink job, RoboSy writes a marker file at the real target so the original link path can be traced later.

| Target type | Marker location | Marker name |
| --- | --- | --- |
| Folder, for example `D:\example` | Inside `D:\example\` | `Symlink path_example.txt` |
| File, for example `D:\folder\app.exe` | Next to the file | `Symlink path_app.exe.txt` |

The marker file contains the original link path, such as:

```text
C:\example
```

## Logs

RoboSy appends operation details to a daily log file:

```text
.\logs\robosy-YYYY-MM-DD.log
```

If the script folder is not writable, logs are written under:

```text
%LOCALAPPDATA%\RoboSy\logs
```

The active log path is printed in the header as:

```text
Logging to: ...
```

Runtime logs are ignored by Git and should not be published.

## Repository Files

| File | Purpose |
| --- | --- |
| `RoboSy.ps1` | Main interactive PowerShell script. |
| `RoboSy.cmd` | Normal launcher. |
| `RoboSy Admin.cmd` | Administrator launcher. |
| `Install-RoboSyPath.ps1` | Adds RoboSy to the user `PATH` and installs the command shim. |
| `README.md` | Project documentation. |
| `LICENSE` | MIT License text. |
| `ATTRIBUTION.md` | Standalone attribution notice. |
| `GITHUB_RELEASE_NOTES.md` | Draft release notes for GitHub. |
| `.gitignore` | Excludes local logs, notes, secrets, cache, temporary files, and generated output. |
| `.gitattributes` | Repository text and line-ending settings. |

## Ignored Local Data

These local paths are intentionally ignored by Git:

| Path or pattern | Reason |
| --- | --- |
| `.Commands/`, `.Comments/`, `Commands/` | Local request notes and working prompts. |
| `logs/`, `log/`, `Logs/`, `Log/`, `*.log` | Runtime logs. |
| `.env`, `.env.*`, keys, credentials, tokens, cookies, sessions | Local secrets and private configuration. |
| `tmp/`, `temp/`, `Temp/`, backup files | Temporary local files. |
| `.cache/`, `cache/`, `Cache/`, language cache folders | Local caches. |
| `output/`, `downloads/`, `dist/`, `build/`, `processed/`, `remuxed/` | Generated output. |
| `.vscode/`, `.idea/`, `*.code-workspace` | Local editor settings. |
| OS metadata files | Local operating-system artifacts. |

## Troubleshooting

### Drag and drop does nothing

Make sure RoboSy is not running as Administrator. Windows does not allow Explorer drag and drop into elevated Administrator terminals.

### `RoboSy` is not recognized

Open a new terminal after running the installer.

If it still does not work, run the installer again:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-RoboSyPath.ps1
```

### Symbolic link creation fails

Run RoboSy as Administrator, or enable Windows Developer Mode.

For folders, RoboSy may fall back to a junction when directory symlink creation is blocked.

### Fast Delete fails

Check for locked files, missing permissions, antivirus interference, or files currently used by another process.

### Logs are not written next to the script

If the script folder is not writable, RoboSy writes logs under:

```text
%LOCALAPPDATA%\RoboSy\logs
```

## License and Attribution

This project is released under the [MIT License](LICENSE).

You are free to use, copy, modify, publish, distribute, sublicense, and use this project in your own projects, including free or commercial projects.

However, if you copy, modify, publish, distribute, or include substantial parts of this project in another project, you must keep the original copyright and license notice.

Please preserve this attribution:

```text
RoboSy - Copyright (c) 2026 Kiaro Sama
Original author: Kiaro Sama
GitHub: https://github.com/KiaroSama
Original repository: https://github.com/KiaroSama/RoboSy
Licensed under the MIT License.
```

## Donate

If this project helps you, donations are appreciated.

| Currency | Network | Address |
| --- | --- | --- |
| Bitcoin (BTC) | Bitcoin | `bc1qmth5m03pu5hujw5xw5jmywam3jj3sqwqupesdt` |
| USDT, BNB, USDC, etc. | BEP20 | `0x0Bd0BA443a8B9cf15922bf7f0Bb0a4b495fD06Ef` |
| USDT, TRX, USDC, etc. | TRC20 | `TWBA3xFTqgZAeAYMxqo85xWnzvty3DcAhw` |
| Ethereum (ETH) | ERC20 | `0x0Bd0BA443a8B9cf15922bf7f0Bb0a4b495fD06Ef` |
| TON | TON | `UQCN8Umo_OfOWqImZetQsrNStPcmLkMAKajFyiCOhso23NDb` |
| Litecoin (LTC) | LTC | `ltc1qntqnnrunadurnw4cshv3qgspywrueyyeyngwuy` |
| Solana (SOL) | Solana | `7B2wkczUjmkDhETwQuknBL8sUsbuV7nErxc317TmQuwR` |
| Polygon (POL) | Polygon | `0x0Bd0BA443a8B9cf15922bf7f0Bb0a4b495fD06Ef` |
