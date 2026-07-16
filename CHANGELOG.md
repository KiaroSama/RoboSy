# Changelog

## Unreleased

### Fixed

- Fixed Move and Copy for folder sources so the selected folder is transferred as a folder and keeps its own name at the destination, instead of flattening its contents into the selected destination path. A destination that already ends with the source folder's name is reused instead of doubling the name (for example, no more `...\Docs\Docs`). Single-file Move and Copy are unaffected and keep the original file name.
- Fixed `Invoke-RobocopyCommand` and `Invoke-CmdDeleteCommand` so they return exactly one integer exit code. Native command output was previously captured into the same pipeline as the exit code, which could make a log entry read as `exitCode=System.Object[]` instead of a number such as `3`.
- Fixed Move + Symlink so an existing symbolic link or junction at the original path is no longer removed during preview/validation. It is now removed only after the final confirmation, immediately before the replacement link is created, so cancelling leaves the existing link untouched.
- Updated the README to describe the existing Move + Symlink behavior for a same-name existing target folder (merge instead of stop), matching the current code instead of the previously stale description.

### Added

- Move and Copy now show the effective final destination path (and, on collision, what already exists there) in the review screen, command preview, breadcrumbs, and logs before asking for confirmation.
- Move and Copy now block drive roots, share roots, and protected system/profile roots as sources, matching the existing Fast Delete guard.
- Added `tests/RoboSy.Tests.ps1`, a non-interactive regression test suite covering destination resolution, robocopy argument building, native-command return values, and symlink replacement safety.

## v1.2.0 - 2026-06-24

### Changed

- Path prompts no longer auto-accept dragged or pasted paths. Every source, destination, and target path must now be confirmed with Enter so you stay in control of each step.
- Move, Copy, Fast Delete, and Move + Symlink jobs now show a final summary and ask for an explicit confirmation before they run.
- Completed selections (mode, source, destination/target) now stay visible in a "Selections so far" block instead of being cleared on each screen redraw.
- The terminal is no longer cleared on every step; each step is appended below the previous output. The title banner and separator line are shown only once at startup.
- Prompt description lines are now shown as parenthesized hints in a yellow color.
- Recolored the navigation prompt: orange `back=0`, blue `quit`, lime-green `Run as admin`, bright-green default option markers such as `[1]`, and uncolored braces.

### Added

- Added `PSScriptAnalyzerSettings.psd1` and a `Lint` GitHub Actions workflow that parses and analyzes all PowerShell files on push and pull request.
- Added GitHub community files: `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates, a Dependabot configuration, and `.editorconfig`.
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
