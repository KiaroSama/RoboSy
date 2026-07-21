# RoboSy regression tests: Symlink Only (option 5)
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# Covers Resolve-SymlinkOnlyDirection (direction detection from the two entered
# paths) in isolation, plus real interactive end-to-end scenarios for
# Invoke-SymlinkOnlyJob driven through piped stdin: create-only in both
# directions, the both-real and neither-real refusals, cancel, and the
# guarantee that nothing is ever moved.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RoboSy.SymlinkOnly.Tests.ps1
#   pwsh -NoProfile -File .\tests\RoboSy.SymlinkOnly.Tests.ps1

. (Join-Path -Path $PSScriptRoot -ChildPath "TestHelpers.ps1")

Write-Host ("RoboSy symlink-only tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor White

$sandbox = New-Sandbox "robosy-symonly"

try {
    # -----------------------------------------------------------------
    Write-Section "Resolve-SymlinkOnlyDirection: direction detection"

    $dirRoot = New-TestDirectory (Join-Path $sandbox "Direction")
    $realDir = New-TestDirectory (Join-Path $dirRoot "RealFolder")
    New-TestFile (Join-Path $realDir "real.txt") -Content "real" | Out-Null
    $missingPath = Join-Path $dirRoot "MissingSide"

    $realStatus = Get-PathStatus $realDir
    $missingStatus = Get-PathStatus $missingPath

    $dirA = Resolve-SymlinkOnlyDirection -FirstInfo $realStatus -SecondInfo $missingStatus
    Assert-True "real-first / missing-second is resolvable" ($dirA.Decision -eq "OK")
    Assert-PathEqual "the real item becomes the target" $realDir $dirA.TargetInfo.Path
    Assert-PathEqual "the missing side becomes the link" $missingStatus.Path $dirA.LinkInfo.Path

    $dirB = Resolve-SymlinkOnlyDirection -FirstInfo $missingStatus -SecondInfo $realStatus
    Assert-True "missing-first / real-second is resolvable" ($dirB.Decision -eq "OK")
    Assert-PathEqual "direction is order-independent: target is still the real item" $realDir $dirB.TargetInfo.Path
    Assert-PathEqual "direction is order-independent: link is still the missing side" $missingStatus.Path $dirB.LinkInfo.Path

    # Both real is a HANDLED case now (link nested inside Path 2), not a refusal;
    # the resolver just classifies it as BothReal and the job does the rest.
    $secondReal = New-TestDirectory (Join-Path $dirRoot "SecondReal")
    $bothReal = Resolve-SymlinkOnlyDirection -FirstInfo $realStatus -SecondInfo (Get-PathStatus $secondReal)
    Assert-True "two real items classify as BothReal" ($bothReal.Decision -eq "BothReal")

    $secondMissing = Get-PathStatus (Join-Path $dirRoot "AlsoMissing")
    $neither = Resolve-SymlinkOnlyDirection -FirstInfo $missingStatus -SecondInfo $secondMissing
    Assert-True "two missing paths are refused as NeitherReal" ($neither.Decision -eq "NeitherReal")

    # A probe for whether this session can create a junction at all. Every
    # link-creating scenario below is skipped (never silently passed) when it
    # cannot, exactly like the link-safety suite.
    $junctionAvailable = $true
    try {
        $probeTarget = New-TestDirectory (Join-Path $sandbox "probe-target")
        $probeLink = Join-Path $sandbox "probe-link"
        New-RoboSyJunction -Path $probeLink -Target $probeTarget | Out-Null
        [System.IO.Directory]::Delete($probeLink, $false)
    }
    catch {
        $junctionAvailable = $false
    }

    # A reparse point (junction) on one side is NOT a "real item", so it becomes
    # the link side to be replaced, and the plain folder on the other side is the
    # target. This only needs a probe-created junction to exist, so it is gated
    # on junction availability too.
    if ($junctionAvailable) {
        $mixRoot = New-TestDirectory (Join-Path $sandbox "MixReparse")
        $mixReal = New-TestDirectory (Join-Path $mixRoot "RealTarget")
        $mixLinkTargetForJunction = New-TestDirectory (Join-Path $mixRoot "JunctionOldTarget")
        $mixJunction = Join-Path $mixRoot "ExistingJunction"
        New-RoboSyJunction -Path $mixJunction -Target $mixLinkTargetForJunction | Out-Null

        $mixDir = Resolve-SymlinkOnlyDirection -FirstInfo (Get-PathStatus $mixJunction) -SecondInfo (Get-PathStatus $mixReal)
        Assert-True "a junction + a real folder is resolvable" ($mixDir.Decision -eq "OK")
        Assert-PathEqual "the plain folder is the target, not the junction" $mixReal $mixDir.TargetInfo.Path
        Assert-PathEqual "the junction is the (replaceable) link side" $mixJunction $mixDir.LinkInfo.Path

        $mixBoth = Resolve-SymlinkOnlyDirection -FirstInfo (Get-PathStatus $mixJunction) -SecondInfo (Get-PathStatus $mixJunction)
        Assert-True "two reparse points are NeitherReal (no real item to point at)" ($mixBoth.Decision -eq "NeitherReal")
    }
    else {
        Skip-Test "junction is the link side, plain folder is the target" "this session cannot create a junction"
        Skip-Test "two reparse points are NeitherReal" "this session cannot create a junction"
    }

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: refusals never change anything"

    # Neither real -> refused.
    $neitherRoot = New-TestDirectory (Join-Path $sandbox "E2E-Neither")
    $neitherA = Join-Path $neitherRoot "MissingA"
    $neitherB = Join-Path $neitherRoot "MissingB"
    $neitherResult = Invoke-RoboSyInteractive -SandboxRoot $neitherRoot -InputLines @("5", $neitherA, $neitherB, "exit")
    Assert-True "neither-real is refused with a clear message" ($neitherResult.Output -match "Neither path points to a real")
    Assert-True "neither-real created nothing at path A" (-not (Test-Path -LiteralPath $neitherA))
    Assert-True "neither-real created nothing at path B" (-not (Test-Path -LiteralPath $neitherB))

    # Both real but Path 2 is a FILE -> refused (a link cannot be created inside a file).
    $bfRoot = New-TestDirectory (Join-Path $sandbox "E2E-BothFile")
    $bfSource = New-TestDirectory (Join-Path $bfRoot "RealFolder")
    New-TestFile (Join-Path $bfSource "s.txt") -Content "s" | Out-Null
    $bfFile = New-TestFile (Join-Path $bfRoot "Path2File.txt") -Content "path2-file"
    $bfResult = Invoke-RoboSyInteractive -SandboxRoot $bfRoot -InputLines @("5", $bfSource, $bfFile, "exit")
    Assert-True "both-real with a file Path 2 is refused" ($bfResult.Output -match "Path 2 is a file, not a folder")
    Assert-True "both-real-file leaves the Path 2 file untouched" `
        (((Get-Content -LiteralPath $bfFile -Raw).Trim()) -eq "path2-file")
    Assert-True "both-real-file leaves the source untouched" (Test-Path -LiteralPath (Join-Path $bfSource "s.txt"))

    if (-not $junctionAvailable) {
        Skip-Test "all link-creating symlink-only scenarios" "this session cannot create a junction"
        Write-TestSummaryAndExit
    }

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: both paths exist -> link nested inside Path 2, nothing deleted"

    # Path 1 is the real source; Path 2 is a folder. The link is created as
    # <Path 2>\<Path 1 name> -> Path 1, and NOTHING in Path 2 is deleted.
    $bothRoot = New-TestDirectory (Join-Path $sandbox "E2E-BothReal")
    $bothSource = New-TestDirectory (Join-Path $bothRoot "Movie")
    New-TestFile (Join-Path $bothSource "movie.txt") -Content "movie-payload" | Out-Null
    $bothContainer = New-TestDirectory (Join-Path $bothRoot "Links")
    New-TestFile (Join-Path $bothContainer "existing.txt") -Content "keep-me" | Out-Null
    $nestedLink = Join-Path $bothContainer "Movie"

    $bothResult = Invoke-RoboSyInteractive -SandboxRoot $bothRoot -InputLines @("5", $bothSource, $bothContainer, "y", "exit")
    Assert-True "both-real exits cleanly" ($bothResult.ExitCode -eq 0) ("exit code {0}" -f $bothResult.ExitCode)
    Assert-True "both-real reports completion" ($bothResult.Output -match "Symlink-only job completed")
    Assert-True "both-real created the link INSIDE Path 2 as <Path2>\<Path1 name>" ((Get-PathStatus $nestedLink).IsReparsePoint)
    Assert-True "both-real nested link resolves into Path 1" (Test-Path -LiteralPath (Join-Path $nestedLink "movie.txt"))
    Assert-True "both-real left Path 1 (the real source) untouched, not moved" (Test-Path -LiteralPath (Join-Path $bothSource "movie.txt"))
    Assert-True "both-real deleted nothing already inside Path 2" (Test-Path -LiteralPath (Join-Path $bothContainer "existing.txt"))
    Assert-True "both-real Path 1 is still a real folder, not itself a link" (-not (Get-PathStatus $bothSource).IsReparsePoint)

    # Order matters when both exist: swapping the two paths swaps source/container.
    $ordRoot = New-TestDirectory (Join-Path $sandbox "E2E-Order")
    $ordA = New-TestDirectory (Join-Path $ordRoot "Alpha")
    New-TestFile (Join-Path $ordA "a.txt") -Content "alpha" | Out-Null
    $ordB = New-TestDirectory (Join-Path $ordRoot "Beta")
    New-TestFile (Join-Path $ordB "b.txt") -Content "beta" | Out-Null

    $ordResult = Invoke-RoboSyInteractive -SandboxRoot $ordRoot -InputLines @("5", $ordB, $ordA, "y", "exit")
    Assert-True "order matters: reversed run exits cleanly" ($ordResult.ExitCode -eq 0) ("exit code {0}" -f $ordResult.ExitCode)
    Assert-True "order matters: (Beta, Alpha) creates Alpha\Beta -> Beta" ((Get-PathStatus (Join-Path $ordA "Beta")).IsReparsePoint)
    Assert-True "order matters: the reversed link resolves into Beta" (Test-Path -LiteralPath (Join-Path (Join-Path $ordA "Beta") "b.txt"))
    Assert-True "order matters: no link was created the other way (Beta\Alpha)" (-not (Test-Path -LiteralPath (Join-Path $ordB "Alpha")))

    # Both real, but Path 2 already contains a real item with Path 1's name -> refused (no overwrite).
    $colRoot = New-TestDirectory (Join-Path $sandbox "E2E-Collide")
    $colSource = New-TestDirectory (Join-Path $colRoot "Data")
    New-TestFile (Join-Path $colSource "d.txt") -Content "data" | Out-Null
    $colContainer = New-TestDirectory (Join-Path $colRoot "Box")
    $colOccupant = New-TestDirectory (Join-Path $colContainer "Data")
    New-TestFile (Join-Path $colOccupant "occupant.txt") -Content "occupant" | Out-Null

    $colResult = Invoke-RoboSyInteractive -SandboxRoot $colRoot -InputLines @("5", $colSource, $colContainer, "exit")
    Assert-True "collision inside Path 2 is refused" ($colResult.Output -match "already contains a real item named")
    Assert-True "collision left the occupant untouched" (Test-Path -LiteralPath (Join-Path $colOccupant "occupant.txt"))
    Assert-True "collision occupant is still a real folder, not replaced by a link" (-not (Get-PathStatus $colOccupant).IsReparsePoint)

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: create-only, both directions, never moves"

    # Direction 1: real item is path 1, link goes at the missing path 2.
    $d1Root = New-TestDirectory (Join-Path $sandbox "E2E-Dir1")
    $d1Real = New-TestDirectory (Join-Path $d1Root "RealFolder")
    New-TestFile (Join-Path $d1Real "payload.txt") -Content "payload-1" | Out-Null
    $d1Link = Join-Path $d1Root "LinkHere"

    $d1Result = Invoke-RoboSyInteractive -SandboxRoot $d1Root -InputLines @("5", $d1Real, $d1Link, "y", "exit")
    Assert-True "direction 1 exits cleanly" ($d1Result.ExitCode -eq 0) ("exit code {0}" -f $d1Result.ExitCode)
    Assert-True "direction 1 reports completion" ($d1Result.Output -match "Symlink-only job completed")
    Assert-True "direction 1 created a link at the missing side" ((Get-PathStatus $d1Link).IsReparsePoint)
    Assert-True "direction 1 link resolves into the real folder" (Test-Path -LiteralPath (Join-Path $d1Link "payload.txt"))
    Assert-True "direction 1 NEVER moved the real item (it is still at the original path)" `
        (Test-Path -LiteralPath (Join-Path $d1Real "payload.txt"))
    Assert-True "direction 1 real path is still a real folder, not itself a link" `
        (-not (Get-PathStatus $d1Real).IsReparsePoint)
    Assert-True "direction 1 wrote a marker file at the real target" `
        (Test-Path -LiteralPath (Join-Path $d1Real "Symlink path_RealFolder.txt"))

    # Direction 2: real item is path 2, link goes at the missing path 1.
    $d2Root = New-TestDirectory (Join-Path $sandbox "E2E-Dir2")
    $d2Real = New-TestDirectory (Join-Path $d2Root "RealFolder")
    New-TestFile (Join-Path $d2Real "payload.txt") -Content "payload-2" | Out-Null
    $d2Link = Join-Path $d2Root "LinkHere"

    $d2Result = Invoke-RoboSyInteractive -SandboxRoot $d2Root -InputLines @("5", $d2Link, $d2Real, "y", "exit")
    Assert-True "direction 2 exits cleanly" ($d2Result.ExitCode -eq 0) ("exit code {0}" -f $d2Result.ExitCode)
    Assert-True "direction 2 reports completion" ($d2Result.Output -match "Symlink-only job completed")
    Assert-True "direction 2 (reversed order) also creates the link at the missing side" ((Get-PathStatus $d2Link).IsReparsePoint)
    Assert-True "direction 2 link resolves into the real folder" (Test-Path -LiteralPath (Join-Path $d2Link "payload.txt"))
    Assert-True "direction 2 NEVER moved the real item" (Test-Path -LiteralPath (Join-Path $d2Real "payload.txt"))

    # -----------------------------------------------------------------
    Write-Section "Interactive end-to-end: cancelling creates nothing"

    $cancelRoot = New-TestDirectory (Join-Path $sandbox "E2E-Cancel")
    $cancelReal = New-TestDirectory (Join-Path $cancelRoot "RealFolder")
    New-TestFile (Join-Path $cancelReal "payload.txt") -Content "payload-c" | Out-Null
    $cancelLink = Join-Path $cancelRoot "LinkHere"

    $null = Invoke-RoboSyInteractive -SandboxRoot $cancelRoot -InputLines @("5", $cancelReal, $cancelLink, "n", "exit")
    Assert-True "cancelling creates no link" (-not (Test-Path -LiteralPath $cancelLink))
    Assert-True "cancelling leaves the real item untouched" (Test-Path -LiteralPath (Join-Path $cancelReal "payload.txt"))
}
finally {
    Remove-Sandbox $sandbox
}

Write-TestSummaryAndExit
