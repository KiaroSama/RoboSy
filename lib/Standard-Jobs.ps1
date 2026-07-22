# RoboSy module: Standard-Jobs.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Move/Copy destination resolution, final-path classification, Invoke-RobocopyJob, and Fast Delete.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Remove-EmptySourceDirectoryAfterMove {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        Write-Log "WARN" ("Source folder still has remaining items after move: {0}" -f $Path)
        return $false
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log "INFO" ("Removed empty source folder after move: {0}" -f $Path)
        return $true
    }
    catch {
        Write-Log "WARN" ("Could not remove empty source folder {0}: {1}" -f $Path, $_.Exception.Message)
        Write-Line ("Empty source folder could not be removed: {0}" -f $Path) $script:UiColor.Warning
        Write-Line $_.Exception.Message $script:UiColor.Muted
        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "This may be a permission issue." $script:UiColor.Warning
        }
        return $false
    }
}


# Standard Move/Copy transfer the selected item itself, not only its contents.
# A directory source therefore keeps its own leaf name at the destination:
# "E:\A\Docs" sent to "F:\B" becomes "F:\B\Docs", never "F:\B\<contents>".
# A destination whose leaf already equals the source folder name is treated as
# the final directory, so the same input can never produce "F:\B\Docs\Docs".
# A file source keeps its original file name inside the destination folder, so
# the destination folder itself is the effective destination.
# Move + Symlink keeps its own exact-target semantics in Resolve-LinkTargetPath.
function Resolve-EffectiveDestinationPath {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $destination = Normalize-PathForCompare $DestinationPath

    if ($SourceInfo.Type -ne "Directory") {
        return $destination
    }

    $destinationLeaf = Get-PathLeafForCompare $destination
    if (-not [string]::IsNullOrWhiteSpace($destinationLeaf) -and $destinationLeaf.Equals($SourceInfo.Name, [StringComparison]::OrdinalIgnoreCase)) {
        return $destination
    }

    return (Join-Path -Path $destination -ChildPath $SourceInfo.Name)
}

# The path of the transferred item once the job has run. For a directory source
# this is the effective destination itself; for a file source it is the file
# inside the effective destination folder.
function Resolve-StandardFinalItemPath {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    if ($SourceInfo.Type -eq "Directory") {
        return $effectiveDestination
    }

    return (Join-Path -Path $effectiveDestination -ChildPath $SourceInfo.Name)
}

# Validates the entered destination against the resolved effective destination
# rather than the raw input, so "E:\A\Docs" -> "E:\A" is caught as a same-path
# job instead of being handed to robocopy.
function Get-StandardDestinationRejectReason {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $finalItemPath = Resolve-StandardFinalItemPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath

    $sourceCompare = Normalize-PathForCompare $SourceInfo.Path
    $finalCompare = Normalize-PathForCompare $finalItemPath

    if ([string]::Equals($sourceCompare, $finalCompare, [StringComparison]::OrdinalIgnoreCase)) {
        return ("Source and destination resolve to the same path: {0}" -f $finalItemPath)
    }

    if ($SourceInfo.Type -eq "Directory" -and (Test-IsSameOrChildPath -Parent $SourceInfo.Path -Child $effectiveDestination)) {
        return "Destination cannot be the source folder or a folder inside the source."
    }

    return $null
}

function Get-NearestExistingAncestorStatus {
    param([AllowNull()][string]$Path)

    $current = Normalize-PathForCompare $Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            return (Get-PathStatus $current)
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($current, [StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }

        $current = $parent
    }

    return $null
}

