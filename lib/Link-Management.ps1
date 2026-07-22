# RoboSy module: Link-Management.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Rollback-safe symbolic link / junction creation and replacement, shared by Move + Symlink and Symlink Only.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

function Test-IsReplaceableLinkStatus {
    param([hashtable]$Status)

    return ($null -ne $Status -and $Status.Exists -and ($Status.IsSymbolicLink -or $Status.IsJunction))
}


function Remove-ExistingLinkOnly {
    param(
        [string]$Path,
        [hashtable]$Status
    )

    if (-not (Test-IsReplaceableLinkStatus $Status)) {
        return $false
    }

    Write-Line "Existing link detected at the original path; removing the link only." $script:UiColor.Warning
    Write-Log "INFO" ("Removing existing link only: {0}" -f (Format-PathStatusForLog $Status))

    try {
        if ($Status.Type -eq "Directory") {
            [System.IO.Directory]::Delete($Path, $false)
        }
        else {
            [System.IO.File]::Delete($Path)
        }
    }
    catch {
        Write-Line "Could not remove the existing link at the original path." $script:UiColor.Error
        Write-Line $_.Exception.Message $script:UiColor.Error
        Write-Log "ERROR" ("Existing link removal failed for {0}: {1}" -f $Path, $_.Exception.Message)
        return $false
    }

    $after = Get-PathStatus $Path
    Write-PathStatusLog "Original/link after existing-link removal" $after

    if ($after.Exists) {
        Write-Line "The original path still exists after link removal; the new link was not created." $script:UiColor.Error
        Write-Log "ERROR" ("Existing link removal did not clear original path: {0}" -f (Format-PathStatusForLog $after))
        return $false
    }

    Write-Log "INFO" ("Existing link removed safely without following the link target: {0}" -f $Path)
    return $true
}


function Write-MoveLinkMissingPaths {
    param(
        [hashtable]$SourceStatus,
        [hashtable]$TargetStatus
    )

    Write-Line "Neither the original path nor the resolved target path exists." $script:UiColor.Error
    Write-Line "Checked paths:" $script:UiColor.Muted
    Write-Line ("  Original/link: {0}" -f $SourceStatus.Path) $script:UiColor.Path
    Write-Line ("  Real target:   {0}" -f $TargetStatus.Path) $script:UiColor.Path
    Write-Line ("  Target parent: {0}" -f $TargetStatus.Parent) $script:UiColor.Path
    Write-Line ("  Target parent exists: {0}" -f $TargetStatus.ParentExists) $script:UiColor.Muted
    Write-Line "Enter an existing original path to move it, or enter an existing target path to create only the link." $script:UiColor.Muted
    Write-Line "If the target should be created by moving the original, the original path must exist." $script:UiColor.Muted
    Write-Log "ERROR" ("Move+Link stopped because both resolved paths are missing. original=({0}); target=({1})" -f (Format-PathStatusForLog $SourceStatus), (Format-PathStatusForLog $TargetStatus))
}


function New-RoboSySymbolicLink {
    param(
        [string]$Path,
        [string]$Target
    )

    $parent = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = "."
    }

    return (New-Item -ItemType SymbolicLink -Path ([System.Management.Automation.WildcardPattern]::Escape($parent)) -Name $name -Target $Target -ErrorAction Stop)
}

function New-RoboSyJunction {
    param(
        [string]$Path,
        [string]$Target
    )

    $parent = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path
    if ([string]::IsNullOrWhiteSpace($parent)) {
        $parent = "."
    }

    return (New-Item -ItemType Junction -Path ([System.Management.Automation.WildcardPattern]::Escape($parent)) -Name $name -Target $Target -ErrorAction Stop)
}


