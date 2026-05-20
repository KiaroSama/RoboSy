# RoboSy v1.0.0

First public release of RoboSy, a portable Windows PowerShell helper for `robocopy` move/copy workflows, permanent deletion, and move-to-symlink relocation.

## Features

- Move files and folders with Windows `robocopy`.
- Copy files and folders with Windows `robocopy`.
- Permanently delete files or folders without using the Recycle Bin.
- Delete folder contents using `robocopy /MIR /MT:32`, then remove the selected folder itself.
- Move real data to a target path and create a symbolic link or junction at the original path.
- Accept typed, pasted, or drag-and-dropped paths in normal terminal mode.
- Relaunch as Administrator by typing `admin` at prompts.
- Fall back from directory symbolic links to junctions when symlink creation is blocked.
- Print total elapsed time after each operation.
- Write daily operation logs.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Windows built-in `robocopy.exe`
- Administrator rights or Windows Developer Mode for file symbolic links

## Safety Notes

RoboSy can move, copy, delete, and relink real files and folders.

Fast Delete is permanent and bypasses the Recycle Bin. Test with a small dummy folder before using it on important data, and always review paths carefully before confirming an operation.

RoboSy blocks drive roots, share roots, and protected root paths for destructive operations, but users remain responsible for confirming the correct paths.

## Quick Start

```powershell
git clone https://github.com/KiaroSama/RoboSy.git
cd RoboSy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-RoboSyPath.ps1
```

Open a new terminal, then run:

```powershell
RoboSy
```

You can also run:

- `RoboSy.cmd` for normal non-elevated use.
- `RoboSy Admin.cmd` for Administrator mode.

## Included Files

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
| `.gitignore` | Release-safe ignore rules for local notes, logs, secrets, cache, temp files, and generated output. |
| `.gitattributes` | Text and line-ending settings. |

## License

RoboSy is released under the MIT License.

Copyright (c) 2026 Kiaro Sama

## Attribution Note

Anyone who copies, modifies, republishes, redistributes, or includes substantial parts of RoboSy must preserve the original copyright and MIT License notice.

- Original author: Kiaro Sama
- GitHub: https://github.com/KiaroSama
- Original repository: https://github.com/KiaroSama/RoboSy
