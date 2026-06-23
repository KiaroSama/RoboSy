# Changelog

## v1.2.0 - 2026-06-24

### Changed

- Path prompts no longer auto-accept dragged or pasted paths. Every source, destination, and target path must now be confirmed with Enter so you stay in control of each step.
- Move, Copy, Fast Delete, and Move + Symlink jobs now show a final summary and ask for an explicit confirmation before they run.
- Completed selections (mode, source, destination/target) now stay visible in a "Selections so far" block at the top of every step instead of being cleared on each screen redraw.

### Added

- Added `PSScriptAnalyzerSettings.psd1` and a `Lint` GitHub Actions workflow that parses and analyzes all PowerShell files on push and pull request.
- Expanded `.gitignore` to protect local-only and assistant paths (`.ignoreme`, `.kiro/`, `.codex/`, `secrets.md`, `explain-AI.md`).

### Removed

- Removed the idle-based drag/drop auto-accept input path and its now-unused helper.

## v1.1.0 - 2026-05-23

### Added

- Added changelog tracking for future releases.

### Changed

- Move and Copy now reject symbolic links, junctions, and other reparse-point paths as sources to avoid following source links.
- Directory Move now attempts to remove an empty source folder if `robocopy` leaves the source root behind.
- Move + Symlink now treats empty-source cleanup failure as fatal because the original link path cannot be created while the real folder remains.
- Source and destination prompts now pass drag-and-drop auto-accept through to the console input reader.
- The installer now writes the command shim with OEM encoding when available, with a fallback for older PowerShell versions.
- The normal launcher now pauses when `RoboSy.ps1` is missing.

### Fixed

- Fixed Move/Copy behavior for symlink and junction sources so `robocopy` cannot silently move or copy the real target contents.
- Fixed Move + Symlink file relocation so an existing rename target is detected before link creation.
- Fixed path creation for directories, symbolic links, and junctions when paths contain wildcard characters such as `[` and `]`.
- Fixed the file-looking destination warning so it also applies when the source is a directory.
- Removed unused internal variables reported by static analysis.
- Added ignore coverage for `.claude/` and RoboSy temporary write-test files.

### Security

- Hardened destructive Move/Copy safety by rejecting reparse-point sources before invoking `robocopy`.
