# RoboSy module: Robocopy-Core.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Native robocopy/cmd.exe command wrappers and exit-code descriptions.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Get-RobocopyExitDescription {
    param([int]$Code)

    switch ($Code) {
        0 { return "No files were copied. Source and destination were already in sync." }
        1 { return "Files were copied successfully." }
        2 { return "Extra files or folders exist at the destination. No copy failures." }
        3 { return "Files were copied, and extra destination items were detected." }
        4 { return "Mismatched files or folders were detected. No copy failures." }
        5 { return "Files were copied, and mismatched items were detected." }
        6 { return "Extra and mismatched destination items were detected. No copy failures." }
        7 { return "Files were copied, with extra or mismatched destination items. No copy failures." }
        default {
            if ($Code -ge 8) {
                return "At least one copy or move failure occurred."
            }

            return "Robocopy returned an unusual exit code."
        }
    }
}

# Wraps [Console]::IsInputRedirected in a function so tests can force the
# non-redirected branch of Read-ConsoleText without a real, piped-free
# terminal session.

function Assert-RobocopyAvailable {
    $robocopyCommand = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($null -eq $robocopyCommand) {
        Write-Line "robocopy.exe was not found on PATH." $script:UiColor.Error
        Write-Line "Robocopy is normally included with Windows. Check the system PATH or run this from a standard Windows shell." $script:UiColor.Muted
        return $false
    }

    return $true
}

function Get-CommonRobocopyArgs {
    return @(
        "/COPY:DAT",
        "/DCOPY:DAT",
        "/R:3",
        "/W:5",
        "/MT:16",
        "/TEE",
        "/ETA",
        "/XJ"
    )
}

function Get-RobocopyCommandText {
    param([string[]]$Arguments)

    return "robocopy " + (($Arguments | ForEach-Object { Format-PowerShellArgument $_ }) -join " ")
}

function Invoke-RobocopyCommand {
    param(
        [string[]]$Arguments,
        [switch]$PreviewShown
    )

    $commandPreview = Get-RobocopyCommandText -Arguments $Arguments

    if (-not $PreviewShown) {
        Write-CommandPreview $commandPreview
    }

    Write-Log "INFO" ("Robocopy command: {0}" -f $commandPreview)

    # Out-Host keeps robocopy's live output visible while keeping it out of the
    # success pipeline. Without it the native output is returned to the caller
    # together with the exit code, and "$code = Invoke-RobocopyCommand ..." gets
    # an Object[] instead of an integer.
    & robocopy @Arguments | Out-Host
    $code = [int]$LASTEXITCODE
    $description = Get-RobocopyExitDescription $code

    Write-Blank
    if ($code -le 7) {
        Write-Line ("Robocopy finished. Exit code: {0}" -f $code) $script:UiColor.Success
        Write-Line $description $script:UiColor.Muted
        Write-Log "INFO" ("Robocopy exit code {0}: {1}" -f $code, $description)
    }
    else {
        Write-Line ("Robocopy failed. Exit code: {0}" -f $code) $script:UiColor.Error
        Write-Line $description $script:UiColor.Muted
        Write-Log "ERROR" ("Robocopy exit code {0}: {1}" -f $code, $description)

        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "Robocopy failure can be caused by missing Administrator permission." $script:UiColor.Warning
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
        }
    }

    # Callers compare this against 7, so it must stay a single integer.
    return $code
}


function Assert-CmdAvailable {
    $cmdCommand = Get-Command cmd.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $cmdCommand) {
        Write-Line "cmd.exe was not found on PATH." $script:UiColor.Error
        Write-Line "Fast Delete uses cmd.exe for file deletion and final cleanup after robocopy purge." $script:UiColor.Muted
        return $false
    }

    return $true
}

function Format-CmdPathArgument {
    param([string]$Path)

    return ('"{0}"' -f ($Path -replace '"', '""'))
}


