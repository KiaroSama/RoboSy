# RoboSy parallel test runner
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# Runs every tests/*.Tests.ps1 file concurrently as separate child processes,
# with a bounded, resource-aware worker ceiling and outer wall timeouts. Each
# test FILE stays internally sequential (they have intra-file order dependencies
# and their own $script:Passed counters); only the files run in parallel. Every
# file uses its own unique GUID sandbox (New-Sandbox), so they share no mutable
# fixture, port, database, account, or clipboard and are safe to run at once.
#
# Fail-closed: zero discovered files, any non-zero child exit, a per-file or
# whole-run timeout, or fewer results than discovered files all exit 1.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-RoboSyTests.ps1
#   pwsh -NoProfile -File .\tests\Invoke-RoboSyTests.ps1 -TestHost pwsh
#
# Worker ceiling (first that is set wins): -MaxWorkers, $env:HOOKMAKER_MAX_TEST_WORKERS,
# $env:ROBOSY_MAX_TEST_WORKERS, else max(2, cores-2). Always clamped to
# [1, min(fileCount, 8)] so it never oversubscribes the machine.

[CmdletBinding()]
param(
    [string]$TestHost = $(if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell.exe' }),
    [int]$MaxWorkers = 0,
    [int]$TimeoutSeconds = 300,
    [int]$PerFileTimeoutSeconds = 180,
    [string]$TestsDirectory = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($TestsDirectory)) {
    $TestsDirectory = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
}

# --- Discover suites (fail closed on zero, matching the CI guard) ---
$testFiles = @(Get-ChildItem -Path $TestsDirectory -Filter '*.Tests.ps1' -File | Sort-Object Name)
if ($testFiles.Count -eq 0) {
    Write-Host ("No regression test files were found under: {0}" -f $TestsDirectory) -ForegroundColor Red
    exit 1
}

# --- Resolve the child test host to an absolute path (safe arg passing) ---
$resolvedHost = Get-Command $TestHost -ErrorAction SilentlyContinue
$hostPath = if ($resolvedHost) { $resolvedHost.Source } else { $TestHost }

# --- Worker ceiling: one documented shared cap, clamped and resource-aware ---
$ceiling = $env:HOOKMAKER_MAX_TEST_WORKERS
if ([string]::IsNullOrWhiteSpace($ceiling)) { $ceiling = $env:ROBOSY_MAX_TEST_WORKERS }
if ($MaxWorkers -le 0) {
    $parsed = 0
    if (-not [string]::IsNullOrWhiteSpace($ceiling) -and [int]::TryParse($ceiling, [ref]$parsed) -and $parsed -gt 0) {
        $MaxWorkers = $parsed
    }
    else {
        $MaxWorkers = [Math]::Max(2, [Environment]::ProcessorCount - 2)
    }
}
$MaxWorkers = [Math]::Max(1, [Math]::Min($MaxWorkers, [Math]::Min($testFiles.Count, 8)))

Write-Host ("Discovered {0} regression test file(s); host={1}; workers={2}; wall<={3}s per-file<={4}s" -f `
        $testFiles.Count, [System.IO.Path]::GetFileName($hostPath), $MaxWorkers, $TimeoutSeconds, $PerFileTimeoutSeconds) -ForegroundColor Cyan
$testFiles | ForEach-Object { Write-Host ("  - {0}" -f $_.Name) -ForegroundColor Cyan }

# taskkill /T terminates the whole owned process tree (robocopy / cmd / spawned
# interactive hosts), which killing the parent alone would leave behind on
# Windows. Fully swallows output/errors and no-ops if the process already exited
# (a normal race during cleanup), so it can never abort the run.
function Stop-ProcessTree {
    param([int]$ProcessId)
    try {
        if ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            & taskkill.exe /PID $ProcessId /T /F *> $null
        }
    }
    catch { }
}

# Start one test file as an isolated child process. Uses [Diagnostics.Process]
# (not Start-Process, whose -PassThru object never populates ExitCode) with the
# .Arguments string (ProcessStartInfo.ArgumentList is null under Windows
# PowerShell 5.1). Test paths contain spaces but no embedded quotes, so simple
# double-quote wrapping is safe. stdout/stderr are drained asynchronously so a
# chatty child (hundreds of lines) can never deadlock on a full pipe buffer.
function Start-TestProcess {
    param([System.IO.FileInfo]$File, [string]$HostPath)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $HostPath
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $File.FullName
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Close()   # detached, non-interactive stdin

    return @{
        Proc    = $proc
        File    = $File
        OutTask = $proc.StandardOutput.ReadToEndAsync()
        ErrTask = $proc.StandardError.ReadToEndAsync()
        Sw      = [System.Diagnostics.Stopwatch]::StartNew()
    }
}

$queue = [System.Collections.Generic.Queue[object]]::new()
$testFiles | ForEach-Object { $queue.Enqueue($_) }
$running = @{}
$results = New-Object System.Collections.Generic.List[object]
$overall = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        while ($running.Count -lt $MaxWorkers -and $queue.Count -gt 0) {
            $state = Start-TestProcess -File $queue.Dequeue() -HostPath $hostPath
            $running[$state.Proc.Id] = $state
        }

        Start-Sleep -Milliseconds 200

        foreach ($childId in @($running.Keys)) {
            $state = $running[$childId]
            $proc = $state.Proc

            if ($proc.HasExited) {
                $proc.WaitForExit()   # ensure the async read tasks have reached EOF
                $state.Sw.Stop()
                $out = $state.OutTask.Result
                $err = $state.ErrTask.Result
                $summaryLine = (($out -split "`n") | Where-Object { $_ -match 'Passed:' } | Select-Object -Last 1)
                $results.Add([pscustomobject]@{
                        Name    = $state.File.Name
                        Exit    = $proc.ExitCode
                        Seconds = $state.Sw.Elapsed.TotalSeconds
                        Summary = ([string]$summaryLine).Trim()
                        Output  = $out
                        Error   = $err
                    })
                $running.Remove($childId)
                continue
            }

            # Per-file wall ceiling.
            if ($state.Sw.Elapsed.TotalSeconds -gt $PerFileTimeoutSeconds) {
                Stop-ProcessTree -ProcessId $childId
                $state.Sw.Stop()
                $results.Add([pscustomobject]@{
                        Name    = $state.File.Name
                        Exit    = 124
                        Seconds = $state.Sw.Elapsed.TotalSeconds
                        Summary = ("PER-FILE TIMEOUT (> {0}s)" -f $PerFileTimeoutSeconds)
                        Output  = ''
                        Error   = ''
                    })
                $running.Remove($childId)
            }
        }

        # Whole-run wall ceiling.
        if ($overall.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
            foreach ($childId in @($running.Keys)) {
                Stop-ProcessTree -ProcessId $childId
                $state = $running[$childId]
                $state.Sw.Stop()
                $results.Add([pscustomobject]@{
                        Name    = $state.File.Name
                        Exit    = 124
                        Seconds = $state.Sw.Elapsed.TotalSeconds
                        Summary = ("WALL TIMEOUT (run exceeded {0}s)" -f $TimeoutSeconds)
                        Output  = ''
                        Error   = ''
                    })
                $running.Remove($childId)
            }
            break
        }
    }
}
finally {
    foreach ($childId in @($running.Keys)) { Stop-ProcessTree -ProcessId $childId }
}
$overall.Stop()