function Resolve-LinkTargetPath {
    param(
        [hashtable]$SourceInfo,
        [hashtable]$TargetInputInfo
    )

    $resolvedPath = $TargetInputInfo.Path
    $decision = "UseEnteredTarget"
    $targetLeaf = Get-PathLeafForCompare $TargetInputInfo.Path

    $sourceIsExistingLink = ($SourceInfo.Exists -and ($SourceInfo.IsSymbolicLink -or $SourceInfo.IsJunction))

    if ($sourceIsExistingLink) {
        $decision = "OriginalIsExistingLinkUseEnteredTarget"
    }
    elseif ($SourceInfo.Exists -and $TargetInputInfo.Exists -and $TargetInputInfo.Type -eq "Directory") {
        if ($SourceInfo.Type -eq "Directory" -and $SourceInfo.Name.Equals($targetLeaf, [StringComparison]::OrdinalIgnoreCase)) {
            $decision = "TargetAlreadyFinalDirectory"
        }
        else {
            $resolvedPath = Join-Path -Path $TargetInputInfo.Path -ChildPath $SourceInfo.Name
            $decision = "TargetIsParentDirectory"
        }
    }

    $TargetInputInfo.ResolutionDecision = $decision
    $TargetInputInfo.ResolvedPath = $resolvedPath

    Write-Log "INFO" ("Resolved link target: source={0}; sourceName={1}; targetInput={2}; targetInputExists={3}; targetInputType={4}; targetLeaf={5}; decision={6}; resolved={7}" -f `
        $SourceInfo.Path, $SourceInfo.Name, $TargetInputInfo.Path, $TargetInputInfo.Exists, $TargetInputInfo.Type, $targetLeaf, $decision, $resolvedPath)

    return $resolvedPath
}

function Get-RobocopyMoveArgs {
    param(
        [hashtable]$SourceInfo,
        [string]$TargetPath
    )

    $commonArgs = Get-CommonRobocopyArgs

    if ($SourceInfo.Type -eq "Directory") {
        return @($SourceInfo.Path, $TargetPath, "/E") + $commonArgs + @("/MOVE")
    }

    $targetParent = Split-Path -Parent $TargetPath
    return @($SourceInfo.Parent, $targetParent, $SourceInfo.Name) + $commonArgs + @("/MOV")
}

function Invoke-RobocopyMoveToExactPath {
    param(
        [hashtable]$SourceInfo,
        [string]$TargetPath
    )

    if (-not (Assert-RobocopyAvailable)) {
        return 16
    }

    if ($SourceInfo.Type -eq "Directory") {
        $targetParent = Split-Path -Parent $TargetPath
        if (-not [string]::IsNullOrWhiteSpace($targetParent) -and -not (Test-Path -LiteralPath $targetParent)) {
            try {
                New-RoboSyDirectory -Path $targetParent | Out-Null
            }
            catch {
                Write-Log "WARN" ("Could not pre-create target parent {0}: {1}" -f $targetParent, $_.Exception.Message)
                # Robocopy will fail next and trigger admin escalation if needed.
            }
        }

        $robocopyArgs = Get-RobocopyMoveArgs -SourceInfo $SourceInfo -TargetPath $TargetPath
        $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown

        if ($code -le 7 -and -not (Remove-EmptySourceDirectoryAfterMove -Path $SourceInfo.Path)) {
            if (-not (Test-RunningAsAdministrator)) {
                $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
            }
            return 16
        }

        return $code
    }

    $targetParent = Split-Path -Parent $TargetPath
    $targetName = Split-Path -Leaf $TargetPath

    if ([string]::IsNullOrWhiteSpace($targetParent)) {
        Write-Line "Target file path must include a parent folder." $script:UiColor.Error
        return 16
    }

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Line "Target file path already exists; move + link will not overwrite it:" $script:UiColor.Error
        Write-Line ("  {0}" -f $TargetPath) $script:UiColor.Path
        Write-Log "ERROR" ("Exact target file path already exists before move: {0}" -f $TargetPath)
        return 16
    }

    if (-not (Test-Path -LiteralPath $targetParent)) {
        try {
            New-RoboSyDirectory -Path $targetParent | Out-Null
        }
        catch {
            Write-Log "WARN" ("Could not pre-create target parent {0}: {1}" -f $targetParent, $_.Exception.Message)
        }
    }

    $robocopyArgs = Get-RobocopyMoveArgs -SourceInfo $SourceInfo -TargetPath $TargetPath
    $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown

    if ($code -le 7 -and $targetName -ne $SourceInfo.Name) {
        $movedPath = Join-Path -Path $targetParent -ChildPath $SourceInfo.Name
        if (Test-Path -LiteralPath $TargetPath) {
            Write-Line "Cannot rename moved file because the target file appeared during the move:" $script:UiColor.Error
            Write-Line ("  {0}" -f $TargetPath) $script:UiColor.Path
            Write-Log "ERROR" ("Rename target appeared after move and before rename: {0}" -f $TargetPath)
            return 16
        }

        if (Test-Path -LiteralPath $movedPath) {
            try {
                Rename-Item -LiteralPath $movedPath -NewName $targetName -ErrorAction Stop
            }
            catch {
                Write-Line ("Could not rename {0} to {1}: {2}" -f $movedPath, $targetName, $_.Exception.Message) $script:UiColor.Warning
                Write-Log "WARN" ("Rename failed: {0} -> {1}: {2}" -f $movedPath, $targetName, $_.Exception.Message)
                if (-not (Test-RunningAsAdministrator)) {
                    $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
                }
                return 16
            }
        }
        else {
            Write-Line ("Moved file was not found for rename: {0}" -f $movedPath) $script:UiColor.Error
            Write-Log "ERROR" ("Moved file missing before rename: {0}" -f $movedPath)
            return 16
        }
    }

    return $code
}

function Test-LinkCreationCapability {
    param(
        [string]$LinkParent,
        [string]$ItemType
    )

    if ([string]::IsNullOrWhiteSpace($LinkParent) -or -not (Test-Path -LiteralPath $LinkParent)) {
        return @{
            CanCreate = $false
            LinkKind = $null
            Message = "The original path parent folder does not exist."
        }
    }

    $id = [Guid]::NewGuid().ToString("N")
    $targetPath = Join-Path -Path $LinkParent -ChildPath (".robosy-link-test-target-" + $id)
    $linkPath = Join-Path -Path $LinkParent -ChildPath (".robosy-link-test-link-" + $id)

    try {
        if ($ItemType -eq "Directory") {
            New-RoboSyDirectory -Path $targetPath | Out-Null

            try {
                New-RoboSySymbolicLink -Path $linkPath -Target $targetPath | Out-Null
                return @{ CanCreate = $true; LinkKind = "SymbolicLink"; Message = $null }
            }
            catch {
                if (Test-Path -LiteralPath $linkPath) {
                    Remove-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
                }

                try {
                    New-RoboSyJunction -Path $linkPath -Target $targetPath | Out-Null
                    return @{ CanCreate = $true; LinkKind = "Junction"; Message = "Directory symlink is not available; junction fallback is available." }
                }
                catch {
                    return @{ CanCreate = $false; LinkKind = $null; Message = $_.Exception.Message }
                }
            }
        }

        Set-Content -LiteralPath $targetPath -Value "robosy link preflight" -Encoding ASCII

        try {
            New-RoboSySymbolicLink -Path $linkPath -Target $targetPath | Out-Null
            return @{ CanCreate = $true; LinkKind = "SymbolicLink"; Message = $null }
        }
        catch {
            return @{ CanCreate = $false; LinkKind = $null; Message = $_.Exception.Message }
        }
    }
    finally {
        if (Test-Path -LiteralPath $linkPath) {
            Remove-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue
        }

        if (Test-Path -LiteralPath $targetPath) {
            Remove-Item -LiteralPath $targetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-LinkSafe {
    param(
        [string]$LinkPath,
        [string]$TargetPath,
        [switch]$PreviewShown
    )

    $linkStatus = Get-PathStatus $LinkPath
    $targetStatus = Get-PathStatus $TargetPath
    Write-PathStatusLog "Link path before create" $linkStatus
    Write-PathStatusLog "Target path before link create" $targetStatus

    if ($linkStatus.Exists) {
        if (Test-IsReplaceableLinkStatus $linkStatus) {
            if (-not (Remove-ExistingLinkOnly -Path $LinkPath -Status $linkStatus)) {
                return $false
            }
        }
        else {
            Write-Line "Cannot create the symbolic link because the original path exists and is not a symbolic link or junction:" $script:UiColor.Error
            Write-Line ("  {0}" -f $LinkPath) $script:UiColor.Path
            Write-Line ("Detected kind: {0}" -f $linkStatus.Kind) $script:UiColor.Muted
            Write-Log "ERROR" ("Link path exists and is not replaceable: {0}" -f (Format-PathStatusForLog $linkStatus))
            return $false
        }
    }

    if (-not $targetStatus.Exists) {
        Write-Line "Cannot create the symbolic link because the target path does not exist:" $script:UiColor.Error
        Write-Line ("  {0}" -f $TargetPath) $script:UiColor.Path
        Write-Log "ERROR" ("Link target missing before create: {0}" -f (Format-PathStatusForLog $targetStatus))
        return $false
    }

    $targetIsDirectory = ($targetStatus.Type -eq "Directory")

    $linkParent = Split-Path -Parent $LinkPath
    if (-not [string]::IsNullOrWhiteSpace($linkParent) -and -not (Test-Path -LiteralPath $linkParent)) {
        New-RoboSyDirectory -Path $linkParent | Out-Null
        Write-Log "INFO" ("Created link parent directory: {0}" -f $linkParent)
    }

    try {
        if (-not $PreviewShown) {
            Write-CommandPreview ('New-Item -ItemType SymbolicLink -Path {0} -Target {1}' -f (Format-PowerShellArgument $LinkPath), (Format-PowerShellArgument $TargetPath))
        }
        Write-Log "INFO" ("Creating symbolic link: {0} -> {1}" -f $LinkPath, $TargetPath)

        New-RoboSySymbolicLink -Path $LinkPath -Target $TargetPath | Out-Null
        Write-Line "Symbolic link created." $script:UiColor.Success
        Write-PathStatusLog "Link path after create" (Get-PathStatus $LinkPath)
        return $true
    }
    catch {
        Write-Log "WARN" ("Symbolic link creation failed for {0} -> {1}: {2}" -f $LinkPath, $TargetPath, $_.Exception.Message)

        if ($targetIsDirectory) {
            Write-Line "Symbolic link failed. Trying directory junction fallback..." $script:UiColor.Warning

            try {
                Write-CommandPreview ('New-Item -ItemType Junction -Path {0} -Target {1}' -f (Format-PowerShellArgument $LinkPath), (Format-PowerShellArgument $TargetPath))
                Write-Log "INFO" ("Creating directory junction: {0} -> {1}" -f $LinkPath, $TargetPath)

                New-RoboSyJunction -Path $LinkPath -Target $TargetPath | Out-Null
                Write-Line "Directory junction created." $script:UiColor.Success
                Write-PathStatusLog "Link path after junction create" (Get-PathStatus $LinkPath)
                return $true
            }
            catch {
                Write-Line "Failed to create symbolic link or junction." $script:UiColor.Error
                Write-Line $_.Exception.Message $script:UiColor.Error
                Write-Log "ERROR" ("Symbolic link and junction creation failed for {0} -> {1}: {2}" -f $LinkPath, $TargetPath, $_.Exception.Message)
                if (-not (Test-RunningAsAdministrator)) {
                    $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator so it can create the required link..."
                }
                return $false
            }
        }

        Write-Line "Failed to create symbolic link." $script:UiColor.Error
        Write-Line $_.Exception.Message $script:UiColor.Error
        Write-Blank
        Write-Line "Tip: On Windows, symbolic links may require Administrator permission or Developer Mode." $script:UiColor.Warning
        if (-not (Test-RunningAsAdministrator)) {
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator so it can create the required link..."
        }
        return $false
    }
}
# Captures the state of an existing link (if any) and the intended new target
# right before the final confirmation, so it can be re-verified unchanged
# immediately after, and so a failed replacement can be rolled back to
# exactly what was there before.
function Get-LinkReplacementSnapshot {
    param(
        [string]$LinkPath,
        [string]$NewTargetPath
    )

    $linkStatus = Get-PathStatus $LinkPath
    $newTargetStatus = Get-PathStatus $NewTargetPath

    return @{
        LinkPath          = $LinkPath
        NewTargetPath     = $NewTargetPath
        LinkStatus        = $linkStatus
        NewTargetStatus   = $newTargetStatus
        IsReplaceableLink = (Test-IsReplaceableLinkStatus $linkStatus)
    }
}

# Re-reads the same two paths and confirms nothing changed since the snapshot
# was captured, so a stale preview can never drive the destructive step.
function Test-LinkReplacementSnapshotUnchanged {
    param([hashtable]$Snapshot)

    $currentNewTargetStatus = Get-PathStatus $Snapshot.NewTargetPath
    $newTargetUnchanged = $currentNewTargetStatus.Exists -and
        $currentNewTargetStatus.Type -eq $Snapshot.NewTargetStatus.Type -and
        -not $currentNewTargetStatus.IsReparsePoint

    if (-not $Snapshot.IsReplaceableLink) {
        return $newTargetUnchanged
    }

    $currentLinkStatus = Get-PathStatus $Snapshot.LinkPath

    $linkUnchanged = (Test-IsReplaceableLinkStatus $currentLinkStatus) -and
        $currentLinkStatus.Kind.Equals($Snapshot.LinkStatus.Kind, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($currentLinkStatus.LinkTarget, $Snapshot.LinkStatus.LinkTarget, [StringComparison]::OrdinalIgnoreCase)

    return ($linkUnchanged -and $newTargetUnchanged)
}

# Restores a link that was removed as part of a replacement that then failed,
# using the exact kind and target captured in the snapshot. The old target
# itself is never touched by link replacement, so it is still there to link
# back to.
function Restore-PreviousLink {
    param([hashtable]$Snapshot)

    if (-not $Snapshot.IsReplaceableLink) {
        return $true
    }

    $oldKind = $Snapshot.LinkStatus.Kind
    $oldTarget = $Snapshot.LinkStatus.LinkTarget

    try {
        if ($oldKind -eq "Junction") {
            New-RoboSyJunction -Path $Snapshot.LinkPath -Target $oldTarget | Out-Null
        }
        else {
            New-RoboSySymbolicLink -Path $Snapshot.LinkPath -Target $oldTarget | Out-Null
        }
    }
    catch {
        Write-Log "ERROR" ("Rollback failed to restore previous link: {0} -> {1}: {2}" -f $Snapshot.LinkPath, $oldTarget, $_.Exception.Message)
        return $false
    }

    $restoredStatus = Get-PathStatus $Snapshot.LinkPath
    $restoredOk = (Test-IsReplaceableLinkStatus $restoredStatus) -and
        $restoredStatus.Kind.Equals($oldKind, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($restoredStatus.LinkTarget, $oldTarget, [StringComparison]::OrdinalIgnoreCase)

    if (-not $restoredOk) {
        Write-Log "ERROR" ("Rollback restored a link but verification failed: {0}" -f (Format-PathStatusForLog $restoredStatus))
    }

    return $restoredOk
}

# The full replace-or-restore transaction for the original link path. Removal
# of an existing link and creation of the new one happen back-to-back; if the
# new link cannot be created or does not verify, the old link is restored
# immediately and the job is reported as failed either way - never success.
function Invoke-SafeLinkReplacement {
    param(
        [hashtable]$Snapshot,
        [switch]$PreviewShown
    )

    $linkPath = $Snapshot.LinkPath
    $targetPath = $Snapshot.NewTargetPath

    if (-not $Snapshot.IsReplaceableLink) {
        # Nothing to replace or roll back; this is a plain create-only link job.
        return (New-LinkSafe -LinkPath $linkPath -TargetPath $targetPath -PreviewShown:$PreviewShown)
    }

    $capability = Test-LinkCreationCapability -LinkParent (Split-Path -Parent $linkPath) -ItemType $Snapshot.NewTargetStatus.Type
    if (-not $capability.CanCreate) {
        Write-Line "The existing link was left untouched because this session cannot create the required replacement link." $script:UiColor.Error
        if (-not [string]::IsNullOrWhiteSpace($capability.Message)) {
            Write-Line $capability.Message $script:UiColor.Muted
        }
        Write-Log "ERROR" ("Link replacement aborted before removal; capability check failed: {0}" -f $capability.Message)
        return $false
    }

    if (-not (Remove-ExistingLinkOnly -Path $linkPath -Status $Snapshot.LinkStatus)) {
        # Remove-ExistingLinkOnly already reported the failure; the old link is
        # still there untouched, so there is nothing to roll back.
        return $false
    }

    $created = New-LinkSafe -LinkPath $linkPath -TargetPath $targetPath -PreviewShown:$PreviewShown
    $verified = $false

    if ($created) {
        $verifyStatus = Get-PathStatus $linkPath
        $verified = (Test-IsReplaceableLinkStatus $verifyStatus) -and
            [string]::Equals((Normalize-PathForCompare $verifyStatus.LinkTarget), (Normalize-PathForCompare $targetPath), [StringComparison]::OrdinalIgnoreCase)

        if ($verified) {
            return $true
        }

        Write-Line "The replacement link was created but did not verify against the requested target." $script:UiColor.Error
        Write-Log "ERROR" ("Replacement link failed verification: {0}" -f (Format-PathStatusForLog $verifyStatus))
    }

    Write-Line "Restoring the previous link because the replacement could not be completed..." $script:UiColor.Warning
    Write-Log "WARN" ("Attempting rollback for failed link replacement: {0}" -f $linkPath)

    $restored = Restore-PreviousLink -Snapshot $Snapshot

    if ($restored) {
        Write-Line "The previous link was restored. No changes were made overall." $script:UiColor.Warning
        Write-Log "INFO" ("Rollback restored previous link: {0}" -f $linkPath)
    }
    else {
        Write-Line "CRITICAL: the previous link could not be restored automatically." $script:UiColor.Error
        Write-Line ("  Original link path:   {0}" -f $Snapshot.LinkPath) $script:UiColor.Path
        Write-Line ("  Original link target: {0}" -f $Snapshot.LinkStatus.LinkTarget) $script:UiColor.Path
        Write-Line ("  Original link kind:   {0}" -f $Snapshot.LinkStatus.Kind) $script:UiColor.Path
        Write-Line ("  Requested new target: {0}" -f $targetPath) $script:UiColor.Path
        Write-Line "Manual recovery command:" $script:UiColor.Accent
        $recoveryKindArg = if ($Snapshot.LinkStatus.Kind -eq "Junction") { "Junction" } else { "SymbolicLink" }
        Write-CommandPreview ('New-Item -ItemType {0} -Path {1} -Target {2}' -f $recoveryKindArg, (Format-PowerShellArgument $Snapshot.LinkPath), (Format-PowerShellArgument $Snapshot.LinkStatus.LinkTarget))
        Write-Log "ERROR" ("CRITICAL: rollback failed to restore previous link: {0}; originalTarget={1}; kind={2}" -f $Snapshot.LinkPath, $Snapshot.LinkStatus.LinkTarget, $Snapshot.LinkStatus.Kind)
    }

    return $false
}

function New-SymlinkMarkerFile {
    param(
        [string]$TargetPath,
        [string]$LinkPath
    )

    if ([string]::IsNullOrWhiteSpace($TargetPath) -or [string]::IsNullOrWhiteSpace($LinkPath)) {
        return $null
    }

    $targetItem = Get-ExistingItem $TargetPath
    if ($null -eq $targetItem) {
        Write-Log "WARN" ("Marker file skipped: target path not found ({0})" -f $TargetPath)
        return $null
    }

    $targetName = $targetItem.Name
    $markerName = "Symlink path_" + $targetName + ".txt"

    if ($targetItem.PSIsContainer) {
        $markerDirectory = $targetItem.FullName
    }
    else {
        $markerDirectory = $targetItem.DirectoryName
        if ([string]::IsNullOrWhiteSpace($markerDirectory)) {
            $markerDirectory = Split-Path -Parent $targetItem.FullName
        }
    }

    if ([string]::IsNullOrWhiteSpace($markerDirectory)) {
        Write-Log "WARN" ("Marker file skipped: could not resolve target directory for {0}" -f $TargetPath)
        return $null
    }

    $markerPath = Join-Path -Path $markerDirectory -ChildPath $markerName

    try {
        # A single target can be linked from several places, so the marker
        # accumulates one line per link and never overwrites the previous
        # entries. The same link path is not added twice.
        $existingLines = @()
        if (Test-Path -LiteralPath $markerPath) {
            $existingLines = @(Get-Content -LiteralPath $markerPath -Encoding UTF8 -ErrorAction Stop |
                ForEach-Object { $_.TrimEnd() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        $alreadyListed = $false
        foreach ($line in $existingLines) {
            if ([string]::Equals($line.Trim(), $LinkPath.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
                $alreadyListed = $true
                break
            }
        }

        if ($alreadyListed) {
            Write-Line ("Marker file already lists this link: {0}" -f $markerPath) $script:UiColor.Muted
            Write-Log "INFO" ("Marker file already contains link {0}: {1}" -f $LinkPath, $markerPath)
            return $markerPath
        }

        $newLines = @($existingLines) + $LinkPath
        Set-Content -LiteralPath $markerPath -Value $newLines -Encoding UTF8 -ErrorAction Stop

        if ($existingLines.Count -gt 0) {
            Write-Line ("Marker file updated (now {0} links): {1}" -f $newLines.Count, $markerPath) $script:UiColor.Success
            Write-Log "INFO" ("Marker file appended link: {0} -> {1} (now {2} link(s))" -f $LinkPath, $markerPath, $newLines.Count)
        }
        else {
            Write-Line ("Marker file: {0}" -f $markerPath) $script:UiColor.Success
            Write-Log "INFO" ("Marker file created: {0} -> {1}" -f $markerPath, $LinkPath)
        }
        return $markerPath
    }
    catch {
        $reason = $_.Exception.Message
        Write-Line ("Could not create marker file: {0}" -f $reason) $script:UiColor.Warning
        Write-Log "WARN" ("Marker file creation failed for {0}: {1}" -f $markerPath, $reason)

        $accessDenied = ($_.Exception -is [System.UnauthorizedAccessException]) -or ($reason -match 'access is denied|access denied|permission denied')
        if ($accessDenied -and -not (Test-RunningAsAdministrator)) {
            Write-Line "Tip: type 'admin' at the next prompt to relaunch elevated, then re-run Option 4 to retry the marker." $script:UiColor.Muted
        }

        return $null
    }
}

# Shared completion reporting for Invoke-MoveAndLinkJob's two link-creation
# paths (move-then-link, and create/replace-only), so the log/console output
# for success and failure cannot drift between them.
function Complete-MoveAndLinkJob {
    param(
        [bool]$Linked,
        [string]$SourcePath,
        [string]$TargetPath,
        [datetime]$StartedAt,
        [string]$CompletedMessage = "Move + symbolic link job completed.",
        [string]$FailedMessage = "Symbolic link job did not complete.",
        [string]$LogLabel = "Move+Link"
    )

    if ($Linked) {
        Write-Log "INFO" ("Symbolic link created: {0} -> {1}" -f $SourcePath, $TargetPath)
        $null = New-SymlinkMarkerFile -TargetPath $TargetPath -LinkPath $SourcePath
    }
    else {
        Write-Log "ERROR" ("Symbolic link creation failed: {0} -> {1}" -f $SourcePath, $TargetPath)
    }

    Write-Blank
    Write-Rule $script:UiColor.Border
    if ($Linked) {
        Write-Line $CompletedMessage $script:UiColor.Success
        Write-Log "INFO" ("{0} job completed." -f $LogLabel)
    }
    else {
        Write-Line $FailedMessage $script:UiColor.Error
        Write-Log "ERROR" ("{0} job did not complete." -f $LogLabel)
    }
    Write-TotalElapsedTime $StartedAt
    Write-Log "INFO" ("Elapsed: {0}" -f (Format-ElapsedTime ((Get-Date) - $StartedAt)))
    Write-Rule $script:UiColor.Border
    Write-Blank

    return (Read-ReturnToMenu)
}

function Invoke-MoveAndLinkJob {
    param(
        [hashtable]$SourceInfo,
        [hashtable]$TargetInputInfo
    )

    $startedAt = Get-Date
    $linkPreviewShown = $false

    $sourcePath = $SourceInfo.Path
    $targetPath = Resolve-LinkTargetPath -SourceInfo $SourceInfo -TargetInputInfo $TargetInputInfo
    $sourceStatus = Get-PathStatus $sourcePath
    $targetStatus = Get-PathStatus $targetPath
    $sourceExists = $sourceStatus.Exists
    $targetExists = $targetStatus.Exists

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName "LINK") $script:UiColor.Accent),
        (New-BreadcrumbStep "Original/link" $sourcePath $script:UiColor.Path),
        (New-BreadcrumbStep "Real target" $targetPath $script:UiColor.Path)
    )
    Show-Header
    Write-Line "Review the move + symbolic link job below before it runs." $script:UiColor.Accent
    Write-Blank

    Write-PathStatusLog "Move+Link original/link check" $sourceStatus
    Write-PathStatusLog "Move+Link real target check" $targetStatus
    Write-Log "INFO" ("Move+Link start: original/link={0}, realTarget={1}, sourceExists={2}, targetExists={3}, sourceKind={4}, targetKind={5}" -f $sourcePath, $targetPath, $sourceExists, $targetExists, $sourceStatus.Kind, $targetStatus.Kind)

    $sourceIsReplaceableLink = Test-IsReplaceableLinkStatus $sourceStatus
    $sourceIsUnsupportedReparsePoint = ($sourceStatus.Exists -and $sourceStatus.IsReparsePoint -and -not $sourceIsReplaceableLink)

    if ($sourceIsUnsupportedReparsePoint) {
        Write-Line "The original path is an unsupported reparse point, not a normal file/folder or replaceable link." $script:UiColor.Error
        Write-Line "Remove it manually or choose the real target path directly." $script:UiColor.Muted
        Write-Log "ERROR" ("Unsupported original-path reparse point: {0}" -f (Format-PathStatusForLog $sourceStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if ($sourceIsReplaceableLink) {
        if (-not $targetExists) {
            Write-Line "The original path is already a link, but the new real target path does not exist." $script:UiColor.Error
            Write-Line "RoboSy will not follow or move the existing link target automatically." $script:UiColor.Muted
            Write-Line "Enter an existing real target path, or remove the link manually and enter a real original path." $script:UiColor.Muted
            Write-Log "ERROR" ("Original path is a replaceable link but target is missing. original=({0}); target=({1})" -f (Format-PathStatusForLog $sourceStatus), (Format-PathStatusForLog $targetStatus))
            Write-Blank
            return (Read-ReturnToMenu)
        }

        # The existing link is left untouched here. Removing it during the
        # review would destroy it even if the user then cancels. New-LinkSafe
        # re-reads the path and removes the link only after the confirmation,
        # immediately before the replacement link is created.
        $sourceExists = $false
    }

    $allowExistingFinalTargetMove = ($sourceExists -and $targetExists -and $SourceInfo.Type -eq "Directory" -and $targetStatus.Type -eq "Directory" -and $TargetInputInfo.ResolutionDecision -eq "TargetAlreadyFinalDirectory")

    if ($sourceExists -and $targetExists -and -not $allowExistingFinalTargetMove) {
        Write-Line "Both paths already exist." $script:UiColor.Error
        Write-Line "The script will not overwrite an existing target or delete an existing source path." $script:UiColor.Muted
        Write-Line "Move/remove one of the paths manually, then run this option again." $script:UiColor.Muted
        Write-Log "ERROR" ("Move+Link stopped because both paths exist and are not a same-name final target case. original=({0}); target=({1})" -f (Format-PathStatusForLog $sourceStatus), (Format-PathStatusForLog $targetStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if ($allowExistingFinalTargetMove) {
        Write-Hint "The target folder already matches the source folder name; RoboSy will use it directly."
        Write-Hint "Files will be moved into that existing target folder before the link is created."
        Write-Log "INFO" ("Allowing move into existing same-name final target: original=({0}); target=({1})" -f (Format-PathStatusForLog $sourceStatus), (Format-PathStatusForLog $targetStatus))
        Write-Blank
    }

    if (-not $sourceExists -and -not $targetExists) {
        Write-MoveLinkMissingPaths -SourceStatus $sourceStatus -TargetStatus $targetStatus
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if ($sourceExists) {
        if ($SourceInfo.Type -eq "Directory" -and (Test-IsSameOrChildPath -Parent $SourceInfo.Path -Child $targetPath)) {
            Write-Line "Target cannot be the source folder or a folder inside the source." $script:UiColor.Error
            Write-Line "That would move a directory into itself." $script:UiColor.Warning
            Write-Blank
            return (Read-ReturnToMenu)
        }

        $linkParent = Split-Path -Parent $sourcePath
        $capability = Test-LinkCreationCapability -LinkParent $linkParent -ItemType $SourceInfo.Type
        if (-not $capability.CanCreate) {
            Write-Line "Move was not started because this session cannot create the required link at the original path." $script:UiColor.Error
            if (-not [string]::IsNullOrWhiteSpace($capability.Message)) {
                Write-Line $capability.Message $script:UiColor.Muted
            }

            if (-not (Test-RunningAsAdministrator)) {
                $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator so it can create the required link..."
            }

            Write-Line "Run as Administrator, enable Windows Developer Mode, or use a directory target where junction fallback is available." $script:UiColor.Warning
            Write-Blank
            return (Read-ReturnToMenu)
        }

        if ($capability.LinkKind -eq "Junction") {
            Write-Hint "Directory symbolic links are not available in this session; the script will use a junction fallback after moving."
            Write-Blank
        }

        Write-Hint "The original path exists and the real target is missing."
        Write-Hint "The script will move the real item to the target path, then create a symbolic link at the original path."
        Write-Blank
        $moveCmd = Get-RobocopyCommandText -Arguments (Get-RobocopyMoveArgs -SourceInfo $SourceInfo -TargetPath $targetPath)
        $linkCmd = 'New-Item -ItemType SymbolicLink -Path {0} -Target {1}' -f (Format-PowerShellArgument $sourcePath), (Format-PowerShellArgument $targetPath)
        Write-CommandPlan @($moveCmd, $linkCmd)
        $linkPreviewShown = $true

        $confirm = Read-YesNo "Continue with move + link" $false
        if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
        if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
        if (-not $confirm) { return "MENU" }

        Write-Blank
        $code = Invoke-RobocopyMoveToExactPath -SourceInfo $SourceInfo -TargetPath $targetPath
        if ($code -gt 7) {
            Write-Blank
            Write-Line "Move failed, so the symbolic link was not created." $script:UiColor.Error
            Write-TotalElapsedTime $startedAt
            Write-Blank
            return (Read-ReturnToMenu)
        }

        if (Test-Path -LiteralPath $sourcePath) {
            Write-Blank
            Write-Line "The source path still exists after robocopy, so the link was not created." $script:UiColor.Error
            Write-Line "Check for locked files or remaining hidden items at the original path." $script:UiColor.Muted
            Write-TotalElapsedTime $startedAt
            Write-Blank
            return (Read-ReturnToMenu)
        }
    }
    else {
        # Captured now, before the confirmation prompt, and re-verified
        # unchanged immediately after it - so nothing about the existing link
        # or the new target is removed or trusted based on a stale preview.
        $linkSnapshot = Get-LinkReplacementSnapshot -LinkPath $sourcePath -NewTargetPath $targetPath

        if ($sourceIsReplaceableLink) {
            Write-Blank
            Write-Line ("WARNING: {0} is already a {1}." -f $sourcePath, $sourceStatus.Kind) Red $script:LinkWarningAnsiColor
            Write-Blank
            Write-Line ("  It currently points to: {0}" -f $sourceStatus.LinkTarget) $script:UiColor.Path
            Write-Line ("  It will be REPOINTED to: {0}" -f $targetPath) $script:UiColor.Warning
            Write-Hint "Only the link is changed; the old target itself is never deleted or followed."
        }
        else {
            Write-Hint "The original path is missing and the real target exists."
            Write-Hint "The script will create only the symbolic link."
        }
        Write-Blank
        Write-CommandPreview ('New-Item -ItemType SymbolicLink -Path {0} -Target {1}' -f (Format-PowerShellArgument $sourcePath), (Format-PowerShellArgument $targetPath))
        $linkPreviewShown = $true

        $confirm = if ($sourceIsReplaceableLink) {
            Read-YesNo "Replace the existing link now" $false
        }
        else {
            Read-YesNo "Create the symbolic link now" $false
        }
        if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
        if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
        if (-not $confirm) {
            Write-Log "INFO" ("Move+Link canceled by user before link creation: {0} -> {1}" -f $sourcePath, $targetPath)
            return "MENU"
        }
        Write-Blank

        if (-not (Test-LinkReplacementSnapshotUnchanged -Snapshot $linkSnapshot)) {
            Write-Line "The original link or the new target changed after the review, so nothing was replaced." $script:UiColor.Error
            Write-Log "ERROR" ("Link replacement aborted: state changed since preview. link={0}; target={1}" -f $sourcePath, $targetPath)
            Write-Blank
            return (Read-ReturnToMenu)
        }

        $linked = Invoke-SafeLinkReplacement -Snapshot $linkSnapshot -PreviewShown:$linkPreviewShown
        return (Complete-MoveAndLinkJob -Linked $linked -SourcePath $sourcePath -TargetPath $targetPath -StartedAt $startedAt)
    }

    # The original path was real and has just been moved away by robocopy
    # above; it is confirmed gone, so this is always a create-only link (never
    # a replacement), and the snapshot below is captured fresh with no prompt
    # in between.
    $linkSnapshot = Get-LinkReplacementSnapshot -LinkPath $sourcePath -NewTargetPath $targetPath
    $linked = Invoke-SafeLinkReplacement -Snapshot $linkSnapshot -PreviewShown:$linkPreviewShown
    return (Complete-MoveAndLinkJob -Linked $linked -SourcePath $sourcePath -TargetPath $targetPath -StartedAt $startedAt)
}

# Symlink Only (option 5) decides direction from the two entered paths. A "real
# item" is an existing path that is NOT a reparse point - the thing a link can
# point at.
# - Exactly one side real  -> order does not matter: the real side is the target,
#   the other side (missing, or an existing replaceable link) is the link.
# - Both sides real         -> order DOES matter (user-fixed convention): Path 1
#   is the real source, and the link is created INSIDE Path 2 as
#   <Path 2>\<Path 1 name> -> Path 1. Nothing in Path 2 is moved or deleted. The
#   caller enforces that Path 2 is a folder and computes the nested link path.
# - Neither side real       -> refused; there is nothing to link to.
function Resolve-SymlinkOnlyDirection {
    param(
        [hashtable]$FirstInfo,
        [hashtable]$SecondInfo
    )

    $firstReal = ($FirstInfo.Exists -and -not $FirstInfo.IsReparsePoint)
    $secondReal = ($SecondInfo.Exists -and -not $SecondInfo.IsReparsePoint)

    if ($firstReal -and $secondReal) {
        return @{ Decision = "BothReal" }
    }

    if (-not $firstReal -and -not $secondReal) {
        return @{ Decision = "NeitherReal" }
    }

    if ($firstReal) {
        return @{ Decision = "OK"; TargetInfo = $FirstInfo; LinkInfo = $SecondInfo }
    }

    return @{ Decision = "OK"; TargetInfo = $SecondInfo; LinkInfo = $FirstInfo }
}

function Invoke-SymlinkOnlyJob {
    param(
        [hashtable]$FirstInfo,
        [hashtable]$SecondInfo
    )

    $startedAt = Get-Date

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName "SYMONLY") $script:UiColor.Accent),
        (New-BreadcrumbStep "Path 1" $FirstInfo.Path $script:UiColor.Path),
        (New-BreadcrumbStep "Path 2" $SecondInfo.Path $script:UiColor.Path)
    )
    Show-Header
    Write-Line "Review the symbolic-link-only job below before it runs." $script:UiColor.Accent
    Write-Blank

    $firstStatus = Get-PathStatus $FirstInfo.Path
    $secondStatus = Get-PathStatus $SecondInfo.Path
    Write-PathStatusLog "Symlink-only path 1 check" $firstStatus
    Write-PathStatusLog "Symlink-only path 2 check" $secondStatus

    $direction = Resolve-SymlinkOnlyDirection -FirstInfo $firstStatus -SecondInfo $secondStatus
    Write-Log "INFO" ("Symlink-only start: path1={0}, path2={1}, decision={2}" -f $FirstInfo.Path, $SecondInfo.Path, $direction.Decision)

    if ($direction.Decision -eq "NeitherReal") {
        Write-Line "Neither path points to a real file or folder to link to." $script:UiColor.Error
        Write-Line "One side must be an existing real item; the other side is where the link is created." $script:UiColor.Muted
        Write-Log "ERROR" ("Symlink-only stopped: neither path is a real item. path1=({0}); path2=({1})" -f (Format-PathStatusForLog $firstStatus), (Format-PathStatusForLog $secondStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    # Resolve the target (the real item the link points at) and the link path.
    $nestedInContainer = $false
    if ($direction.Decision -eq "BothReal") {
        # User-fixed convention: Path 1 is the real source; the link goes INSIDE
        # Path 2 as <Path 2>\<Path 1 name>. Nothing in Path 2 is moved or deleted.
        if ($secondStatus.Type -ne "Directory") {
            Write-Line "Both paths already exist, so the link must be created inside Path 2 - but Path 2 is a file, not a folder." $script:UiColor.Error
            Write-Line ("  Path 2: {0}" -f $secondStatus.Path) $script:UiColor.Path
            Write-Line "Enter a folder as Path 2, or remove one of the two real items first." $script:UiColor.Muted
            Write-Log "ERROR" ("Symlink-only stopped: both real but Path 2 is not a folder. path1=({0}); path2=({1})" -f (Format-PathStatusForLog $firstStatus), (Format-PathStatusForLog $secondStatus))
            Write-Blank
            return (Read-ReturnToMenu)
        }
        $targetStatus = $firstStatus
        $targetPath = $firstStatus.Path
        $linkPath = Join-Path -Path $secondStatus.Path -ChildPath $firstStatus.Name
        $nestedInContainer = $true
    }
    else {
        $targetStatus = $direction.TargetInfo
        $targetPath = $direction.TargetInfo.Path
        $linkPath = $direction.LinkInfo.Path
    }

    # For the both-real case the link path is freshly computed inside Path 2, so
    # read its real status now (it is usually missing, but could already be an
    # item or a replaceable link).
    $linkStatus = Get-PathStatus $linkPath

    if ([string]::Equals((Normalize-PathForCompare $targetPath), (Normalize-PathForCompare $linkPath), [StringComparison]::OrdinalIgnoreCase)) {
        Write-Line "The link and its target resolve to the same location, so no link can be created." $script:UiColor.Error
        Write-Log "ERROR" ("Symlink-only stopped: link and target resolve to the same location: {0}" -f $targetPath)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    # A link created inside its own target directory would point back up at a
    # folder that contains it - a loop. Refuse it (more likely in the both-real
    # nested case, e.g. Path 2 sitting inside Path 1).
    if ($targetStatus.Type -eq "Directory" -and (Test-IsSameOrChildPath -Parent $targetPath -Child $linkPath)) {
        Write-Line "The link would be created inside its own target folder, which forms a loop." $script:UiColor.Error
        Write-Line ("  Target: {0}" -f $targetPath) $script:UiColor.Path
        Write-Line ("  Link:   {0}" -f $linkPath) $script:UiColor.Path
        Write-Log "ERROR" ("Symlink-only stopped: link inside its own target (loop). target={0}; link={1}" -f $targetPath, $linkPath)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $linkIsReplaceable = Test-IsReplaceableLinkStatus $linkStatus
    if ($linkStatus.Exists -and -not $linkIsReplaceable) {
        if ($nestedInContainer) {
            Write-Line ("Path 2 already contains a real item named '{0}', so the link will not overwrite it." -f $firstStatus.Name) $script:UiColor.Error
        }
        else {
            Write-Line "The link side already exists and is not a symbolic link or junction, so it will not be replaced." $script:UiColor.Error
        }
        Write-Line ("  {0}" -f $linkPath) $script:UiColor.Path
        Write-Log "ERROR" ("Symlink-only stopped: link path exists and is not replaceable: {0}" -f (Format-PathStatusForLog $linkStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $capability = Test-LinkCreationCapability -LinkParent (Split-Path -Parent $linkPath) -ItemType $targetStatus.Type
    if (-not $capability.CanCreate) {
        Write-Line "This session cannot create the required link at the link path." $script:UiColor.Error
        if (-not [string]::IsNullOrWhiteSpace($capability.Message)) {
            Write-Line $capability.Message $script:UiColor.Muted
        }

        if (-not (Test-RunningAsAdministrator)) {
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator so it can create the required link..."
        }

        Write-Line "Run as Administrator, enable Windows Developer Mode, or point the link at a directory where junction fallback is available." $script:UiColor.Warning
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if ($capability.LinkKind -eq "Junction") {
        Write-Hint "Directory symbolic links are not available in this session; the script will use a junction fallback."
    }

    # Spell out exactly what will happen before the final confirmation.
    Write-Hint ("Real source (link target): {0}" -f $targetPath)
    if ($nestedInContainer) {
        Write-Hint "Both paths exist, so the link is created INSIDE Path 2. Nothing in Path 2 is moved or deleted."
        Write-Hint ("New link: {0}  ->  {1}" -f $linkPath, $targetPath)
    }
    elseif ($linkIsReplaceable) {
        # Make it unmistakable that an existing link is being repointed and show
        # where it currently points, so its real target is never a surprise.
        Write-Blank
        Write-Line ("WARNING: {0} is already a {1}." -f $linkPath, $linkStatus.Kind) Red $script:LinkWarningAnsiColor
        Write-Blank
        Write-Line ("  It currently points to: {0}" -f $linkStatus.LinkTarget) $script:UiColor.Path
        Write-Line ("  It will be REPOINTED to: {0}" -f $targetPath) $script:UiColor.Warning
        Write-Hint "Only the link is changed; the old target itself is never deleted or followed."
    }
    else {
        Write-Hint ("The symbolic link will be created at: {0}" -f $linkPath)
    }
    Write-Blank
    Write-CommandPreview ('New-Item -ItemType SymbolicLink -Path {0} -Target {1}' -f (Format-PowerShellArgument $linkPath), (Format-PowerShellArgument $targetPath))

    # Captured before the confirmation prompt and re-verified unchanged
    # immediately after, so nothing is removed or trusted on a stale preview.
    $linkSnapshot = Get-LinkReplacementSnapshot -LinkPath $linkPath -NewTargetPath $targetPath

    $confirm = if ($linkIsReplaceable) {
        Read-YesNo "Replace the existing link now" $false
    }
    else {
        Read-YesNo "Create the symbolic link now" $false
    }
    if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
    if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
    if (-not $confirm) {
        Write-Log "INFO" ("Symlink-only canceled by user before link creation: {0} -> {1}" -f $linkPath, $targetPath)
        return "MENU"
    }
    Write-Blank

    if (-not (Test-LinkReplacementSnapshotUnchanged -Snapshot $linkSnapshot)) {
        Write-Line "The link path or the real target changed after the review, so nothing was created." $script:UiColor.Error
        Write-Log "ERROR" ("Symlink-only aborted: state changed since preview. link={0}; target={1}" -f $linkPath, $targetPath)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $linked = Invoke-SafeLinkReplacement -Snapshot $linkSnapshot -PreviewShown
    return (Complete-MoveAndLinkJob -Linked $linked -SourcePath $linkPath -TargetPath $targetPath -StartedAt $startedAt -CompletedMessage "Symlink-only job completed." -FailedMessage "Symlink-only job did not complete." -LogLabel "Symlink-only")
}