# Centralizes what standard Move/Copy will actually do at the effective final
# path: fresh creation, safe reuse, an explicit merge/overwrite that needs
# confirmation, or a hard block (type conflict / unsupported reparse point).
# Both the review screen and the execution-time revalidation call this, so
# they can never disagree about what is about to happen. A reparse point
# anywhere in the write path is unsafe because robocopy writes through it -
# /XJ only excludes junctions encountered while recursing, it does not make a
# linked destination argument safe.
function Get-StandardFinalPathClassification {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $finalItemPath = Resolve-StandardFinalItemPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $destinationInputStatus = Get-PathStatus $DestinationPath
    $effectiveDestinationStatus = Get-PathStatus $effectiveDestination
    $finalStatus = Get-PathStatus $finalItemPath

    $result = @{
        EffectiveDestination = $effectiveDestination
        FinalItemPath        = $finalItemPath
        FinalStatus          = $finalStatus
        Classification       = $null
        BlockReason          = $null
        RequiresConfirmation = $false
        ExistingItemCount    = 0
    }

    foreach ($candidate in @($destinationInputStatus, $effectiveDestinationStatus, $finalStatus)) {
        if ($candidate.Exists -and $candidate.IsReparsePoint) {
            $result.Classification = "UnsupportedReparsePoint"
            $result.BlockReason = ("The destination path is a symbolic link, junction, or other reparse point: {0}" -f $candidate.Path)
            return $result
        }
    }

    $ancestorStatus = Get-NearestExistingAncestorStatus $effectiveDestination
    if ($null -ne $ancestorStatus -and $ancestorStatus.IsReparsePoint) {
        $result.Classification = "UnsupportedReparsePoint"
        $result.BlockReason = ("An existing parent folder in the destination path is a symbolic link, junction, or other reparse point: {0}" -f $ancestorStatus.Path)
        return $result
    }

    if (-not $finalStatus.Exists) {
        $result.Classification = if ($SourceInfo.Type -eq "Directory") { "CreateDirectory" } else { "CreateFile" }
        return $result
    }

    if ($SourceInfo.Type -eq "Directory") {
        if ($finalStatus.Type -ne "Directory") {
            $result.Classification = "TypeConflictDirectoryOntoFile"
            $result.BlockReason = ("A folder cannot be transferred onto an existing file: {0}" -f $finalItemPath)
            return $result
        }

        $result.ExistingItemCount = @(Get-ChildItem -LiteralPath $finalItemPath -Force -ErrorAction SilentlyContinue).Count
        if ($result.ExistingItemCount -eq 0) {
            $result.Classification = "ReuseEmptyDirectory"
        }
        else {
            $result.Classification = "MergeDirectory"
            $result.RequiresConfirmation = $true
        }

        return $result
    }

    if ($finalStatus.Type -eq "Directory") {
        $result.Classification = "TypeConflictFileOntoDirectory"
        $result.BlockReason = ("A file cannot overwrite an existing folder: {0}" -f $finalItemPath)
        return $result
    }

    $result.Classification = "OverwriteFile"
    $result.RequiresConfirmation = $true
    return $result
}

function Get-StandardRobocopyArgs {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo,
        [string]$EffectiveDestination
    )

    $commonArgs = Get-CommonRobocopyArgs

    if ($SourceInfo.Type -eq "Directory") {
        $robocopyArgs = @($SourceInfo.Path, $EffectiveDestination, "/E") + $commonArgs

        if ($Mode -eq "MOVE") {
            $robocopyArgs += "/MOVE"
        }

        return $robocopyArgs
    }

    $robocopyArgs = @($SourceInfo.Parent, $EffectiveDestination, $SourceInfo.Name) + $commonArgs

    if ($Mode -eq "MOVE") {
        $robocopyArgs += "/MOV"
    }

    return $robocopyArgs
}

