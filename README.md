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
- Create a symbolic link only, without moving anything, and let RoboSy work out the direction so the order of the two paths does not matter (Symlink Only).
- Accept typed, pasted, or drag-and-dropped paths in normal terminal mode, confirmed with Enter (no auto-accept).
- Keep your previous selections visible at the top of each step instead of clearing the screen.
- Ask for an explicit confirmation before every move, copy, delete, or link job runs.
- Relaunch as Administrator by typing `admin` at prompts.
- Fall back from directory symbolic links to junctions when symlink creation is blocked.
- Refuse symbolic links, junctions, and other reparse points as Move/Copy sources to avoid accidentally moving the real target's contents.
- Refuse drive roots, share roots, and protected system/profile roots as Move/Copy sources.
- Transfer a selected folder as a folder, preserving its name at the destination, instead of flattening its contents into the destination root.
- Block a Move/Copy when the resolved destination is a type conflict (a folder onto an existing file, or a file onto an existing folder) instead of merging or overwriting the wrong thing.
- Refuse a Move/Copy destination that is itself a symbolic link, junction, or other reparse point, and re-check the destination immediately before running so a change between review and execution stops the job instead of running it.
- Roll back automatically if replacing an existing Move + Symlink link fails partway through, so a failed replacement never leaves you without the original link.
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

Move and Copy refuse source paths that are symbolic links, junctions, or other reparse points. Choose the real target path directly, or use Move + Symlink when you want to manage a link.

Move and Copy also refuse a destination that is a symbolic link, junction, or other reparse point, and refuse a type conflict (folder onto an existing file, or file onto an existing folder) instead of merging or overwriting the wrong thing. The destination is checked again immediately before the job runs, so a change between the review screen and confirmation stops the job instead of running it.

If replacing an existing Move + Symlink link fails partway through, RoboSy restores the original link automatically and reports the job as failed, never as successful.

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
| `5` | Create a symbolic link only (never move); the order of the two paths does not matter. |

Prompt shortcuts:

| Input | Action |
| --- | --- |
| `0` | Go back to the previous menu or prompt. |
| `admin` | Relaunch RoboSy as Administrator. |
| `exit` or `quit` | Quit RoboSy. |

For drag and drop, drop the path into the terminal, then press Enter to confirm it. RoboSy never auto-accepts a path, so you always stay in control of each step.

RoboSy keeps your completed selections (mode, source, destination) visible in a "Selections so far" block at the top of every step, so you can see the previous steps as you move forward. Before any job runs, RoboSy shows a final summary and asks you to confirm.

RoboSy delegates line editing to the active PowerShell host instead of implementing its own key-processing loop. Editing behavior such as Backspace, arrow keys, Escape, history, and Ctrl+C may vary by host and terminal. If the active host has no usable line reader or throws `NotImplementedException`, RoboSy falls back to `[Console]::ReadLine()`.

## Operations

### Move

The move operation uses `robocopy` to move a selected file or folder to a destination path.

Use this when you want RoboSy to transfer data and remove the original copy after a successful move.

For a folder source, RoboSy transfers the folder itself: entering destination `F:\B` for source `E:\A\Docs` moves it to `F:\B\Docs`, not into `F:\B` directly. A destination that already ends with the source folder's name (for example `F:\B\Docs`) is used as-is instead of doubling the name. A single file keeps its original file name at the destination.

If the resolved final path already exists and holds other items, RoboSy shows what it found and asks for a separate confirmation before merging into it or overwriting a same-named file. A type conflict at the final path (a folder onto an existing file, or a file onto an existing folder) is blocked outright; `robocopy` is never invoked for it.

If `robocopy` leaves an empty source folder behind after a directory move, RoboSy attempts to remove that empty source folder.

Move uses `/XJ`, so nested junctions are excluded instead of being followed.

### Copy

The copy operation uses `robocopy` to copy a selected file or folder to a destination path, using the same folder-preserving destination behavior as Move.

Use this when you want to keep the original item in place.

Copy uses `/XJ`, so nested junctions are excluded instead of being followed.

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
- If both paths already exist, RoboSy stops without overwriting either path, unless the target is an existing folder whose name already matches the source folder name; in that case RoboSy moves the source's contents into that existing folder before creating the link.
- If the original path is already a symbolic link or junction, RoboSy leaves it untouched until you confirm the replacement, then removes only the link entry (never its target) immediately before creating the new link.
- If creating the replacement link fails after the old link was removed, RoboSy immediately restores the original link and reports the job as failed. If the restore itself cannot complete, RoboSy reports a critical error with the original link's target and a manual recovery command; the old target is never deleted or modified either way.
- If directory symlinks are unavailable, RoboSy tries a junction fallback.

### Symlink Only

Option `5` creates a symbolic link only and never moves or deletes anything. It asks for two paths:

1. **Path 1** (the real source, if both paths exist)
2. **Path 2** (the link location; a folder, if both paths exist)

Behavior:

