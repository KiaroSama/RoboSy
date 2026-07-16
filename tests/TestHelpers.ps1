# Shared test infrastructure for the RoboSy.*.Tests.ps1 files.
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# Dot-source this file first in every test file. It dot-sources RoboSy.ps1
# itself (via the ROBOSY_LIB_ONLY hook) and defines common assertion helpers,
# disposable-sandbox helpers, and the interactive end-to-end process harness
# used to exercise real menu/prompt flows via piped stdin.

$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0
$script:Skipped = 0

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ""
    )

    if ($Condition) {
        $script:Passed++
        Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green
        return
    }

    $script:Failed++
    Write-Host ("  FAIL  {0}" -f $Name) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        Write-Host ("        {0}" -f $Detail) -ForegroundColor Yellow
    }
}

function Skip-Test {
    param(
        [string]$Name,
        [string]$Reason
    )

    $script:Skipped++
    Write-Host ("  SKIP  {0}: {1}" -f $Name, $Reason) -ForegroundColor Yellow
}

function Assert-PathEqual {
    param(
        [string]$Name,
        [AllowNull()][string]$Expected,
        [AllowNull()][string]$Actual
    )

    $expectedNormalized = Normalize-PathForCompare $Expected
    $actualNormalized = Normalize-PathForCompare $Actual
    $ok = [string]::Equals($expectedNormalized, $actualNormalized, [StringComparison]::OrdinalIgnoreCase)
    Assert-True $Name $ok ("expected '{0}' but got '{1}'" -f $expectedNormalized, $actualNormalized)
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
}

function New-TestDirectory {
    param([string]$Path)
    [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    return $Path
}

function New-TestFile {
    param([string]$Path, [string]$Content = "robosy test")
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    return $Path
}

# Builds the SourceInfo hashtable shape that RoboSy's own prompts produce.
function New-SourceInfo {
    param([string]$Path)

    $info = Get-PathInfo -InputPath $Path
    if ($null -eq $info) {
        throw "Test setup error: source path does not exist: $Path"
    }
    return $info
}

function New-Sandbox {
    param([string]$Prefix = "robosy-tests")
    $sandbox = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("{0}-{1}" -f $Prefix, [Guid]::NewGuid().ToString("N"))
    New-TestDirectory $sandbox | Out-Null
    return $sandbox
}

function Remove-Sandbox {
    param([string]$Path)
    if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path)) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-TestSummaryAndExit {
    Write-Host ""
    Write-Host ("Passed: {0}  Failed: {1}  Skipped: {2}" -f $script:Passed, $script:Failed, $script:Skipped) `
        -ForegroundColor $(if ($script:Failed -gt 0) { "Red" } else { "Green" })

    if ($script:Failed -gt 0) {
        exit 1
    }

    exit 0
}

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:RoboSyScriptPath = Join-Path -Path $script:RepoRoot -ChildPath "RoboSy.ps1"

if (-not (Test-Path -LiteralPath $script:RoboSyScriptPath)) {
    throw "RoboSy.ps1 was not found next to the tests directory: $($script:RoboSyScriptPath)"
}

$env:ROBOSY_LIB_ONLY = "1"
. $script:RoboSyScriptPath
$env:ROBOSY_LIB_ONLY = $null

# Executable used for real interactive (piped-stdin) end-to-end scenarios.
# Matches whichever PowerShell host is currently running the test file, so a
# CI run under Windows PowerShell 5.1 also drives the interactive flow under
# 5.1, and a run under PowerShell 7 drives it under 7.
$script:InteractiveExe = if ($PSVersionTable.PSEdition -eq "Core") {
    (Get-Command pwsh -ErrorAction SilentlyContinue).Source
}
else {
    (Get-Command powershell.exe -ErrorAction SilentlyContinue).Source
}
if ([string]::IsNullOrWhiteSpace($script:InteractiveExe)) {
    $script:InteractiveExe = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell.exe" }
}

# Runs RoboSy.ps1 as a real interactive subprocess with piped stdin, from a
# disposable copy so its own log directory resolves under $SandboxRoot instead
# of the real repository. [Console]::IsInputRedirected is true for piped
# stdin, so RoboSy's own Read-Host based input path handles it exactly like a
# real terminal session that stays in control of every step. Returns the
# combined console output and the process exit code.
function Invoke-RoboSyInteractive {
    param(
        [string]$SandboxRoot,
        [string[]]$InputLines
    )

    $scriptCopy = Join-Path -Path $SandboxRoot -ChildPath ("RoboSy-{0}.ps1" -f ([Guid]::NewGuid().ToString("N")))
    Copy-Item -LiteralPath $script:RoboSyScriptPath -Destination $scriptCopy -Force

    $stdin = ($InputLines -join "`n") + "`n"

    try {
        $output = $stdin | & $script:InteractiveExe -NoProfile -ExecutionPolicy Bypass -File $scriptCopy 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        Remove-Item -LiteralPath $scriptCopy -Force -ErrorAction SilentlyContinue
    }

    return @{
        Output   = ($output | Out-String)
        ExitCode = $exitCode
    }
}