function Invoke-RobocopyJob {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo,
        [hashtable]$DestinationInfo
    )

    $startedAt = Get-Date

    $classification = Get-StandardFinalPathClassification -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    $effectiveDestination = $classification.EffectiveDestination
    $finalItemPath = $classification.FinalItemPath

    $breadcrumbSteps = New-Object System.Collections.Generic.List[object]
    $breadcrumbSteps.Add((New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent))
    $breadcrumbSteps.Add((New-BreadcrumbStep "Source" $SourceInfo.Path $script:UiColor.Path))
    $breadcrumbSteps.Add((New-BreadcrumbStep "Destination" $DestinationInfo.Path $script:UiColor.Path))
    if (-not [string]::Equals((Normalize-PathForCompare $DestinationInfo.Path), (Normalize-PathForCompare $finalItemPath), [StringComparison]::OrdinalIgnoreCase)) {
        $breadcrumbSteps.Add((New-BreadcrumbStep "Final path" $finalItemPath $script:UiColor.Path))
    }
    Set-Breadcrumb $breadcrumbSteps.ToArray()

    Show-Header
    Write-Line "Review the job below before it runs." $script:UiColor.Accent
    Write-Blank

    if (-not (Assert-RobocopyAvailable)) {
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $rejectReason = Get-StandardDestinationRejectReason -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    if (-not [string]::IsNullOrWhiteSpace($rejectReason)) {
        Write-Line "Job stopped before anything was transferred." $script:UiColor.Error
        Write-Line $rejectReason $script:UiColor.Warning
        Write-Log "ERROR" ("Standard job blocked: {0}; source={1}; destinationInput={2}" -f $rejectReason, $SourceInfo.Path, $DestinationInfo.Path)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if (-not [string]::IsNullOrWhiteSpace($classification.BlockReason)) {
        Write-Line "Job stopped before anything was transferred." $script:UiColor.Error
        Write-Line $classification.BlockReason $script:UiColor.Warning
        Write-Log "ERROR" ("Standard job blocked by final-path classification: {0}; classification={1}; source={2}; destinationInput={3}" -f `
            $classification.BlockReason, $classification.Classification, $SourceInfo.Path, $DestinationInfo.Path)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $robocopyArgs = Get-StandardRobocopyArgs -Mode $Mode -SourceInfo $SourceInfo -EffectiveDestination $effectiveDestination
    $finalStatus = $classification.FinalStatus

    $finalPlan = switch ($classification.Classification) {
        "CreateDirectory"     { "Create (does not exist yet)" }
        "CreateFile"          { "Create (does not exist yet)" }
        "ReuseEmptyDirectory" { "Reuse (existing empty folder)" }
        "MergeDirectory"      { "Merge into an existing folder that already holds {0} item(s)" -f $classification.ExistingItemCount }
        "OverwriteFile"       { "Overwrite (an existing file is already at this path)" }
        default               { $classification.Classification }
    }

    $collisionMessage = switch ($classification.Classification) {
        "MergeDirectory" { "Existing files with the same names inside that folder will be overwritten. Unrelated files already there are kept." }
        "OverwriteFile"  { "The existing file at the final path will be overwritten." }
        default          { $null }
    }

    Write-LabelValue "Source type" $SourceInfo.Type $script:UiColor.Text
    Write-LabelValue "Final path" $finalItemPath $script:UiColor.Path
    Write-LabelValue "Final path plan" $finalPlan $script:UiColor.Text

    Write-PathStatusLog "Standard job source check" $SourceInfo
    Write-PathStatusLog "Standard job destination check" $DestinationInfo
    Write-PathStatusLog "Standard job final path check" $finalStatus
    Write-Log "INFO" ("Job start: mode={0}, sourceType={1}, source={2}, destinationInput={3}, effectiveDestination={4}, finalPath={5}, classification={6}" -f `
        $Mode, $SourceInfo.Type, $SourceInfo.Path, $DestinationInfo.Path, $effectiveDestination, $finalItemPath, $classification.Classification)

    if ($Mode -eq "MOVE") {
        Write-Hint "Move mode deletes source items after robocopy confirms they were copied."
    }

    Write-Blank
    Write-CommandPreview (Get-RobocopyCommandText -Arguments $robocopyArgs)

    if ($classification.RequiresConfirmation) {
        Write-Line "The final path already exists." $script:UiColor.Warning
        Write-Line $collisionMessage $script:UiColor.Muted
        Write-Blank

        $collisionConfirm = Read-YesNo ("Continue into the existing path {0}" -f $finalItemPath) $true
        if ($collisionConfirm -is [string] -and $collisionConfirm -eq "EXIT") { return "EXIT" }
        if ($collisionConfirm -is [string] -and $collisionConfirm -eq "BACK") { return "BACK" }
        if (-not $collisionConfirm) {
            Write-Log "INFO" ("Job canceled at the final-path collision prompt: mode={0}; finalPath={1}" -f $Mode, $finalItemPath)
            return "MENU"
        }

        Write-Blank
    }

    $confirm = Read-YesNo ("Run this {0} job now" -f (Get-ModeDisplayName $Mode)) $false
    if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
    if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
    if (-not $confirm) {
        Write-Log "INFO" ("Job canceled by user before execution: mode={0}" -f $Mode)
        return "MENU"
    }

    Write-Blank

    # Re-read the source immediately before the destructive step so a path that
    # changed between the review and the confirmation cannot be acted on.
    $sourceRecheck = Get-PathStatus $SourceInfo.Path
    Write-PathStatusLog "Standard job source recheck before execution" $sourceRecheck
    if (-not $sourceRecheck.Exists -or $sourceRecheck.Type -ne $SourceInfo.Type -or $sourceRecheck.IsReparsePoint) {
        Write-Line "The source path changed after the review, so nothing was transferred." $script:UiColor.Error
        Write-Line ("  {0}" -f $SourceInfo.Path) $script:UiColor.Path
        Write-Log "ERROR" ("Standard job aborted because the source changed after review: {0}" -f (Format-PathStatusForLog $sourceRecheck))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    # Recompute the classification from the same confirmed inputs and compare
    # it to what was shown at review time. The command that runs below is the
    # SAME $robocopyArgs computed at preview time - this never recomputes it,
    # it only decides whether it is still safe to run unchanged.
    $executionClassification = Get-StandardFinalPathClassification -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    Write-PathStatusLog "Standard job final path recheck before execution" $executionClassification.FinalStatus
    Write-Log "INFO" ("Execution-time classification: {0}; effectiveDestination={1}; finalPath={2}" -f `
        $executionClassification.Classification, $executionClassification.EffectiveDestination, $executionClassification.FinalItemPath)

    $classificationDrifted = (-not [string]::Equals($executionClassification.EffectiveDestination, $effectiveDestination, [StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::Equals($executionClassification.FinalItemPath, $finalItemPath, [StringComparison]::OrdinalIgnoreCase)) -or
        ($executionClassification.Classification -ne $classification.Classification) -or
        (-not [string]::IsNullOrWhiteSpace($executionClassification.BlockReason))

    if ($classificationDrifted) {
        Write-Line "The destination state changed after the review, so nothing was transferred." $script:UiColor.Error
        if (-not [string]::IsNullOrWhiteSpace($executionClassification.BlockReason)) {
            Write-Line $executionClassification.BlockReason $script:UiColor.Warning
        }
        else {
            Write-Line ("Reviewed as: {0}; now: {1}" -f $classification.Classification, $executionClassification.Classification) $script:UiColor.Warning
        }
        Write-Log "ERROR" ("Standard job aborted: final-path classification drifted between review and execution. reviewed={0}; execution={1}" -f `
            $classification.Classification, $executionClassification.Classification)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown
    $sourceCleanupOk = $true

    if ($code -le 7 -and $Mode -eq "MOVE" -and $SourceInfo.Type -eq "Directory") {
        $sourceCleanupOk = Remove-EmptySourceDirectoryAfterMove -Path $SourceInfo.Path
    }

    Write-Blank
    Write-Rule $script:UiColor.Border
    if ($code -le 7 -and $sourceCleanupOk) {
        Write-Line "Job completed." $script:UiColor.Success
        Write-Log "INFO" ("Job completed: mode={0}, exitCode={1}" -f $Mode, $code)
    }
    elseif ($code -le 7) {
        Write-Line "Job completed, but the empty source folder could not be removed." $script:UiColor.Warning
        Write-Log "WARN" ("Job completed with source cleanup warning: mode={0}, exitCode={1}, source={2}" -f $Mode, $code, $SourceInfo.Path)
    }
    else {
        Write-Line "Job completed with errors." $script:UiColor.Error
        Write-Log "ERROR" ("Job completed with errors: mode={0}, exitCode={1}" -f $Mode, $code)
    }
    Write-TotalElapsedTime $startedAt
    Write-Log "INFO" ("Elapsed: {0}" -f (Format-ElapsedTime ((Get-Date) - $startedAt)))
    Write-Rule $script:UiColor.Border
    Write-Blank

    return (Read-ReturnToMenu)
}


function Test-UnsafeFastDeletePath {
    param([hashtable]$Status)

    if ($null -eq $Status -or -not $Status.Exists) {
        return "The delete target does not exist."
    }

    $protectedReason = Get-ProtectedRootReason $Status.Path
    if (-not [string]::IsNullOrWhiteSpace($protectedReason)) {
        return $protectedReason
    }

    if ($Status.IsReparsePoint -and -not (Test-IsReplaceableLinkStatus $Status)) {
        return "Unsupported reparse points are not deleted automatically, to avoid deleting an unexpected target."
    }

    return $null
}


function Invoke-FastDeleteJob {
    param([hashtable]$DeleteInfo)

    $startedAt = Get-Date

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName "DELETE") $script:UiColor.Error),
        (New-BreadcrumbStep "Delete target" $DeleteInfo.Path $script:UiColor.Path)
    )

    Show-Header
    Write-Line "Review the delete target below before it runs." $script:UiColor.Error
    Write-Blank

    $deleteStatus = Get-PathStatus $DeleteInfo.Path

    Write-LabelValue "Target type" $deleteStatus.Type $script:UiColor.Text
    Write-LabelValue "Target kind" $deleteStatus.Kind $script:UiColor.Text
    Write-PathStatusLog "Fast delete target check" $deleteStatus
    Write-Log "INFO" ("Fast delete start: {0}" -f (Format-PathStatusForLog $deleteStatus))

    $unsafeReason = Test-UnsafeFastDeletePath -Status $deleteStatus
    if (-not [string]::IsNullOrWhiteSpace($unsafeReason)) {
        Write-Blank
        Write-Line "Fast Delete stopped before deleting anything." $script:UiColor.Error
        Write-Line $unsafeReason $script:UiColor.Warning
        Write-Log "ERROR" ("Fast delete blocked: {0}; target=({1})" -f $unsafeReason, (Format-PathStatusForLog $deleteStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    Write-Blank
    Write-Line "This is permanent. The selected path will not go to the Recycle Bin." $script:UiColor.Warning
    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        Write-Hint "The selected path is a link or junction. RoboSy will delete only the link entry, not its target."
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        Write-Hint "The selected folder and everything inside it will be permanently deleted."
    }
    else {
        Write-Hint "The selected file will be deleted directly."
    }
    Write-Blank

    # Show the command that will run before asking for the final confirmation.
    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        # Link removal uses a direct delete, so there is no shell command to preview.
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        $purgePreviewArgs = @("<temporary empty folder>", $deleteStatus.Path, "/MIR", "/MT:32", "/R:0", "/W:0", "/XJ", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
        $purgeCmd = Get-RobocopyCommandText -Arguments $purgePreviewArgs
        $rmdirCmd = "cmd.exe /d /c rmdir /s /q " + (Format-CmdPathArgument $deleteStatus.Path)
        Write-CommandPlan @($purgeCmd, $rmdirCmd)
    }
    else {
        Write-CommandPreview ("cmd.exe /d /c del /f /q /a " + (Format-CmdPathArgument $deleteStatus.Path))
    }

    $confirm = Read-YesNo "Permanently delete this path now" $true
    if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
    if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
    if (-not $confirm) {
        Write-Log "INFO" ("Fast delete canceled by user: {0}" -f $deleteStatus.Path)
        return "MENU"
    }

    Write-Blank

    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        $deleted = Remove-ExistingLinkOnly -Path $deleteStatus.Path -Status $deleteStatus
        $code = if ($deleted) { 0 } else { 1 }
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        $code = Invoke-RobocopyPurgeDirectoryDelete -TargetPath $deleteStatus.Path -PreviewShown
    }
    else {
        if (-not (Assert-CmdAvailable)) {
            Write-Blank
            return (Read-ReturnToMenu)
        }

        $quotedPath = Format-CmdPathArgument $deleteStatus.Path
        $commandText = "del /f /q /a $quotedPath"
        $code = Invoke-CmdDeleteCommand -CommandText $commandText -PreviewShown
    }

    $after = Get-PathStatus $deleteStatus.Path
    Write-PathStatusLog "Fast delete target after delete" $after

    Write-Blank
    Write-Rule $script:UiColor.Border
    if ($code -eq 0 -and -not $after.Exists) {
        Write-Line "Fast delete completed." $script:UiColor.Success
        Write-Log "INFO" ("Fast delete completed: {0}" -f $deleteStatus.Path)
    }
    else {
        Write-Line "Fast delete did not complete." $script:UiColor.Error
        if ($after.Exists) {
            Write-Line "The target path still exists. It may be locked or require Administrator permission." $script:UiColor.Warning
        }
        Write-Log "ERROR" ("Fast delete incomplete: code={0}; after=({1})" -f $code, (Format-PathStatusForLog $after))
    }
    Write-TotalElapsedTime $startedAt
    Write-Log "INFO" ("Elapsed: {0}" -f (Format-ElapsedTime ((Get-Date) - $startedAt)))
    Write-Rule $script:UiColor.Border
    Write-Blank

    return (Read-ReturnToMenu)
}
