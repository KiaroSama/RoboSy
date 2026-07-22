# RoboSy module: Elevation.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Administrator relaunch: Windows Terminal/pwsh discovery, argument building, and Invoke-AdminSwitch.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Convert-ToCommandLineArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-ApplicationPath {
    param([string]$Name)

    try {
        $command = Get-Command $Name -CommandType Application -ErrorAction Stop
        return $command.Source
    }
    catch {
        return $null
    }
}

function Get-PreferredPowerShellPath {
    $pwshPath = Get-ApplicationPath "pwsh.exe"
    if (-not [string]::IsNullOrWhiteSpace($pwshPath)) {
        return $pwshPath
    }

    return (Get-ApplicationPath "powershell.exe")
}

function Get-WindowsTerminalCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]

    $wtFromPath = Get-ApplicationPath "wt.exe"
    if (-not [string]::IsNullOrWhiteSpace($wtFromPath)) {
        $candidates.Add($wtFromPath)
    }

    $windowsAppsWt = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Microsoft\WindowsApps\wt.exe"
    if (Test-Path -LiteralPath $windowsAppsWt) {
        $candidates.Add($windowsAppsWt)
    }

    # Keep a blind wt.exe attempt for systems where App Execution Alias works
    # with Start-Process even when Get-Command cannot resolve it here.
    $candidates.Add("wt.exe")

    return @($candidates | Select-Object -Unique)
}

function Get-ScriptLaunchArguments {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Convert-ToCommandLineArgument $PSCommandPath)
    )

    foreach ($arg in $script:OriginalScriptArguments) {
        $argumentList += (Convert-ToCommandLineArgument $arg)
    }

    return $argumentList
}

function Test-RunningAsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-ScriptAsAdministrator {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return $false
    }

    $workingDirectory = Split-Path -Parent $PSCommandPath
    $shellPath = Get-PreferredPowerShellPath
    if ([string]::IsNullOrWhiteSpace($shellPath)) {
        return $false
    }

    $scriptArguments = Get-ScriptLaunchArguments
    $terminalArguments = @(
        "new-tab",
        "--title",
        (Convert-ToCommandLineArgument "RoboSy"),
        "--startingDirectory",
        (Convert-ToCommandLineArgument $workingDirectory),
        (Convert-ToCommandLineArgument $shellPath)
    ) + $scriptArguments

    foreach ($terminalPath in (Get-WindowsTerminalCandidates)) {
        try {
            Start-Process -FilePath $terminalPath -ArgumentList ($terminalArguments -join " ") -WorkingDirectory $workingDirectory -Verb RunAs -ErrorAction Stop
            return $true
        }
        catch {
            continue
        }
    }

    Start-Process -FilePath $shellPath -ArgumentList ($scriptArguments -join " ") -WorkingDirectory $workingDirectory -Verb RunAs -ErrorAction Stop
    return $true
}


function Invoke-AdminSwitch {
    param([string]$Reason = "Restarting RoboSy as Administrator...")

    if (Test-RunningAsAdministrator) {
        Write-Line "RoboSy is already running as Administrator." $script:UiColor.Warning
        Start-Sleep -Seconds 1
        return $false
    }

    if ($env:ROBOSY_SKIP_ELEVATION -eq "1") {
        Write-Line "Admin relaunch is disabled for this session." $script:UiColor.Warning
        return $false
    }

    Write-Line $Reason $script:UiColor.Warning

    try {
        $started = Restart-ScriptAsAdministrator
        if ($started) {
            exit
        }
    }
    catch {
        Write-Line "Failed to restart as Administrator." $script:UiColor.Error
        Write-Line $_.Exception.Message $script:UiColor.Error
        Write-Line "Open Windows Terminal as Administrator and run RoboSy manually." $script:UiColor.Warning
        Start-Sleep -Seconds 2
        return $false
    }

    Write-Line "Unable to locate the current script path for elevation." $script:UiColor.Error
    Start-Sleep -Seconds 2
    return $false
}
