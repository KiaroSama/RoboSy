# RoboSy module: Menu-Prompts.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Main menu choice and the source/destination path prompts.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Read-MainChoice {
    while ($true) {
        Reset-Breadcrumb
        Show-Header
        Write-MenuOption "1" "Move" "Move a folder tree or a single file with robocopy." Magenta -Default -AnsiColor ("{0}[38;2;210;170;255m" -f [char]27)
        Write-MenuOption "2" "Copy" "Copy a folder tree or a single file with robocopy." Green
        Write-MenuOption "3" "Fast Delete" "Permanently delete a file or folder with robocopy purge; no Recycle Bin." Red
        Write-MenuOption "4" "Move + Symlink" "Move the real item to a target path, then leave a link at the original path." Cyan
        Write-MenuOption "5" "Symlink Only" "Only create a symbolic link; nothing is moved. Order of the two paths does not matter." Cyan -AnsiColor ("{0}[38;5;117m" -f [char]27)
        Write-Blank

        $choice = Read-ConsoleText "Choose Option [1]"

        if (Test-ExitInput $choice) {
            return "EXIT"
        }

        if (Test-BackInput $choice) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($choice)) {
            return "MOVE"
        }

        switch ($choice.Trim()) {
            "1" { return "MOVE" }
            "2" { return "COPY" }
            "3" { return "DELETE" }
            "4" { return "LINK" }
            "5" { return "SYMONLY" }
            default {
                Write-Blank
                Write-Line "Invalid option. Choose 1, 2, 3, 4, 5, or press Enter for 1." $script:UiColor.Error
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Read-SourcePath {
    param([string]$Mode)

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent)
    )

    while ($true) {
        Show-Header

        switch ($Mode) {
            "LINK" {
                Write-Line "Enter the original path where the link should exist." $script:UiColor.Text
                Write-Hint "If this path currently contains a real file/folder, it can be moved to the target path first."
                Write-Hint "If this path does not exist, the script will create only the link after you enter an existing target."
            }
            "SYMONLY" {
                Write-Line "Enter the first path. Nothing is ever moved or deleted." $script:UiColor.Text
                Write-Hint "If only one path is a real file/folder, order does not matter - the real side is the link target."
                Write-Hint "If BOTH paths exist, Path 1 is the real source and the link is created inside Path 2 (which must be a folder)."
            }
            "DELETE" {
                Write-Line "Enter the existing file or folder to permanently delete." $script:UiColor.Text
                Write-Hint "This bypasses the Recycle Bin and uses robocopy purge for faster folder deletion."
            }
            default {
                Write-Line "Enter the existing source path." $script:UiColor.Text
                Write-Hint "The source can be a folder or one single file."
            }
        }

        Write-Hint "Type, paste, or drag/drop a path, then press Enter to confirm."
        Write-Blank

        $prompt = switch ($Mode) {
            "DELETE" { "Delete path" }
            "SYMONLY" { "Path 1 (real source if both exist)" }
            default { "Source" }
        }
        $inputPath = Read-ConsoleText $prompt
        if (Test-ExitInput $inputPath) { return @{ Action = "EXIT" } }
        if (Test-BackInput $inputPath) { return @{ Action = "BACK" } }

        $normalizedInputPath = Normalize-UserPath $inputPath
        Write-Log "INFO" ("Source path received: raw={0}; normalized={1}; mode={2}" -f $inputPath, $normalizedInputPath, $Mode)

        $allowMissing = ($Mode -eq "LINK" -or $Mode -eq "SYMONLY")
        $sourceInfo = Get-PathInfo -InputPath $inputPath -AllowMissing:$allowMissing
        if ($null -ne $sourceInfo) {
            Write-PathStatusLog "Source path normalized" $sourceInfo
        }

        if ($null -eq $sourceInfo) {
            Write-Blank
            if ($Mode -eq "LINK") {
                Write-Line "Source/link path is invalid." $script:UiColor.Error
            }
            elseif ($Mode -eq "SYMONLY") {
                Write-Line "First path is invalid." $script:UiColor.Error
            }
            elseif ($Mode -eq "DELETE") {
                Write-Line "Delete path does not exist." $script:UiColor.Error
            }
            else {
                Write-Line "Source path does not exist." $script:UiColor.Error
            }
            Start-Sleep -Seconds 1
            continue
        }

        if ($Mode -eq "MOVE" -or $Mode -eq "COPY") {
            $protectedReason = Get-ProtectedRootReason $sourceInfo.Path
            if (-not [string]::IsNullOrWhiteSpace($protectedReason)) {
                Write-Blank
                Write-Line "Move/Copy source cannot be a drive root, share root, or protected system/profile root." $script:UiColor.Error
                Write-Line $protectedReason $script:UiColor.Warning
                Write-Line "Choose a specific folder or file inside it instead." $script:UiColor.Muted
                Write-Log "ERROR" ("Move/Copy source rejected as a protected root: {0}; reason={1}" -f $sourceInfo.Path, $protectedReason)
                Start-Sleep -Seconds 3
                continue
            }
        }

        if (($Mode -eq "MOVE" -or $Mode -eq "COPY") -and $sourceInfo.IsReparsePoint) {
            Write-Blank
            Write-Line "Move/Copy source cannot be a symbolic link, junction, or other reparse point." $script:UiColor.Error
            Write-Line "Robocopy can follow a source link and move/copy the real target's contents instead." $script:UiColor.Warning
            if (-not [string]::IsNullOrWhiteSpace($sourceInfo.LinkTarget)) {
                Write-Line ("Detected link target: {0}" -f $sourceInfo.LinkTarget) $script:UiColor.Muted
            }
            Write-Line "Choose the real target path directly, or use Move + Symlink when you want to manage a link." $script:UiColor.Muted
            Write-Log "ERROR" ("Move/Copy source rejected because it is a reparse point: {0}" -f (Format-PathStatusForLog $sourceInfo))
            Start-Sleep -Seconds 3
            continue
        }

        $sourceInfo.Action = "OK"
        return $sourceInfo
    }
}