- **Only one path is a real file/folder — order does not matter.** Whichever path is a real, existing file or folder (not itself a link) becomes the link **target**; the other path — the one that is missing, or is already a symbolic link or junction — becomes the **link** location. RoboSy creates the link at the missing/link side, pointing to the real item. Nothing is moved.
- **Both paths already exist — order matters.** Path 1 is treated as the real source, and the link is created **inside** Path 2 as `<Path 2>\<Path 1 name>`, pointing to Path 1. Nothing inside Path 2 is moved or deleted. Path 2 must be a folder (a file is rejected), and if Path 2 already contains a real item with Path 1's name, RoboSy stops rather than overwriting it. The exact link that will be created is shown before you confirm.
- **Neither path is a real file/folder — RoboSy stops,** because there is nothing to link to.
- If the link side is already a symbolic link or junction, RoboSy replaces it with the same rollback-safe transaction used by Move + Symlink: the old link is removed only immediately before the new link is created, its target is never followed, and a failed replacement restores the original link and reports failure.
- If directory symlinks are unavailable, RoboSy tries a junction fallback, exactly like Move + Symlink.

## Marker File

After a successful Move + Symlink or Symlink Only job, RoboSy writes a marker file at the real target so the link path can be traced later.

| Target type | Marker location | Marker name |
| --- | --- | --- |
| Folder, for example `D:\example` | Inside `D:\example\` | `Symlink path_example.txt` |
| File, for example `D:\folder\app.exe` | Next to the file | `Symlink path_app.exe.txt` |

The marker file lists the link path(s) that point at this target, one per line. Because a single target can be linked from several places, each new link is **appended** on its own line rather than overwriting the previous entries, and the same link path is never added twice:

```text
C:\example
D:\another\link\to\example
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
| `RoboSy.ps1` | Entry point: dot-sources every `lib/*.ps1` module, handles elevation/relaunch, then runs the interactive main menu loop. |
| `lib/Elevation.ps1` | Administrator relaunch: Windows Terminal/pwsh discovery, argument building, and `Invoke-AdminSwitch`. |
| `lib/Logging.ps1` | Daily log file initialization and `Write-Log`. |
| `lib/Console-UI.ps1` | Console colors/state, ANSI-aware line writers, prompts, breadcrumbs, and the session header. |
| `lib/Input.ps1` | Navigation-keyword checks and the redirected/non-redirected console input pipeline (`Read-ConsoleText`, `Read-HostUiLine`, `Read-YesNo`). |
| `lib/Path-Helpers.ps1` | Path normalization/comparison, link metadata, path status, and the protected-root guard. |
| `lib/Robocopy-Core.ps1` | Native `robocopy`/`cmd.exe` command wrappers and exit-code descriptions. |
| `lib/Standard-Jobs.ps1` | Move/Copy destination resolution, final-path classification, `Invoke-RobocopyJob`, and Fast Delete. |
| `lib/Link-Management.ps1` | Rollback-safe symbolic link/junction creation and replacement, shared by Move + Symlink and Symlink Only. |
| `lib/Menu-Prompts.ps1` | Main menu choice and the source/destination path prompts. |
| `tests/TestHelpers.ps1` | Shared test assertions, sandbox helpers, and the interactive end-to-end test harness. |
| `tests/RoboSy.Tests.ps1` | Regression tests for destination resolution and native-command wrappers. |
| `tests/RoboSy.LinkSafety.Tests.ps1` | Regression tests for the rollback-safe Move + Symlink replacement transaction. |
| `tests/RoboSy.Classification.Tests.ps1` | Regression tests for final-path classification, type conflicts, reparse-point hardening, and execution-time revalidation. |
| `tests/RoboSy.Input.Tests.ps1` | Regression tests for `Read-ConsoleText`'s redirected/non-redirected input paths and the `Read-HostUiLine` fallback chain. |
| `tests/RoboSy.SymlinkOnly.Tests.ps1` | Regression tests for Symlink Only direction detection and its create-only, never-move end-to-end behavior. |
| `tests/Invoke-RoboSyTests.ps1` | Bounded parallel test runner (runs every `*.Tests.ps1` concurrently as isolated child processes); used locally and in CI. |
| `RoboSy.cmd` | Normal launcher. |
| `RoboSy Admin.cmd` | Administrator launcher. |
| `Install-RoboSyPath.ps1` | Adds RoboSy to the user `PATH` and installs the command shim. |
| `README.md` | Project documentation. |
| `CHANGELOG.md` | User-facing release history. |
| `LICENSE` | MIT License text. |
| `ATTRIBUTION.md` | Standalone attribution notice. |
| `GITHUB_RELEASE_NOTES.md` | Draft release notes for GitHub. |
| `.gitignore` | Excludes local logs, notes, secrets, cache, temporary files, and generated output. |
| `.gitattributes` | Repository text and line-ending settings. |
| `PSScriptAnalyzerSettings.psd1` | PSScriptAnalyzer rule configuration used locally and in CI. |
| `.github/workflows/lint.yml` | GitHub Actions workflow that parses and analyzes the PowerShell files. |
| `.editorconfig` | Shared editor settings (encoding, line endings, indentation). |
| `.github/CONTRIBUTING.md` | Contribution and local development guide. |
| `.github/SECURITY.md` | Security policy and private vulnerability reporting. |
| `.github/ISSUE_TEMPLATE/` | Bug report and feature request templates. |
| `.github/PULL_REQUEST_TEMPLATE.md` | Pull request checklist. |
| `.github/dependabot.yml` | Weekly GitHub Actions version updates. |

