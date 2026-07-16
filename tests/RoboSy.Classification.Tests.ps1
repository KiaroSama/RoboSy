# RoboSy regression tests: final-path classification, type conflicts,
# destination reparse-point hardening, and execution-time revalidation.
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RoboSy.Classification.Tests.ps1
#   pwsh -NoProfile -File .\tests\RoboSy.Classification.Tests.ps1

. (Join-Path -Path $PSScriptRoot -ChildPath "TestHelpers.ps1")

Write-Host ("RoboSy classification tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor White

$sandbox = New-Sandbox "robosy-classification"

try {
    # -----------------------------------------------------------------
    Write-Section "Classification: create / reuse / merge / overwrite"

    $sourceRoot = New-TestDirectory (Join-Path $sandbox "Source")
    $folderSource = New-TestDirectory (Join-Path $sourceRoot "Docs")
    New-TestFile (Join-Path $folderSource "a.txt") | Out-Null
    $folderSourceInfo = New-SourceInfo $folderSource

    $fileSource = New-TestFile (Join-Path $sourceRoot "report.txt")
    $fileSourceInfo = New-SourceInfo $fileSource

    $emptyDestParent = New-TestDirectory (Join-Path $sandbox "EmptyDestParent")
    $createClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $emptyDestParent
    Assert-True "a missing final path classifies as CreateDirectory for a folder source" ($createClassification.Classification -eq "CreateDirectory")
    Assert-True "CreateDirectory does not require confirmation" (-not $createClassification.RequiresConfirmation)

    $fileCreateClassification = Get-StandardFinalPathClassification -SourceInfo $fileSourceInfo -DestinationPath $emptyDestParent
    Assert-True "a missing final path classifies as CreateFile for a file source" ($fileCreateClassification.Classification -eq "CreateFile")

    $emptyFinalParent = New-TestDirectory (Join-Path $sandbox "ReuseParent")
    New-TestDirectory (Join-Path $emptyFinalParent "Docs") | Out-Null
    $reuseClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $emptyFinalParent
    Assert-True "an existing empty folder classifies as ReuseEmptyDirectory" ($reuseClassification.Classification -eq "ReuseEmptyDirectory")
    Assert-True "ReuseEmptyDirectory does not require confirmation" (-not $reuseClassification.RequiresConfirmation)

    $mergeParent = New-TestDirectory (Join-Path $sandbox "MergeParent")
    $mergeFinal = New-TestDirectory (Join-Path $mergeParent "Docs")
    New-TestFile (Join-Path $mergeFinal "existing.txt") | Out-Null
    $mergeClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $mergeParent
    Assert-True "a non-empty existing folder classifies as MergeDirectory" ($mergeClassification.Classification -eq "MergeDirectory")
    Assert-True "MergeDirectory requires confirmation" $mergeClassification.RequiresConfirmation
    Assert-True "MergeDirectory reports the existing item count" ($mergeClassification.ExistingItemCount -eq 1)

    $overwriteParent = New-TestDirectory (Join-Path $sandbox "OverwriteParent")
    New-TestFile (Join-Path $overwriteParent "report.txt") -Content "existing" | Out-Null
    $overwriteClassification = Get-StandardFinalPathClassification -SourceInfo $fileSourceInfo -DestinationPath $overwriteParent
    Assert-True "an existing file for a file source classifies as OverwriteFile" ($overwriteClassification.Classification -eq "OverwriteFile")
    Assert-True "OverwriteFile requires confirmation" $overwriteClassification.RequiresConfirmation

    # -----------------------------------------------------------------
    Write-Section "Classification: type conflicts are blocked, never merged"

    $dirOntoFileParent = New-TestDirectory (Join-Path $sandbox "DirOntoFileParent")
    New-TestFile (Join-Path $dirOntoFileParent "Docs") -Content "this is a file named Docs" | Out-Null
    $dirOntoFileClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $dirOntoFileParent
    Assert-True "a folder onto an existing file is classified as a type conflict" ($dirOntoFileClassification.Classification -eq "TypeConflictDirectoryOntoFile")
    Assert-True "the directory-onto-file conflict carries a block reason" (-not [string]::IsNullOrWhiteSpace($dirOntoFileClassification.BlockReason))
    Assert-True "the directory-onto-file conflict does not merely require confirmation" (-not $dirOntoFileClassification.RequiresConfirmation)

    $fileOntoDirParent = New-TestDirectory (Join-Path $sandbox "FileOntoDirParent")
    New-TestDirectory (Join-Path $fileOntoDirParent "report.txt") | Out-Null
    $fileOntoDirClassification = Get-StandardFinalPathClassification -SourceInfo $fileSourceInfo -DestinationPath $fileOntoDirParent
    Assert-True "a file onto an existing folder is classified as a type conflict" ($fileOntoDirClassification.Classification -eq "TypeConflictFileOntoDirectory")
    Assert-True "the file-onto-directory conflict carries a block reason" (-not [string]::IsNullOrWhiteSpace($fileOntoDirClassification.BlockReason))

    # -----------------------------------------------------------------
    Write-Section "Classification: unsupported reparse-point destinations are blocked"

    $reparseParent = New-TestDirectory (Join-Path $sandbox "ReparseParent")
    $linkedAway = New-TestDirectory (Join-Path $sandbox "LinkedAway")
    $reparseJunctionAvailable = $true
    $linkedFinal = Join-Path $reparseParent "Docs"
    try {
        New-RoboSyJunction -Path $linkedFinal -Target $linkedAway | Out-Null
    }
    catch {
        $reparseJunctionAvailable = $false
    }

    if ($reparseJunctionAvailable) {
        $reparseClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $reparseParent
        Assert-True "a junction sitting at the final path is classified as UnsupportedReparsePoint" ($reparseClassification.Classification -eq "UnsupportedReparsePoint")
        Assert-True "the reparse-point block carries a block reason" (-not [string]::IsNullOrWhiteSpace($reparseClassification.BlockReason))

        # /XJ only protects nested junctions found while recursing; it must not
        # be treated as making a linked destination argument itself safe.
        $destinationIsJunctionClassification = Get-StandardFinalPathClassification -SourceInfo $fileSourceInfo -DestinationPath $linkedFinal
        Assert-True "a destination argument that is itself a junction is blocked regardless of /XJ" `
            ($destinationIsJunctionClassification.Classification -eq "UnsupportedReparsePoint")
    }
    else {
        Skip-Test "reparse-point destination blocking" "this session cannot create a junction"
        Skip-Test "destination-argument-is-a-junction blocking" "this session cannot create a junction"
    }

    # -----------------------------------------------------------------
    Write-Section "Classification: stability and drift detection between preview and execution"

    $stableParent = New-TestDirectory (Join-Path $sandbox "StableParent")
    $previewClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $stableParent
    $reCheckClassification = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $stableParent
    Assert-True "an unchanged destination reclassifies identically" ($reCheckClassification.Classification -eq $previewClassification.Classification)
    Assert-PathEqual "an unchanged effective destination stays stable" $previewClassification.EffectiveDestination $reCheckClassification.EffectiveDestination
    Assert-PathEqual "an unchanged final item path stays stable" $previewClassification.FinalItemPath $reCheckClassification.FinalItemPath

    # Race: an item appears at the final path after the preview was shown.
    $appearsParent = New-TestDirectory (Join-Path $sandbox "AppearsParent")
    $appearsPreview = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $appearsParent
    New-TestFile (Join-Path $appearsParent "Docs") -Content "appeared after preview" | Out-Null
    $appearsExecution = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $appearsParent
    Assert-True "a final path that appears after preview changes classification" ($appearsExecution.Classification -ne $appearsPreview.Classification)
    Assert-True "the newly appeared item is recognized as a type conflict" ($appearsExecution.Classification -eq "TypeConflictDirectoryOntoFile")

    # Race: the final path changes type (folder -> file) after being confirmed
    # as a MergeDirectory.
    $mutateParent = New-TestDirectory (Join-Path $sandbox "MutateParent")
    New-TestDirectory (Join-Path $mutateParent "Docs") | Out-Null
    New-TestFile (Join-Path $mutateParent "Docs\existing.txt") | Out-Null
    $mutatePreview = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $mutateParent
    Assert-True "the pre-mutation classification is MergeDirectory" ($mutatePreview.Classification -eq "MergeDirectory")
    Remove-Item -LiteralPath (Join-Path $mutateParent "Docs") -Recurse -Force
    New-TestFile (Join-Path $mutateParent "Docs") -Content "now a file" | Out-Null
    $mutateExecution = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $mutateParent
    Assert-True "a MergeDirectory that turned into a file is detected at execution time" `
        ($mutateExecution.Classification -ne $mutatePreview.Classification -and $mutateExecution.Classification -eq "TypeConflictDirectoryOntoFile")

    # Race: the destination becomes a reparse point after preview.
    if ($reparseJunctionAvailable) {
        $becomesLinkParent = New-TestDirectory (Join-Path $sandbox "BecomesLinkParent")
        $becomesLinkPreview = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $becomesLinkParent
        Assert-True "the pre-mutation classification is a normal create" ($becomesLinkPreview.Classification -eq "CreateDirectory")
        New-RoboSyJunction -Path (Join-Path $becomesLinkParent "Docs") -Target $linkedAway | Out-Null
        $becomesLinkExecution = Get-StandardFinalPathClassification -SourceInfo $folderSourceInfo -DestinationPath $becomesLinkParent
        Assert-True "a destination that becomes a reparse point after preview is blocked at execution time" `
            ($becomesLinkExecution.Classification -eq "UnsupportedReparsePoint")
    }
    else {
        Skip-Test "destination-becomes-reparse-point race detection" "this session cannot create a junction"
    }

    # -----------------------------------------------------------------
    Write-Section "End-to-end: a blocked type conflict never invokes robocopy"

    $e2eParent = New-TestDirectory (Join-Path $sandbox "E2E-TypeConflict")
    $e2eSource = New-TestDirectory (Join-Path $e2eParent "Src\Docs")
    New-TestFile (Join-Path $e2eSource "payload.txt") -Content "should never move" | Out-Null
    $e2eDestParent = New-TestDirectory (Join-Path $e2eParent "Dest")
    $conflictingFile = New-TestFile (Join-Path $e2eDestParent "Docs") -Content "blocks the folder transfer"

    $e2eResult = Invoke-RoboSyInteractive -SandboxRoot $e2eParent -InputLines @("1", $e2eSource, $e2eDestParent, "exit")

    Assert-True "the blocked job reports the type conflict to the console" `
        ($e2eResult.Output -match "cannot be transferred onto an existing file")
    Assert-True "robocopy was never invoked for the blocked type conflict" `
        ($e2eResult.Output -notmatch "Robocopy command:")
    Assert-True "the conflicting destination file was left completely untouched" `
        ((Get-Content -LiteralPath $conflictingFile -Raw) -match "blocks the folder transfer")
    Assert-True "the source folder was never moved or deleted" (Test-Path -LiteralPath (Join-Path $e2eSource "payload.txt"))
}
finally {
    Remove-Sandbox $sandbox
}

Write-TestSummaryAndExit
