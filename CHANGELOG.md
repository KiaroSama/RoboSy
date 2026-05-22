# Changelog

## [Unreleased]

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