## Ignored Local Data

These local paths are intentionally ignored by Git:

| Path or pattern | Reason |
| --- | --- |
| `.Commands/`, `.Comments/`, `Commands/`, `.claude/`, `.kiro/`, `.codex/`, `.ignoreme/` | Local request notes, AI tool state, and working prompts. |
| `secrets.md`, `explain-AI.md` | Local-only secret registry and private notes that must never be published. |
| `logs/`, `log/`, `Logs/`, `Log/`, `*.log` | Runtime logs. |
| `.env`, `.env.*`, keys, credentials, tokens, cookies, sessions | Local secrets and private configuration. |
| `tmp/`, `temp/`, `Temp/`, backup files | Temporary local files. |
| `.cache/`, `cache/`, `Cache/`, language cache folders | Local caches. |
| `output/`, `downloads/`, `dist/`, `build/`, `processed/`, `remuxed/` | Generated output. |
| `.vscode/`, `.idea/`, `*.code-workspace` | Local editor settings. |
| OS metadata files | Local operating-system artifacts. |

## Development

RoboSy is linted with [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview) using the rules in `PSScriptAnalyzerSettings.psd1`, and its regression tests run under both Windows PowerShell 5.1 and PowerShell 7+. The same checks run in GitHub Actions (`.github/workflows/lint.yml`, using `actions/checkout@v7` with `persist-credentials: false`) on every push and pull request that touches `RoboSy.ps1`, a file under `tests/`, the analyzer settings, or the workflow itself. CI fails closed if zero `tests/*.Tests.ps1` files are discovered, instead of silently reporting success.

Run the checks locally before pushing:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

A clean run reports no issues.

Run the regression tests locally with the parallel runner (this is what CI uses). It runs every `tests/*.Tests.ps1` file concurrently as isolated child processes, with a bounded worker ceiling and per-file/whole-run timeouts:

```powershell
# Windows PowerShell 5.1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-RoboSyTests.ps1 -TestHost powershell.exe
# PowerShell 7+
pwsh -NoProfile -File .\tests\Invoke-RoboSyTests.ps1 -TestHost pwsh
```

The runner prints each file's passed/failed/skipped counts and total wall time, and exits non-zero on any failure, timeout, or if zero test files are discovered. The worker count defaults to `max(2, cores-2)` (clamped to the number of test files, max 8) and can be capped with `-MaxWorkers N` or the `HOOKMAKER_MAX_TEST_WORKERS` / `ROBOSY_MAX_TEST_WORKERS` environment variable. Only the files run in parallel — each file stays internally sequential, and every file uses its own unique temporary sandbox, so they share no state. You can still run a single file directly (for example `pwsh -NoProfile -File .\tests\RoboSy.Input.Tests.ps1`) when debugging one suite.

Tests run entirely inside disposable temporary directories and clean up after themselves; the interactive end-to-end scenarios in `RoboSy.LinkSafety.Tests.ps1`, `RoboSy.Classification.Tests.ps1`, and `RoboSy.SymlinkOnly.Tests.ps1` drive a disposable copy of `RoboSy.ps1` through piped input, so its own log directory never touches the real repository. `RoboSy.Input.Tests.ps1` covers `Read-ConsoleText`'s redirected and non-redirected input paths, including the `Read-HostUiLine` host-line-reader fallback chain, using injected fakes rather than a real keyboard.

### Manual terminal smoke test

Automated tests inject a fake host-line reader for the non-redirected input path, since driving the active host's real line editor needs an actual keyboard and terminal. RoboSy delegates that editing to the host rather than implementing it, so exact behavior for Backspace, arrow keys, Escape, and Ctrl+C can vary by host and terminal — verify it in the specific host you care about rather than assuming one terminal's behavior applies everywhere. Before relying on a change to `Read-ConsoleText`/`Read-HostUiLine`, run RoboSy in a real terminal under both Windows PowerShell 5.1 and PowerShell 7+ and check:

- Ordinary typing and Enter
- Pasting a path
- Explorer drag-and-drop, then pressing Enter to confirm it
- Backspace
- Arrow-key editing (left/right, and recalling history if your terminal supports it)
- Escape (behavior is host-defined; ConsoleHost typically clears the current line)
- Typing `admin`, `0`, `exit`, and `quit`
- Ctrl+C
- Unicode text
- A path containing spaces, an apostrophe, and `[`/`]` characters

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