function Read-DestinationPath {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo
    )

    $sourceLabel = switch ($Mode) {
        "LINK" { "Original/link" }
        "SYMONLY" { "Path 1" }
        default { "Source" }
    }
    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent),
        (New-BreadcrumbStep $sourceLabel $SourceInfo.Path $script:UiColor.Path)
    )

    while ($true) {
        Show-Header

        if ($Mode -eq "SYMONLY") {
            Write-Line "Enter the second path. Nothing is ever moved or deleted." $script:UiColor.Text
            Write-Hint "If only Path 1 is real, this is where the link is created (order does not matter)."
            Write-Hint "If both paths exist, the link is created INSIDE this folder as <Path 2>\<Path 1 name> -> Path 1."
            Write-Hint "If neither path is a real file/folder, RoboSy stops without changing anything."
        }
        elseif ($Mode -eq "LINK") {
            Write-Line "Enter the real target path." $script:UiColor.Text
            Write-Hint "If the original path exists and this target path is missing, the original item is moved here first."
            Write-Hint "If the original path is missing, this target path must already exist."
            Write-Hint "If you enter an existing folder while moving an existing item, the item is moved inside it with the same name."
        }
        else {
            Write-Line "Enter the destination folder path." $script:UiColor.Text
            Write-Hint "This is the folder the selected item is transferred into."
            Write-Hint "If the destination folder does not exist, robocopy will create it."

            if ($SourceInfo.Type -eq "Directory") {
                Write-Hint ("The selected folder is transferred as a folder, so it becomes <destination>\{0}." -f $SourceInfo.Name)
                Write-Hint ("A destination that already ends with '{0}' is used as the final folder instead." -f $SourceInfo.Name)
            }
            else {
                Write-Hint ("The original file name is kept, so the file becomes <destination>\{0}." -f $SourceInfo.Name)
            }
        }

        Write-Blank
        $destPrompt = if ($Mode -eq "SYMONLY") { "Path 2 (link location; a folder if both exist)" } else { "Destination/target" }
        $inputPath = Read-ConsoleText $destPrompt
        if (Test-ExitInput $inputPath) { return @{ Action = "EXIT" } }
        if (Test-BackInput $inputPath) { return @{ Action = "BACK" } }

        $normalizedInputPath = Normalize-UserPath $inputPath
        Write-Log "INFO" ("Destination/target path received: raw={0}; normalized={1}; mode={2}" -f $inputPath, $normalizedInputPath, $Mode)

        $destInfo = Get-PathInfo -InputPath $inputPath -AllowMissing
        if ($null -ne $destInfo) {
            Write-PathStatusLog "Destination/target path normalized" $destInfo
        }

        if ($null -eq $destInfo) {
            Write-Blank
            Write-Line "Destination path is invalid." $script:UiColor.Error
            Start-Sleep -Seconds 1
            continue
        }

        if ($Mode -ne "LINK" -and $Mode -ne "SYMONLY") {
            if ($destInfo.Exists -and $destInfo.Type -ne "Directory") {
                Write-Blank
                Write-Line "Destination must be a folder path, but this path is an existing file." $script:UiColor.Error
                Start-Sleep -Seconds 2
                continue
            }

            $rejectReason = Get-StandardDestinationRejectReason -SourceInfo $SourceInfo -DestinationPath $destInfo.Path
            if (-not [string]::IsNullOrWhiteSpace($rejectReason)) {
                Write-Blank
                Write-Line $rejectReason $script:UiColor.Error
                Write-Line "That can cause recursive copies or destructive move behavior." $script:UiColor.Warning
                Write-Log "ERROR" ("Destination rejected: {0}; source={1}; destinationInput={2}" -f $rejectReason, $SourceInfo.Path, $destInfo.Path)
                Start-Sleep -Seconds 3
                continue
            }

            if (-not $destInfo.Exists) {
                $leaf = [System.IO.Path]::GetFileName($destInfo.Path.TrimEnd([char[]]@('\', '/')))
                $extension = [System.IO.Path]::GetExtension($leaf)

                if (-not [string]::IsNullOrWhiteSpace($extension)) {
                    Write-Blank
                    Write-Line "This destination looks like a file name:" $script:UiColor.Warning
                    Write-Line ("  {0}" -f $destInfo.Path) $script:UiColor.Path
                    Write-Line "Robocopy will treat it as a destination folder path, not as an output file or archive." $script:UiColor.Muted
                    $useAnyway = Read-YesNo "Use this as a destination folder anyway" $true

                    if ($useAnyway -is [string] -and $useAnyway -eq "EXIT") { return @{ Action = "EXIT" } }
                    if ($useAnyway -is [string] -and $useAnyway -eq "BACK") { continue }
                    if (-not $useAnyway) { continue }
                }
            }
        }

        $destInfo.Action = "OK"
        return $destInfo
    }
}
