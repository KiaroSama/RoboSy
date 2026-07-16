# RoboSy regression tests: rollback-safe Move + Symlink replacement transaction
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# Covers Get-LinkReplacementSnapshot, Test-LinkReplacementSnapshotUnchanged,
# Restore-PreviousLink, and Invoke-SafeLinkReplacement, plus real interactive
# cancel/confirm scenarios for Invoke-MoveAndLinkJob driven through piped
# stdin (a genuine end-to-end exercise of the control flow, not a mock).
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RoboSy.LinkSafety.Tests.ps1
#   pwsh -NoProfile -File .\tests\RoboSy.LinkSafety.Tests.ps1

. (Join-Path -Path $PSScriptRoot -ChildPath "TestHelpers.ps1")

Write-Host ("RoboSy link-safety tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor White

$sandbox = New-Sandbox "robosy-linksafety"

# A junction is used for every scenario below because it does not require
# Administrator rights or Developer Mode, unlike a directory symbolic link -
# this keeps the suite runnable on ordinary CI runners. Scenarios that
# genuinely cannot run in this session (junction creation refused) are
# skipped, never silently passed.
function New-JunctionFixture {
    param([string]$Root)

    $oldTarget = New-TestDirectory (Join-Path $Root "OldTarget")
    New-TestFile (Join-Path $oldTarget "old.txt") -Content "old target" | Out-Null
    $newTarget = New-TestDirectory (Join-Path $Root "NewTarget")
    New-TestFile (Join-Path $newTarget "new.txt") -Content "new target" | Out-Null
    $linkPath = Join-Path $Root "MyLink"

    New-RoboSyJunction -Path $linkPath -Target $oldTarget | Out-Null

    return @{
        LinkPath  = $linkPath
        OldTarget = $oldTarget
        NewTarget = $newTarget
    }
}

try {
    $junctionAvailable = $true
    try {
        $probeRoot = New-TestDirectory (Join-Path $sandbox "probe")
        $null = New-JunctionFixture -Root $probeRoot
        Remove-Item -LiteralPath $probeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        $junctionAvailable = $false
    }

    if (-not $junctionAvailable) {
        Skip-Test "all link-safety scenarios" "this session cannot create a junction"
        Write-TestSummaryAndExit
    }

    # -----------------------------------------------------------------
    Write-Section "Get-LinkReplacementSnapshot / Test-LinkReplacementSnapshotUnchanged"

    $unitRoot = New-TestDirectory (Join-Path $sandbox "Unit")
    $fixture = New-JunctionFixture -Root $unitRoot

    $snapshot = Get-LinkReplacementSnapshot -LinkPath $fixture.LinkPath -NewTargetPath $fixture.NewTarget
    Assert-True "snapshot detects the existing junction as replaceable" $snapshot.IsReplaceableLink
    Assert-True "an unchanged snapshot reports unchanged" (Test-LinkReplacementSnapshotUnchanged -Snapshot $snapshot)

    # Case: the new target disappears after preview but before execution.
    $vanishingRoot = New-TestDirectory (Join-Path $sandbox "Vanishing")
    $vanishingFixture = New-JunctionFixture -Root $vanishingRoot
    $vanishingSnapshot = Get-LinkReplacementSnapshot -LinkPath $vanishingFixture.LinkPath -NewTargetPath $vanishingFixture.NewTarget
    Remove-Item -LiteralPath $vanishingFixture.NewTarget -Recurse -Force
    Assert-True "a vanished new target is detected as changed" `
        (-not (Test-LinkReplacementSnapshotUnchanged -Snapshot $vanishingSnapshot))
    Assert-True "the old link was never removed after detecting the vanished target" `
        (Test-IsReplaceableLinkStatus (Get-PathStatus $vanishingFixture.LinkPath))

    # Case: the original link changes (repointed) after preview.
    $changedRoot = New-TestDirectory (Join-Path $sandbox "Changed")
    $changedFixture = New-JunctionFixture -Root $changedRoot
    $changedSnapshot = Get-LinkReplacementSnapshot -LinkPath $changedFixture.LinkPath -NewTargetPath $changedFixture.NewTarget
    $otherTarget = New-TestDirectory (Join-Path $changedRoot "OtherTarget")
    # Windows PowerShell 5.1's Remove-Item throws a spurious
    # NullReferenceException on some junctions; [IO.Directory]::Delete is the
    # same non-recursive removal Remove-ExistingLinkOnly itself uses.
    [System.IO.Directory]::Delete($changedFixture.LinkPath, $false)
    New-RoboSyJunction -Path $changedFixture.LinkPath -Target $otherTarget | Out-Null
    Assert-True "a repointed original link is detected as changed" `
        (-not (Test-LinkReplacementSnapshotUnchanged -Snapshot $changedSnapshot))

    # -----------------------------------------------------------------
    Write-Section "Invoke-SafeLinkReplacement: confirmed success"

    $successRoot = New-TestDirectory (Join-Path $sandbox "Success")
    $successFixture = New-JunctionFixture -Root $successRoot
    $successSnapshot = Get-LinkReplacementSnapshot -LinkPath $successFixture.LinkPath -NewTargetPath $successFixture.NewTarget
    $successResult = Invoke-SafeLinkReplacement -Snapshot $successSnapshot -PreviewShown

    Assert-True "a normal replacement reports success" $successResult
    Assert-True "the link now resolves into the new target" (Test-Path -LiteralPath (Join-Path $successFixture.LinkPath "new.txt"))
    Assert-True "the old target survived the replacement" (Test-Path -LiteralPath (Join-Path $successFixture.OldTarget "old.txt"))

    # -----------------------------------------------------------------
    Write-Section "Invoke-SafeLinkReplacement: forced creation failure triggers rollback"

    $rollbackRoot = New-TestDirectory (Join-Path $sandbox "Rollback")
    $rollbackFixture = New-JunctionFixture -Root $rollbackRoot
    $rollbackSnapshot = Get-LinkReplacementSnapshot -LinkPath $rollbackFixture.LinkPath -NewTargetPath $rollbackFixture.NewTarget

    # Force the replacement link's creation to fail deterministically,
    # regardless of the session's symlink/junction privilege, by removing the
    # new target after the snapshot was captured (New-LinkSafe requires the
    # target to exist).
    Remove-Item -LiteralPath $rollbackFixture.NewTarget -Recurse -Force

    $rollbackResult = Invoke-SafeLinkReplacement -Snapshot $rollbackSnapshot -PreviewShown

    Assert-True "a forced creation failure is reported as failure, never success" (-not $rollbackResult)
    $rollbackStatus = Get-PathStatus $rollbackFixture.LinkPath
    Assert-True "rollback restored the original junction" (Test-IsReplaceableLinkStatus $rollbackStatus)
    Assert-True "the restored link still resolves into the original old target" `
        (Test-Path -LiteralPath (Join-Path $rollbackFixture.LinkPath "old.txt"))
    Assert-True "the old target was never touched by the failed replacement" `
        (Test-Path -LiteralPath (Join-Path $rollbackFixture.OldTarget "old.txt"))

    # -----------------------------------------------------------------
    Write-Section "Restore-PreviousLink: forced rollback failure is reported, not hidden"

    $blockedRoot = New-TestDirectory (Join-Path $sandbox "Blocked")
    $blockedFixture = New-JunctionFixture -Root $blockedRoot
    $blockedSnapshot = Get-LinkReplacementSnapshot -LinkPath $blockedFixture.LinkPath -NewTargetPath $blockedFixture.NewTarget

    # Simulate "the old link was already removed, and something else now
    # occupies that path" - the one scenario where restoring the previous
    # link itself must fail.
    [System.IO.Directory]::Delete($blockedFixture.LinkPath, $false)
    New-TestFile -Path $blockedFixture.LinkPath -Content "unexpected occupant" | Out-Null

    $restoreResult = Restore-PreviousLink -Snapshot $blockedSnapshot
    Assert-True "rollback reports failure when the link path is occupied by another real item" (-not $restoreResult)
    Assert-True "the unexpected occupant was not silently removed by the failed rollback" `
        ((Get-PathStatus $blockedFixture.LinkPath).Type -eq "File")

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: cancelling never touches the existing link"

    foreach ($cancelInput in @("n", "exit", "quit")) {
        $caseRoot = New-TestDirectory (Join-Path $sandbox ("Cancel-" + $cancelInput))
        $caseFixture = New-JunctionFixture -Root $caseRoot

        $null = Invoke-RoboSyInteractive -SandboxRoot $caseRoot -InputLines @("4", $caseFixture.LinkPath, $caseFixture.NewTarget, $cancelInput, "exit")

        $afterStatus = Get-PathStatus $caseFixture.LinkPath
        Assert-True ("cancelling with '{0}' leaves the link as a replaceable link" -f $cancelInput) (Test-IsReplaceableLinkStatus $afterStatus)
        Assert-True ("cancelling with '{0}' leaves the link pointing at the original target" -f $cancelInput) `
            (Test-Path -LiteralPath (Join-Path $caseFixture.LinkPath "old.txt"))
        Assert-True ("cancelling with '{0}' leaves the new target untouched" -f $cancelInput) `
            (Test-Path -LiteralPath (Join-Path $caseFixture.NewTarget "new.txt"))
    }

    # "0" (back) returns to the destination prompt instead of quitting, so it
    # needs one more line (re-entering the target) before exiting.
    $backRoot = New-TestDirectory (Join-Path $sandbox "Cancel-0")
    $backFixture = New-JunctionFixture -Root $backRoot
    $null = Invoke-RoboSyInteractive -SandboxRoot $backRoot -InputLines @("4", $backFixture.LinkPath, $backFixture.NewTarget, "0", "exit")
    $backStatus = Get-PathStatus $backFixture.LinkPath
    Assert-True "answering '0' leaves the link as a replaceable link" (Test-IsReplaceableLinkStatus $backStatus)
    Assert-True "answering '0' leaves the link pointing at the original target" `
        (Test-Path -LiteralPath (Join-Path $backFixture.LinkPath "old.txt"))

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: confirmed replacement"

    $confirmRoot = New-TestDirectory (Join-Path $sandbox "Confirm")
    $confirmFixture = New-JunctionFixture -Root $confirmRoot
    $confirmResult = Invoke-RoboSyInteractive -SandboxRoot $confirmRoot -InputLines @("4", $confirmFixture.LinkPath, $confirmFixture.NewTarget, "y", "exit")

    Assert-True "the interactive process exited cleanly" ($confirmResult.ExitCode -eq 0) ("exit code {0}" -f $confirmResult.ExitCode)
    Assert-True "confirmed replacement reports completion in the console output" `
        ($confirmResult.Output -match "Move \+ symbolic link job completed")
    Assert-True "confirmed replacement repointed the link to the new target" `
        (Test-Path -LiteralPath (Join-Path $confirmFixture.LinkPath "new.txt"))
    Assert-True "confirmed replacement left the old target untouched" `
        (Test-Path -LiteralPath (Join-Path $confirmFixture.OldTarget "old.txt"))
}
finally {
    Remove-Sandbox $sandbox
}

Write-TestSummaryAndExit
