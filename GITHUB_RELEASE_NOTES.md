# RoboSy v1.1.0

Suggested tag: `v1.1.0`

RoboSy v1.1.0 is a safety and reliability update for Move, Copy, Move + Symlink, path handling, and release documentation.

## Added

- Added `CHANGELOG.md` for release history.
- Added documentation for Move/Copy reparse-point source refusal and `/XJ` nested junction behavior.

## Changed

- Move and Copy now reject symbolic links, junctions, and other reparse-point paths as sources to avoid following source links.
- Directory Move now attempts to remove an empty source folder if `robocopy` leaves the source root behind.
- Move + Symlink now treats empty-source cleanup failure as a fatal move error because the original link path cannot be created while the real folder remains.
- Drag-and-drop path auto-accept is wired into source and destination prompts again.
- The installer writes the command shim with OEM encoding when available, with a fallback for older PowerShell versions.
- The normal launcher now pauses when `RoboSy.ps1` is missing, matching the Administrator launcher behavior.

## Fixed

- Fixed a critical Move/Copy safety issue where a symlink or junction source could cause `robocopy` to move or copy the real target contents.
- Fixed Move + Symlink file relocation so an existing rename target is detected before link creation.
- Fixed wildcard-sensitive `New-Item -Path` usage for paths containing characters such as `[` and `]`.
- Fixed the destination warning so file-looking destination paths are shown for directory sources too.
- Removed unused internal variables reported by static analysis.
- Added ignore coverage for `.claude/` and RoboSy temporary write-test files.

## Removed

- No user-facing features were removed.

## Breaking Changes

- Move and Copy no longer accept symbolic links, junctions, or other reparse points as source paths. Choose the real target path directly, or use Move + Symlink when managing a link.

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

- Review any workflow that previously selected a symlink or junction as the Move/Copy source. Use the real target path instead.
- If you installed the `RoboSy` command shim before this release and your project path contains non-ASCII characters, rerun `Install-RoboSyPath.ps1`.

## License and Attribution

RoboSy is released under the MIT License.

Copyright (c) 2026 Kiaro Sama

Anyone who copies, modifies, republishes, redistributes, or includes substantial parts of RoboSy must preserve the original copyright and MIT License notice.

- Original author: Kiaro Sama
- GitHub: https://github.com/KiaroSama
- Original repository: https://github.com/KiaroSama/RoboSy
