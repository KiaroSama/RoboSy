# RoboSy module: Logging.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Daily log file initialization and Write-Log.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

$script:LogInitialized = $false
$script:LogDirectory = $null
$script:LogFilePath = $null

function Initialize-LogPath {
    if ($script:LogInitialized) { return }
    $script:LogInitialized = $true

    $candidateDirs = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $scriptDir = Split-Path -Parent $PSCommandPath
        if (-not [string]::IsNullOrWhiteSpace($scriptDir)) {
            $candidateDirs.Add((Join-Path -Path $scriptDir -ChildPath "logs"))
        }
    }

    $localAppData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path -Path $HOME -ChildPath "AppData\Local"
    }

    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $candidateDirs.Add((Join-Path -Path $localAppData -ChildPath "RoboSy\logs"))
    }

    $date = (Get-Date).ToString("yyyy-MM-dd")

    foreach ($logDir in $candidateDirs) {
        try {
            if (-not (Test-Path -LiteralPath $logDir)) {
                New-RoboSyDirectory -Path $logDir | Out-Null
            }

            $probe = Join-Path -Path $logDir -ChildPath (".robosy-write-test-{0}.tmp" -f $PID)
            Set-Content -LiteralPath $probe -Value "test" -Encoding UTF8 -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue

            $script:LogDirectory = $logDir
            $script:LogFilePath = Join-Path -Path $logDir -ChildPath ("robosy-{0}.log" -f $date)
            return
        }
        catch {
            continue
        }
    }
}

function Write-Log {
    param(
        [string]$Level = "INFO",
        [AllowNull()][string]$Message
    )

    if (-not $script:LogInitialized) {
        Initialize-LogPath
    }

    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) { return }
    if ($null -eq $Message) { $Message = "" }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "{0} [{1}] {2}" -f $timestamp, $Level.ToUpper(), $Message

    try {
        Add-Content -LiteralPath $script:LogFilePath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging never breaks the user-facing flow.
    }
}
