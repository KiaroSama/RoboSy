# RoboSy v1.2.0

Suggested tag: `v1.2.0`

RoboSy v1.2.0 is a usability and safety update focused on the interactive prompt
flow, clearer colors, and stronger repository tooling.

## Added

- Added `PSScriptAnalyzerSettings.psd1` and a `Lint` GitHub Actions workflow that parses and analyzes all PowerShell files on push and pull request.
- Added GitHub community files: `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates, a Dependabot configuration, and `.editorconfig`.
- Expanded `.gitignore` to protect local-only and assistant paths (`.ignoreme`, `.kiro/`, `.codex/`, `secrets.md`, `explain-AI.md`).

## Changed

- Paths are never auto-accepted. Every source, destination, and target path must be confirmed with Enter, so you stay in control of each step.
- Move, Copy, Fast Delete, and Move + Symlink jobs now show a final summary and ask for an explicit confirmation before they run.
- Completed selections stay visible in a "Selections so far" block, and the terminal is no longer cleared on each step. The title banner and separator line are shown once at startup.
- Prompt description lines are now shown as parenthesized yellow hints.
- Recolored the navigation prompt: orange `back=0`, blue `quit`, lime-green `Run as admin`, bright-green default option markers such as `[1]`, and uncolored braces.

## Fixed

- Fixed the screen-clearing behavior that hid previous prompts and made it hard to review earlier steps.

## Removed

- Removed the idle-based drag/drop auto-accept input path and its now-unused helper.

## Breaking Changes

- None. Existing workflows behave the same, except paths now require Enter to confirm and jobs require an explicit confirmation before running.

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or PowerShell 7+
- Windows built-in `robocopy.exe`
- Administrator rights or Windows Developer Mode for file symbolic links

## Safety Notes

RoboSy can move, copy, delete, and relink real files and folders. Always test with a small dummy folder before using it on important data.

Fast Delete is permanent and bypasses the Recycle Bin.

Move and Copy use `/XJ`, so nested junctions are excluded instead of being followed.

## Upgrade Notes

- No migration is required. If you relied on dragged paths being accepted automatically, just press Enter to confirm each path now.

## License and Attribution

RoboSy is released under the MIT License.

Copyright (c) 2026 Kiaro Sama

Anyone who copies, modifies, republishes, redistributes, or includes substantial parts of RoboSy must preserve the original copyright and MIT License notice.

- Original author: Kiaro Sama
- GitHub: https://github.com/KiaroSama
- Original repository: https://github.com/KiaroSama/RoboSy
