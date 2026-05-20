@echo off
rem SPDX-License-Identifier: MIT
rem Copyright (c) 2026 Kiaro Sama
setlocal

set "ROBOSY_SCRIPT=%~dp0RoboSy.ps1"

if not exist "%ROBOSY_SCRIPT%" (
    echo RoboSy.ps1 was not found next to this launcher.
    pause
    exit /b 1
)

rem Prefer PowerShell 7+ when available, otherwise fall back to Windows PowerShell.
set "PS_EXE=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS_EXE=pwsh.exe"

"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $script=$env:ROBOSY_SCRIPT; $workdir=Split-Path -Parent $script; $shell=(Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue).Source; if([string]::IsNullOrWhiteSpace($shell)){ $shell=(Get-Command powershell.exe -CommandType Application).Source }; $q={ param([string]$v) ([char]34 + ($v -replace [char]34, ('\' + [char]34)) + [char]34) }; $runArgs='new-tab --title ' + (& $q 'RoboSy') + ' --startingDirectory ' + (& $q $workdir) + ' ' + (& $q $shell) + ' -NoProfile -ExecutionPolicy Bypass -File ' + (& $q $script); $candidates=@((Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue).Source,(Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'),'wt.exe') | Where-Object { $_ } | Select-Object -Unique; foreach($wt in $candidates){ try { Start-Process -FilePath $wt -ArgumentList $runArgs -WorkingDirectory $workdir -Verb RunAs -ErrorAction Stop; exit 0 } catch { continue } }; $fallbackArgs='-NoProfile -ExecutionPolicy Bypass -File ' + (& $q $script); Start-Process -FilePath $shell -ArgumentList $fallbackArgs -WorkingDirectory $workdir -Verb RunAs -ErrorAction Stop"

set "ROBOSY_EXIT=%errorlevel%"
if not "%ROBOSY_EXIT%"=="0" (
    echo.
    echo Failed to start RoboSy as Administrator. ^(exit code %ROBOSY_EXIT%^)
    echo If this keeps failing, open Windows Terminal as Administrator and run RoboSy.cmd manually.
    pause
)
endlocal & exit /b %ROBOSY_EXIT%
