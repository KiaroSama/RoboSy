# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $PSCommandPath
$shimDir = Join-Path -Path $env:USERPROFILE -ChildPath ".dotnet\tools"
$shimPath = Join-Path -Path $shimDir -ChildPath "RoboSy.cmd"
$currentUserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ([string]::IsNullOrWhiteSpace($currentUserPath)) {
    $entries = @()
}
else {
    $entries = @($currentUserPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$alreadyInstalled = $false
foreach ($entry in $entries) {
    if ([string]::Equals($entry.TrimEnd('\'), $projectDir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        $alreadyInstalled = $true
        break
    }
}

[System.IO.Directory]::CreateDirectory($shimDir) | Out-Null

$shimLines = @(
    "@echo off",
    "setlocal",
    "set ""ROBOSY_TARGET=$projectDir\RoboSy.cmd""",
    "if not exist ""%ROBOSY_TARGET%"" (",
    "    echo RoboSy target was not found: %ROBOSY_TARGET%",
    "    exit /b 1",
    ")",
    "call ""%ROBOSY_TARGET%"" %*",
    "exit /b %errorlevel%"
)
try {
    Set-Content -LiteralPath $shimPath -Value $shimLines -Encoding OEM -ErrorAction Stop
}
catch {
    Set-Content -LiteralPath $shimPath -Value $shimLines -Encoding Default -ErrorAction Stop
}
Write-Host "Installed command shim:" -ForegroundColor Green
Write-Host "  $shimPath" -ForegroundColor Cyan

$shimDirInPath = $false
foreach ($entry in $entries) {
    if ([string]::Equals($entry.TrimEnd('\'), $shimDir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        $shimDirInPath = $true
        break
    }
}

if (-not $alreadyInstalled -or -not $shimDirInPath) {
    if (-not $alreadyInstalled) {
        $entries += $projectDir
    }

    if (-not $shimDirInPath) {
        $entries += $shimDir
    }

    $newPath = ($entries | Select-Object -Unique) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Updated the current user's PATH." -ForegroundColor Green
}
else {
    Write-Host "RoboSy project folder and shim folder are already in the current user's PATH." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Run this in a new terminal, or in the current terminal if .dotnet tools was already on PATH:" -ForegroundColor Gray
Write-Host "  RoboSy" -ForegroundColor Cyan