# --- Report ---
Write-Host ''
$anyFail = $false
foreach ($r in ($results | Sort-Object Name)) {
    $color = if ($r.Exit -eq 0) { 'Green' } else { 'Red' }
    Write-Host ("  {0,-38} {1,7:N1}s  exit={2}  {3}" -f $r.Name, $r.Seconds, $r.Exit, $r.Summary) -ForegroundColor $color
    if ($r.Exit -ne 0) {
        $anyFail = $true
        if (-not [string]::IsNullOrWhiteSpace($r.Output)) { Write-Host $r.Output }
        if (-not [string]::IsNullOrWhiteSpace($r.Error)) { Write-Host $r.Error -ForegroundColor Red }
    }
}
Write-Host ''
Write-Host ("Total: {0} file(s) in {1:N1}s (workers={2}, host={3})" -f `
        $results.Count, $overall.Elapsed.TotalSeconds, $MaxWorkers, [System.IO.Path]::GetFileName($hostPath)) `
    -ForegroundColor $(if ($anyFail) { 'Red' } else { 'Green' })

# Coverage guard: every discovered suite must have produced a result.
if ($results.Count -ne $testFiles.Count) {
    Write-Host ("Coverage error: discovered {0} suite(s) but recorded {1} result(s)." -f $testFiles.Count, $results.Count) -ForegroundColor Red
    exit 1
}
if ($anyFail) { exit 1 }
exit 0
