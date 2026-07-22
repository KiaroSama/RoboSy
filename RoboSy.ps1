# RoboSy Script
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Interactive helper for common Windows file relocation tasks.
#
# Options:
#   1. Move  - Default option. Press Enter on the main menu to choose it.
#   2. Copy  - Copy a file or folder with robocopy.
#   3. Fast Delete - Permanently delete a file or folder with robocopy purge.
#   4. Move + Symlink - Create a symbolic link at the original path.
#              If the original path already contains a real file/folder and
#              the target path does not exist, the item is moved to the target
#              path with robocopy first, then a symbolic link is created at the
#              original path.
#   5. Symlink Only - Create a symbolic link only; nothing is ever moved.
#              Order does not matter: whichever of the two paths holds the real
#              file/folder becomes the link target, and the other (missing) path
#              becomes the link. Refuses to run if both paths hold real items or
#              if neither does.
#
# Navigation:
#   - Type "exit" at any prompt to quit.
#   - Type "0" at path prompts to go back one step.
#
# Drag and drop:
#   - You can type a path normally.
#   - You can drag/drop an existing file or folder into the console.
#   - After typing, pasting, or dropping a path, press Enter to confirm it.
#     RoboSy never auto-accepts a path; you stay in control of every step.
#   - Each job also asks for a final confirmation before it runs.
#   - Windows blocks drag/drop from normal Explorer windows into elevated
#     Administrator terminals. Run RoboSy normally when you need drag/drop.
#
# Robocopy notes:
#   - Exit codes 0 through 7 are success or non-critical warnings.
#   - Exit codes 8 and above mean at least one failure occurred.
#
# Elevation:
#   - RoboSy runs non-elevated by default so Explorer drag/drop works.
#   - Use RoboSy Admin.cmd only when you intentionally need an Administrator
#     session for file symbolic links or protected paths.

$ErrorActionPreference = "Stop"
$script:OriginalScriptArguments = @($args)


# Split by responsibility into lib/*.ps1 (see .ai/REFERENCE.md); every function
# and script-scoped variable is defined by the time this line finishes running.
$script:RoboSyLibDir = Join-Path -Path (Split-Path -Parent $PSCommandPath) -ChildPath "lib"
foreach ($module in @(
        "Elevation.ps1",
        "Logging.ps1",
        "Console-UI.ps1",
        "Input.ps1",
        "Path-Helpers.ps1",
        "Robocopy-Core.ps1",
        "Standard-Jobs.ps1",
        "Link-Management.ps1",
        "Menu-Prompts.ps1"
    )) {
    . (Join-Path -Path $script:RoboSyLibDir -ChildPath $module)
}

if ($env:ROBOSY_FORCE_ELEVATION -eq "1" -and $env:ROBOSY_SKIP_ELEVATION -ne "1" -and -not (Test-RunningAsAdministrator)) {
    Write-Host "Restarting RoboSy as Administrator..." -ForegroundColor Yellow

    try {
        $started = Restart-ScriptAsAdministrator
        if ($started) {
            exit
        }
    }
    catch {
        Write-Host "Failed to restart as Administrator." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Open Windows Terminal as Administrator and run this script manually." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Host "Unable to locate the current script path for elevation." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Test hook: dot-sourcing this script with ROBOSY_LIB_ONLY=1 loads the helper
# functions without starting the interactive menu. Used by tests\RoboSy.Tests.ps1.
if ($env:ROBOSY_LIB_ONLY -eq "1") { return }

Initialize-LogPath
Write-Log "INFO" ("RoboSy session started. PSVersion={0}, PID={1}, Admin={2}" -f $PSVersionTable.PSVersion, $PID, (Test-RunningAsAdministrator))

:MainMenu while ($true) {
    $mode = Read-MainChoice

    if ($mode -eq "EXIT") {
        Write-Log "INFO" "Mode selected: EXIT"
        break MainMenu
    }

    Write-Log "INFO" ("Mode selected: {0}" -f $mode)

    :SourcePrompt while ($true) {
        $sourceInfo = Read-SourcePath -Mode $mode

        if ($sourceInfo.Action -eq "EXIT") {
            exit
        }

        if ($sourceInfo.Action -eq "BACK") {
            continue MainMenu
        }

        if ($mode -eq "DELETE") {
            $result = Invoke-FastDeleteJob -DeleteInfo $sourceInfo

            if ($result -eq "EXIT") {
                exit
            }

            if ($result -eq "BACK") {
                continue SourcePrompt
            }

            continue MainMenu
        }

        :DestinationPrompt while ($true) {
            $destInfo = Read-DestinationPath -Mode $mode -SourceInfo $sourceInfo

            if ($destInfo.Action -eq "EXIT") {
                exit
            }

            if ($destInfo.Action -eq "BACK") {
                break DestinationPrompt
            }

            if ($mode -eq "LINK") {
                $result = Invoke-MoveAndLinkJob -SourceInfo $sourceInfo -TargetInputInfo $destInfo
            }
            elseif ($mode -eq "SYMONLY") {
                $result = Invoke-SymlinkOnlyJob -FirstInfo $sourceInfo -SecondInfo $destInfo
            }
            else {
                $result = Invoke-RobocopyJob -Mode $mode -SourceInfo $sourceInfo -DestinationInfo $destInfo
            }

            if ($result -eq "EXIT") {
                exit
            }

            if ($result -eq "BACK") {
                continue DestinationPrompt
            }

            # Pressing Enter after a completed job returns to the main menu.
            continue MainMenu
        }
    }
}

Write-Blank
Write-Line "Goodbye." $script:UiColor.Accent
Write-Log "INFO" "RoboSy session ended."
Start-Sleep -Milliseconds 500
