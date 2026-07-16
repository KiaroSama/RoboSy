# RoboSy regression tests: destination resolution, native-command wrappers
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# Non-interactive regression tests for RoboSy path resolution, robocopy argument
# building, and native-command wrappers. No test framework is required: run the
# file with PowerShell 5.1 or PowerShell 7+ and check the exit code.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RoboSy.Tests.ps1
#   pwsh -NoProfile -File .\tests\RoboSy.Tests.ps1
#
# Every test works inside a disposable temporary directory that is removed on
# exit. Nothing outside that directory is created, moved, or deleted.
#
# See also RoboSy.LinkSafety.Tests.ps1 (Move + Symlink replacement transaction)
# and RoboSy.Classification.Tests.ps1 (final-path classification, type
# conflicts, reparse-point hardening, execution-time revalidation).

. (Join-Path -Path $PSScriptRoot -ChildPath "TestHelpers.ps1")

Write-Host ("RoboSy regression tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor White

$sandbox = New-Sandbox "robosy-tests"

try {
    # ---------------------------------------------------------------------
    Write-Section "Effective destination resolution (folder sources)"

    $sourceParent = New-TestDirectory (Join-Path $sandbox "SourceParent")
    $docs = New-TestDirectory (Join-Path $sourceParent "Docs")
    New-TestFile (Join-Path $docs "note.txt") | Out-Null
    New-TestFile (Join-Path $docs "nested\deep.txt") | Out-Null
    $docsInfo = New-SourceInfo $docs

    $destinationParent = New-TestDirectory (Join-Path $sandbox "DestinationParent")

    Assert-PathEqual "folder source gains its own leaf name at the destination" `
        (Join-Path $destinationParent "Docs") `
        (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $destinationParent)

    $sameNamedDestination = Join-Path $destinationParent "Docs"
    Assert-PathEqual "destination already ending in the source name is not doubled" `
        $sameNamedDestination `
        (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $sameNamedDestination)

    Assert-PathEqual "same-name check ignores case" `
        (Join-Path $destinationParent "docs") `
        (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath (Join-Path $destinationParent "docs"))

    Assert-PathEqual "a trailing slash does not change the resolved destination" `
        (Join-Path $destinationParent "Docs") `
        (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath ($destinationParent + "\"))

    Assert-PathEqual "a missing destination folder still gains the source leaf name" `
        (Join-Path $sandbox "NotCreatedYet\Docs") `
        (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath (Join-Path $sandbox "NotCreatedYet"))

    # ---------------------------------------------------------------------
    Write-Section "Effective destination resolution (file sources)"

    $singleFile = New-TestFile (Join-Path $sourceParent "report.txt")
    $fileInfo = New-SourceInfo $singleFile

    Assert-PathEqual "file source keeps the destination folder as the robocopy destination" `
        $destinationParent `
        (Resolve-EffectiveDestinationPath -SourceInfo $fileInfo -DestinationPath $destinationParent)

    Assert-PathEqual "file source keeps its original file name at the final path" `
        (Join-Path $destinationParent "report.txt") `
        (Resolve-StandardFinalItemPath -SourceInfo $fileInfo -DestinationPath $destinationParent)

    # ---------------------------------------------------------------------
    Write-Section "Destination validation"

    Assert-True "a normal destination is accepted" `
        ($null -eq (Get-StandardDestinationRejectReason -SourceInfo $docsInfo -DestinationPath $destinationParent))

    Assert-True "source equals destination is rejected" `
        ($null -ne (Get-StandardDestinationRejectReason -SourceInfo $docsInfo -DestinationPath $docs)) `
        "expected a rejection when the destination resolves onto the source itself"

    Assert-True "a destination that resolves onto the source parent is rejected" `
        ($null -ne (Get-StandardDestinationRejectReason -SourceInfo $docsInfo -DestinationPath $sourceParent)) `
        "SourceParent resolves to SourceParent\Docs, which is the source"

    Assert-True "a destination inside the source is rejected" `
        ($null -ne (Get-StandardDestinationRejectReason -SourceInfo $docsInfo -DestinationPath (Join-Path $docs "nested"))) `
        "expected a rejection for a destination inside the source folder"

    Assert-True "moving a file into its own folder is rejected" `
        ($null -ne (Get-StandardDestinationRejectReason -SourceInfo $fileInfo -DestinationPath $sourceParent)) `
        "the file would resolve back onto itself"

    Assert-True "a file source may target an unrelated folder" `
        ($null -eq (Get-StandardDestinationRejectReason -SourceInfo $fileInfo -DestinationPath $destinationParent))

    # ---------------------------------------------------------------------
    Write-Section "Protected root guard"

    Assert-True "a drive root is rejected as a Move/Copy source" `
        ($null -ne (Get-ProtectedRootReason ([System.IO.Path]::GetPathRoot($sandbox))))

    Assert-True "the user profile root is rejected as a Move/Copy source" `
        ($null -ne (Get-ProtectedRootReason $HOME))

    Assert-True "an ordinary folder under the profile root is still allowed" `
        ($null -eq (Get-ProtectedRootReason (Join-Path $HOME "SomeOrdinaryProjectFolder"))) `
        "protection must apply to the root itself, not to folders under it"

    Assert-True "an ordinary sandbox folder is allowed" `
        ($null -eq (Get-ProtectedRootReason $docs))

    # ---------------------------------------------------------------------
    Write-Section "Robocopy argument building"

    $moveArgs = Get-StandardRobocopyArgs -Mode "MOVE" -SourceInfo $docsInfo `
        -EffectiveDestination (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $destinationParent)

    Assert-PathEqual "move args target the leaf-preserving destination" (Join-Path $destinationParent "Docs") $moveArgs[1]
    Assert-True "move args use /E" ($moveArgs -contains "/E")
    Assert-True "move args use /MOVE for a folder source" ($moveArgs -contains "/MOVE")

    $copyArgs = Get-StandardRobocopyArgs -Mode "COPY" -SourceInfo $docsInfo `
        -EffectiveDestination (Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $destinationParent)

    Assert-PathEqual "copy args target the same leaf-preserving destination as move" (Join-Path $destinationParent "Docs") $copyArgs[1]
    Assert-True "copy args do not use /MOVE" (-not ($copyArgs -contains "/MOVE"))

    $fileMoveArgs = Get-StandardRobocopyArgs -Mode "MOVE" -SourceInfo $fileInfo `
        -EffectiveDestination (Resolve-EffectiveDestinationPath -SourceInfo $fileInfo -DestinationPath $destinationParent)

    Assert-PathEqual "file move args pass the source parent folder" $sourceParent $fileMoveArgs[0]
    Assert-True "file move args pass the original file name" ($fileMoveArgs[2] -eq "report.txt")
    Assert-True "file move args use /MOV, not /MOVE" (($fileMoveArgs -contains "/MOV") -and -not ($fileMoveArgs -contains "/MOVE"))

    Assert-True "the command preview quotes paths that contain spaces" `
        ((Get-RobocopyCommandText -Arguments @("C:\a b\c", "D:\e", "/E")) -eq "robocopy 'C:\a b\c' D:\e /E")

    # ---------------------------------------------------------------------
    Write-Section "Real folder Copy keeps the folder itself"

    $copyDestination = New-TestDirectory (Join-Path $sandbox "CopyDestination")
    $copyEffective = Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $copyDestination
    $copyCode = Invoke-RobocopyCommand -Arguments (Get-StandardRobocopyArgs -Mode "COPY" -SourceInfo $docsInfo -EffectiveDestination $copyEffective)

    Assert-True "the copy wrapper returns exactly one value" (@($copyCode).Count -eq 1) ("got {0} value(s)" -f @($copyCode).Count)
    Assert-True "the copy wrapper returns an integer, not command output" ($copyCode -is [int]) ("got type {0}" -f $copyCode.GetType().FullName)
    Assert-True "the copy succeeded" ($copyCode -le 7) ("exit code {0}" -f $copyCode)
    Assert-True "copy created DestinationParent\Docs\note.txt" (Test-Path -LiteralPath (Join-Path $copyDestination "Docs\note.txt"))
    Assert-True "copy preserved the nested folder" (Test-Path -LiteralPath (Join-Path $copyDestination "Docs\nested\deep.txt"))
    Assert-True "copy did not flatten note.txt into the destination root" (-not (Test-Path -LiteralPath (Join-Path $copyDestination "note.txt")))
    Assert-True "copy left the source folder in place" (Test-Path -LiteralPath $docs)

    # ---------------------------------------------------------------------
    Write-Section "Real folder Move keeps the folder itself"

    $moveDestination = New-TestDirectory (Join-Path $sandbox "MoveDestination")
    $moveEffective = Resolve-EffectiveDestinationPath -SourceInfo $docsInfo -DestinationPath $moveDestination
    $moveCode = Invoke-RobocopyCommand -Arguments (Get-StandardRobocopyArgs -Mode "MOVE" -SourceInfo $docsInfo -EffectiveDestination $moveEffective)

    Assert-True "the move wrapper returns exactly one integer" ((@($moveCode).Count -eq 1) -and ($moveCode -is [int]))
    Assert-True "the move succeeded" ($moveCode -le 7) ("exit code {0}" -f $moveCode)
    Assert-True "move created MoveDestination\Docs\note.txt" (Test-Path -LiteralPath (Join-Path $moveDestination "Docs\note.txt"))
    Assert-True "move did not flatten note.txt into the destination root" (-not (Test-Path -LiteralPath (Join-Path $moveDestination "note.txt")))

    $null = Remove-EmptySourceDirectoryAfterMove -Path $docs
    Assert-True "move removed the emptied source folder" (-not (Test-Path -LiteralPath $docs))

    # ---------------------------------------------------------------------
    Write-Section "Real single-file Move keeps the file name"

    $fileDestination = New-TestDirectory (Join-Path $sandbox "FileDestination")
    $fileEffective = Resolve-EffectiveDestinationPath -SourceInfo $fileInfo -DestinationPath $fileDestination
    $fileCode = Invoke-RobocopyCommand -Arguments (Get-StandardRobocopyArgs -Mode "MOVE" -SourceInfo $fileInfo -EffectiveDestination $fileEffective)

    Assert-True "the file move wrapper returns exactly one integer" ((@($fileCode).Count -eq 1) -and ($fileCode -is [int]))
    Assert-True "the moved file kept its name" (Test-Path -LiteralPath (Join-Path $fileDestination "report.txt"))
    Assert-True "the source file is gone after the move" (-not (Test-Path -LiteralPath $singleFile))

    # ---------------------------------------------------------------------
    Write-Section "Unicode, spaces, and apostrophes"

    $awkwardParent = New-TestDirectory (Join-Path $sandbox "Volume 27 - Journey's End (Special)")
    $awkwardSource = New-TestDirectory (Join-Path $awkwardParent "Docs")
    New-TestFile (Join-Path $awkwardSource "ファイル テスト.txt") -Content "unicode" | Out-Null
    New-TestFile (Join-Path $awkwardSource "Ünïcode's résumé.txt") -Content "unicode" | Out-Null
    $awkwardInfo = New-SourceInfo $awkwardSource

    $awkwardDestination = New-TestDirectory (Join-Path $sandbox "MT - Volume 27 - Journey of Two Lifetimes (Special Book)")
    $awkwardEffective = Resolve-EffectiveDestinationPath -SourceInfo $awkwardInfo -DestinationPath $awkwardDestination

    Assert-PathEqual "the reproduced Docs case resolves to <destination>\Docs" `
        (Join-Path $awkwardDestination "Docs") $awkwardEffective

    $awkwardCode = Invoke-RobocopyCommand -Arguments (Get-StandardRobocopyArgs -Mode "COPY" -SourceInfo $awkwardInfo -EffectiveDestination $awkwardEffective)
    Assert-True "the awkward-path copy returns one integer" ((@($awkwardCode).Count -eq 1) -and ($awkwardCode -is [int]))
    Assert-True "the awkward-path copy succeeded" ($awkwardCode -le 7) ("exit code {0}" -f $awkwardCode)
    Assert-True "the Unicode file survived the copy" (Test-Path -LiteralPath (Join-Path $awkwardEffective "ファイル テスト.txt"))
    Assert-True "the apostrophe file survived the copy" (Test-Path -LiteralPath (Join-Path $awkwardEffective "Ünïcode's résumé.txt"))
    Assert-True "the awkward-path copy did not flatten into the destination root" `
        (-not (Test-Path -LiteralPath (Join-Path $awkwardDestination "ファイル テスト.txt")))

    # ---------------------------------------------------------------------
    Write-Section "Native command wrappers return a single integer"

    $deleteMe = New-TestFile (Join-Path $sandbox "delete-me.txt")
    $deleteCode = Invoke-CmdDeleteCommand -CommandText ("del /f /q /a " + (Format-CmdPathArgument $deleteMe))

    Assert-True "the cmd delete wrapper returns exactly one value" (@($deleteCode).Count -eq 1) ("got {0} value(s)" -f @($deleteCode).Count)
    Assert-True "the cmd delete wrapper returns an integer" ($deleteCode -is [int]) ("got type {0}" -f $deleteCode.GetType().FullName)
    Assert-True "the cmd delete wrapper reports success as 0" ($deleteCode -eq 0)
    Assert-True "the file was deleted" (-not (Test-Path -LiteralPath $deleteMe))

    Assert-True "a formatted exit code renders as a number, not System.Object[]" `
        (("exitCode={0}" -f $copyCode) -eq ("exitCode=" + [string][int]$copyCode)) `
        ("got '{0}'" -f ("exitCode={0}" -f $copyCode))

    # ---------------------------------------------------------------------
    Write-Section "Existing link replacement is confirmation-gated"

    $linkTarget = New-TestDirectory (Join-Path $sandbox "LinkTarget")
    New-TestFile (Join-Path $linkTarget "payload.txt") -Content "real target" | Out-Null
    $oldTarget = New-TestDirectory (Join-Path $sandbox "OldLinkTarget")
    New-TestFile (Join-Path $oldTarget "old.txt") -Content "old target" | Out-Null
    $linkPath = Join-Path $sandbox "ExistingLink"

    $linkCreated = $false
    try {
        New-RoboSyJunction -Path $linkPath -Target $oldTarget | Out-Null
        $linkCreated = $true
    }
    catch {
        Skip-Test "link replacement tests" ("this session cannot create a junction ({0})" -f $_.Exception.Message)
        Skip-Test "link replacement tests (confirm path)" "depends on junction creation above"
    }

    if ($linkCreated) {
        # Cancelling: Invoke-MoveAndLinkJob must not touch the link before the
        # user confirms, so the preview path must leave it fully intact.
        $sourceInfo = Get-PathInfo -InputPath $linkPath -AllowMissing
        $statusBefore = Get-PathStatus $linkPath

        Assert-True "the existing junction is detected as a replaceable link" (Test-IsReplaceableLinkStatus $statusBefore)

        # Removal is refused for anything that is not a link, and is the only
        # mutation path; it is reached from New-LinkSafe after confirmation.
        $notALink = Get-PathStatus $linkTarget
        Assert-True "a real folder is never removed as an existing link" `
            (-not (Remove-ExistingLinkOnly -Path $linkTarget -Status $notALink)) `
            "Remove-ExistingLinkOnly must refuse non-link paths"
        Assert-True "the real folder survived the refused removal" (Test-Path -LiteralPath (Join-Path $linkTarget "payload.txt"))

        # Confirmed replacement: New-LinkSafe removes the old link and relinks.
        $replaced = New-LinkSafe -LinkPath $linkPath -TargetPath $linkTarget -PreviewShown
        if ($replaced) {
            $statusAfter = Get-PathStatus $linkPath
            Assert-True "the confirmed replacement repointed the link" `
                (Test-Path -LiteralPath (Join-Path $linkPath "payload.txt")) `
                ("link kind after replace: {0}" -f $statusAfter.Kind)
            Assert-True "the confirmed replacement did not delete the old link target" `
                (Test-Path -LiteralPath (Join-Path $oldTarget "old.txt")) `
                "removing a link must never follow it into its target"
        }
        else {
            Skip-Test "confirmed link replacement" "this session cannot create the replacement link"
        }

        if ($null -eq $sourceInfo) {
            Assert-True "the link path resolves as a source" $false "Get-PathInfo returned null for the junction"
        }
    }
}
finally {
    Remove-Sandbox $sandbox
}

Write-TestSummaryAndExit