function New-RobocopyEmptySourceDirectory {
    param([string]$TargetPath)

    if (-not $script:LogInitialized) {
        Initialize-LogPath
    }

    $candidateRoots = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @([System.IO.Path]::GetTempPath(), $env:TEMP, $env:TMP, $script:LogDirectory)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidateRoots.Add($candidate)
        }
    }

    foreach ($candidateRoot in @($candidateRoots | Select-Object -Unique)) {
        try {
            $rootPath = Get-FullPathSafe $candidateRoot
            if ([string]::IsNullOrWhiteSpace($rootPath)) {
                continue
            }

            if (-not (Test-Path -LiteralPath $rootPath)) {
                New-RoboSyDirectory -Path $rootPath | Out-Null
            }

            $emptySource = Join-Path -Path $rootPath -ChildPath (".robosy-empty-delete-{0}" -f ([Guid]::NewGuid().ToString("N")))
            $emptySourceFullPath = Get-FullPathSafe $emptySource
            if ([string]::IsNullOrWhiteSpace($emptySourceFullPath)) {
                continue
            }

            if (Test-IsSameOrChildPath -Parent $TargetPath -Child $emptySourceFullPath) {
                continue
            }

            New-RoboSyDirectory -Path $emptySourceFullPath | Out-Null
            return $emptySourceFullPath
        }
        catch {
            Write-Log "WARN" ("Could not create robocopy empty source under {0}: {1}" -f $candidateRoot, $_.Exception.Message)
            continue
        }
    }

    return $null
}


function Invoke-CmdDeleteCommand {
    param(
        [string]$CommandText,
        [switch]$PreviewShown
    )

    $commandPreview = "cmd.exe /d /c " + $CommandText

    if (-not $PreviewShown) {
        Write-CommandPreview $commandPreview
    }

    Write-Log "INFO" ("Fast delete command: {0}" -f $commandPreview)

    # See Invoke-RobocopyCommand: Out-Host keeps the command output visible
    # without letting it become part of this function's return value.
    & cmd.exe /d /c $CommandText | Out-Host
    $code = [int]$LASTEXITCODE

    Write-Blank
    if ($code -eq 0) {
        Write-Line ("Fast delete command finished. Exit code: {0}" -f $code) $script:UiColor.Success
        Write-Log "INFO" ("Fast delete command exit code {0}" -f $code)
    }
    else {
        Write-Line ("Fast delete command failed. Exit code: {0}" -f $code) $script:UiColor.Error
        Write-Log "ERROR" ("Fast delete command exit code {0}" -f $code)

        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "Delete failure can be caused by missing Administrator permission or locked files." $script:UiColor.Warning
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
        }
    }

    # Callers compare this against 0, so it must stay a single integer.
    return $code
}

function Invoke-RobocopyPurgeDirectoryDelete {
    param(
        [string]$TargetPath,
        [switch]$PreviewShown
    )

    if (-not (Assert-RobocopyAvailable)) {
        return 16
    }

    if (-not (Assert-CmdAvailable)) {
        return 16
    }

    $emptySource = New-RobocopyEmptySourceDirectory -TargetPath $TargetPath
    if ([string]::IsNullOrWhiteSpace($emptySource)) {
        Write-Line "Could not create an empty source folder for robocopy purge." $script:UiColor.Error
        Write-Log "ERROR" ("Could not create robocopy purge empty source for target: {0}" -f $TargetPath)
        return 16
    }

    try {
        Write-Hint "Robocopy purges everything inside the selected folder, then RoboSy deletes the selected folder itself."
        Write-Blank

        $robocopyArgs = @(
            $emptySource,
            $TargetPath,
            "/MIR",
            "/MT:32",
            "/R:0",
            "/W:0",
            "/XJ",
            "/NFL",
            "/NDL",
            "/NJH",
            "/NJS",
            "/NP"
        )

        $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown:$PreviewShown
        if ($code -gt 7) {
            return $code
        }

        if (Test-Path -LiteralPath $TargetPath) {
            $quotedPath = Format-CmdPathArgument $TargetPath
            $cleanupCode = Invoke-CmdDeleteCommand -CommandText "rmdir /s /q $quotedPath" -PreviewShown:$PreviewShown
            if ($cleanupCode -ne 0) {
                return $cleanupCode
            }
        }

        return 0
    }
    finally {
        if (Test-Path -LiteralPath $emptySource) {
            Remove-Item -LiteralPath $emptySource -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
