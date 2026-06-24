# Contributing to RoboSy

Thanks for your interest in improving RoboSy. This is a single-file, interactive
PowerShell tool for Windows, so contributions are kept simple and focused.

## Ways to contribute

- Report bugs and unexpected behavior.
- Suggest new features or improvements.
- Improve documentation.
- Submit pull requests with fixes or enhancements.

## Before you start

- RoboSy targets Windows with PowerShell 5.1 or PowerShell 7+.
- Core file-operations rely on the built-in `robocopy.exe`.
- Keep changes consistent with the existing console UI style, colors, and
  navigation conventions.
- All code, comments, and documentation are written in English.

## Development setup

```powershell
git clone https://github.com/KiaroSama/RoboSy.git
cd RoboSy
```

Run the tool directly while developing:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\RoboSy.ps1
```

## Linting

RoboSy is checked with [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)
using the rules in `PSScriptAnalyzerSettings.psd1`. The same checks run in CI
(`.github/workflows/lint.yml`).

Run them locally before opening a pull request:

```powershell
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

A clean run reports no issues. Also confirm the script still parses:

```powershell
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\RoboSy.ps1).Path, [ref]$tokens, [ref]$errors)
$errors
```

## Testing

RoboSy performs real file operations, so test on small, disposable folders only.
Verify the scenarios you changed (Move, Copy, Fast Delete, Move + Symlink),
including back navigation (`0`), cancel paths, and at least one failure case.

Do not commit runtime logs, secrets, or any local-only files. The repository
ignore rules already exclude `logs/`, secrets, and assistant directories.

## Pull requests

- Keep each pull request focused on one logical change.
- Update `README.md` and `CHANGELOG.md` when behavior changes.
- Use clear, descriptive English commit messages.
- Make sure the lint workflow passes.
