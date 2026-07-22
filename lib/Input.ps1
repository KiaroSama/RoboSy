# RoboSy module: Input.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Navigation-keyword checks and the redirected/non-redirected console input pipeline (Read-ConsoleText, Read-HostUiLine, Read-YesNo).
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Test-ExitInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }

    $trimmed = $Text.Trim()
    return ($trimmed.Equals("exit", [StringComparison]::OrdinalIgnoreCase) -or $trimmed.Equals("quit", [StringComparison]::OrdinalIgnoreCase))
}

function Test-BackInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }
    return ($Text.Trim() -eq "0")
}

function Test-AdminInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }
    return $Text.Trim().Equals("admin", [StringComparison]::OrdinalIgnoreCase)
}


function Test-ConsoleInputIsRedirected {
    return [Console]::IsInputRedirected
}

# The last-resort line reader when the active host has no usable UI. Kept as
# its own function (instead of calling [Console]::ReadLine() inline) purely so
# tests can replace it and avoid ever blocking on a real console.
function Read-ConsoleFallbackLine {
    return [Console]::ReadLine()
}

# Delegates line editing to the active PowerShell host instead of a
# hand-rolled key-processing loop. PSHostUserInterface.ReadLine() guarantees
# line input, but exact editing behavior (backspace, arrow keys, Escape,
# history, Ctrl+C) is host-defined and can vary between ConsoleHost, Windows
# Terminal, PowerShell 5.1, PowerShell 7+, and other hosts. $HostUi defaults
# to the real $Host.UI in production; tests inject a fake UI object to
# exercise the fallback paths deterministically, since $Host itself is
# read-only and cannot be replaced. A host with no usable UI, or whose
# ReadLine() throws NotImplementedException, falls back to
# Read-ConsoleFallbackLine. Any other exception (including cancellation) is
# never caught here.
function Read-HostUiLine {
    param($HostUi = $Host.UI)

    if ($null -ne $HostUi) {
        try {
            return $HostUi.ReadLine()
        }
        catch [System.NotImplementedException] {
            # Fall through to the console fallback below.
        }
    }

    return Read-ConsoleFallbackLine
}

function Read-ConsoleText {
    param(
        [string]$Prompt,
        [switch]$HideNavigation
    )

    $displayPrompt = Format-ConsolePromptText -Prompt $Prompt -HideNavigation:$HideNavigation

    if (Test-ConsoleInputIsRedirected) {
        $redirectedInput = Read-Host $displayPrompt
        if (Test-AdminInput $redirectedInput) {
            $null = Invoke-AdminSwitch
            return "0"
        }

        return $redirectedInput
    }

    while ($true) {
        Write-ConsolePrompt -Prompt $Prompt -HideNavigation:$HideNavigation
        $inputText = Read-HostUiLine

        if (Test-AdminInput $inputText) {
            $null = Invoke-AdminSwitch
            continue
        }

        return $inputText
    }
}

function Read-ReturnToMenu {
    # Return to the main menu automatically without prompting. The screen is
    # never cleared, so the finished job output stays visible above the menu.
    return "MENU"
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultNo = $true
    )

    while ($true) {
        if ($DefaultNo) {
            $suffix = " [y/N]"
        }
        else {
            $suffix = " [Y/n]"
        }

        $answer = Read-ConsoleText ($Prompt + $suffix)

        if (Test-ExitInput $answer) {
            return "EXIT"
        }

        if (Test-BackInput $answer) {
            return "BACK"
        }

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return (-not $DefaultNo)
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default {
                Write-Line "Please answer y or n. Type exit to quit." $script:UiColor.Error
            }
        }
    }
}
