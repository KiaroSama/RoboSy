# RoboSy regression tests: Read-ConsoleText orchestration and the
# Read-HostUiLine host-line-reader fallback chain.
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
#
# $Host is a read-only automatic variable, so it cannot be swapped to test
# Read-HostUiLine's fallback behavior. Instead Read-HostUiLine accepts an
# optional -HostUi parameter (defaulting to the real $Host.UI in production);
# these tests pass fake stand-ins defined below as real PowerShell classes
# (FakeSuccessHostUi, FakeNotImplementedHostUi, FakeOtherFailureHostUi) to
# force each branch deterministically. A PSCustomObject + ScriptMethod was
# tried first and rejected: PowerShell wraps an exception thrown from a
# ScriptMethod in MethodInvocationException/RuntimeException (verified
# directly), which a real compiled PSHostUserInterface override would not do,
# so `catch [System.NotImplementedException]` in Read-HostUiLine would not
# have matched it. A class method throws its exception unwrapped, matching
# real host behavior. Read-ConsoleText's own orchestration (call count,
# passthrough, admin re-prompt, no double prompt) is tested the same way
# every other test file mocks RoboSy helpers: by redefining the functions it
# calls (Read-HostUiLine, Test-ConsoleInputIsRedirected, Write-ConsolePrompt,
# Invoke-AdminSwitch) in this process's own scope, since PowerShell resolves
# unqualified function calls dynamically at call time.
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\RoboSy.Input.Tests.ps1
#   pwsh -NoProfile -File .\tests\RoboSy.Input.Tests.ps1

. (Join-Path -Path $PSScriptRoot -ChildPath "TestHelpers.ps1")

Write-Host ("RoboSy input tests (PowerShell {0})" -f $PSVersionTable.PSVersion) -ForegroundColor White

# Fake $Host.UI stand-ins for Read-HostUiLine's -HostUi parameter. These use
# real PowerShell classes rather than a PSCustomObject + ScriptMethod: a
# ScriptMethod that throws gets wrapped by PowerShell in a
# MethodInvocationException (verified directly - the original exception ends
# up two levels deep as .InnerException.InnerException), which a real
# compiled PSHostUserInterface override would not do. A class method throws
# its exception unwrapped, faithfully matching real host behavior, so
# `catch [System.NotImplementedException]` in Read-HostUiLine sees the same
# exception type a real host would produce.
class FakeSuccessHostUi {
    [string]$ReturnValue
    FakeSuccessHostUi([string]$value) { $this.ReturnValue = $value }
    [string] ReadLine() { return $this.ReturnValue }
}

class FakeNotImplementedHostUi {
    [string] ReadLine() { throw [System.NotImplementedException]::new("test-forced: ReadLine not implemented") }
}

class FakeOtherFailureHostUi {
    [string] ReadLine() { throw [System.InvalidOperationException]::new("test-forced: unrelated failure") }
}

try {
    # This section runs FIRST and calls the real, un-mocked Read-HostUiLine -
    # every later section redefines Read-HostUiLine for its own purposes, and
    # that redefinition persists for the rest of the process.
    # -----------------------------------------------------------------
    Write-Section "Read-HostUiLine: fallback chain in isolation"

    $successUi = [FakeSuccessHostUi]::new("direct-success")
    $successResult = Read-HostUiLine -HostUi $successUi
    Assert-True "a working host UI returns its value directly" ($successResult -eq "direct-success")
    Assert-True "the direct-success path returns a single scalar string" (($successResult -is [string]) -and (@($successResult).Count -eq 1))

    function Read-ConsoleFallbackLine { return "fallback-value" }

    $nullUiResult = Read-HostUiLine -HostUi $null
    Assert-True "a null host UI falls back to Read-ConsoleFallbackLine" ($nullUiResult -eq "fallback-value")

    $notImplementedUi = [FakeNotImplementedHostUi]::new()
    $notImplementedResult = Read-HostUiLine -HostUi $notImplementedUi
    Assert-True "NotImplementedException from the host UI falls back to Read-ConsoleFallbackLine" ($notImplementedResult -eq "fallback-value")

    function Read-ConsoleFallbackLine { return "ファイル テスト résumé" }
    $unicodeFallback = Read-HostUiLine -HostUi $null
    Assert-True "the fallback path returns Unicode text intact" ($unicodeFallback -ceq "ファイル テスト résumé")

    function Read-ConsoleFallbackLine { return "F:\Vol [Special] (Book)\Docs" }
    $bracketFallback = Read-HostUiLine -HostUi $null
    Assert-True "the fallback path returns a bracketed path intact" ($bracketFallback -ceq "F:\Vol [Special] (Book)\Docs")

    $otherThrowUi = [FakeOtherFailureHostUi]::new()
    $otherThrew = $false
    try {
        $null = Read-HostUiLine -HostUi $otherThrowUi
    }
    catch [System.InvalidOperationException] {
        $otherThrew = $true
    }
    Assert-True "an unrelated exception from the host UI is not swallowed as a fallback trigger" $otherThrew `
        "Read-HostUiLine must only catch NotImplementedException, not every exception"

    function Read-ConsoleFallbackLine { return "scalar-fallback" }
    $scalarFallback = Read-HostUiLine -HostUi $null
    Assert-True "the fallback path returns a single scalar string" (($scalarFallback -is [string]) -and (@($scalarFallback).Count -eq 1))

    # -----------------------------------------------------------------
    Write-Section "Read-ConsoleText: non-redirected branch, ordinary input"

    function Test-ConsoleInputIsRedirected { return $false }
    $script:PromptCallCount = 0
    function Write-ConsolePrompt {
        param($Prompt, [switch]$HideNavigation)
        [void]$Prompt
        [void]$HideNavigation
        $script:PromptCallCount++
    }

    foreach ($case in @(
            @{ Name = "ordinary text"; Value = "hello" },
            @{ Name = "blank input"; Value = "" },
            @{ Name = "Unicode text"; Value = "ファイル テスト résumé" },
            @{ Name = "path with spaces and an apostrophe"; Value = "C:\Users\Kiaro's Files\a b c" },
            @{ Name = "path with brackets"; Value = "F:\Vol [Special] (Book)\Docs" },
            @{ Name = "'0' (back)"; Value = "0" },
            @{ Name = "'exit'"; Value = "exit" },
            @{ Name = "'quit'"; Value = "quit" },
            @{ Name = "'y'"; Value = "y" },
            @{ Name = "'n'"; Value = "n" }
        )) {
        $script:PromptCallCount = 0
        $script:HostUiCallCount = 0
        function Read-HostUiLine {
            $script:HostUiCallCount++
            return $case.Value
        }

        $result = Read-ConsoleText -Prompt "Test"

        Assert-True ("{0} is returned unchanged" -f $case.Name) ($result -ceq $case.Value) ("got '{0}'" -f $result)
        Assert-True ("{0}: Read-HostUiLine called exactly once" -f $case.Name) ($script:HostUiCallCount -eq 1)
        Assert-True ("{0}: prompt written exactly once (no duplication)" -f $case.Name) ($script:PromptCallCount -eq 1)
        Assert-True ("{0}: return value is a single scalar string" -f $case.Name) (($result -is [string]) -and (@($result).Count -eq 1))
    }

    # -----------------------------------------------------------------
    Write-Section "Read-ConsoleText: non-redirected branch, admin re-prompt"

    $script:PromptCallCount = 0
    $script:AdminSwitchCalls = 0
    $script:HostUiAnswers = New-Object System.Collections.Generic.Queue[string]
    $script:HostUiAnswers.Enqueue("admin")
    $script:HostUiAnswers.Enqueue("SecondValue")
    function Read-HostUiLine { return $script:HostUiAnswers.Dequeue() }
    function Invoke-AdminSwitch {
        param([string]$Reason = "")
        [void]$Reason
        $script:AdminSwitchCalls++
        return $false
    }
    function Write-ConsolePrompt {
        param($Prompt, [switch]$HideNavigation)
        [void]$Prompt
        [void]$HideNavigation
        $script:PromptCallCount++
    }

    $adminResult = Read-ConsoleText -Prompt "Test"

    Assert-True "'admin' triggers Invoke-AdminSwitch exactly once" ($script:AdminSwitchCalls -eq 1)
    Assert-True "the value entered after 'admin' is returned normally" ($adminResult -eq "SecondValue")
    Assert-True "the prompt is re-printed once per loop iteration (twice total)" ($script:PromptCallCount -eq 2)

    # -----------------------------------------------------------------
    Write-Section "Read-ConsoleText: redirected branch stays on Read-Host"

    function Test-ConsoleInputIsRedirected { return $true }
    $script:HostUiCallCount = 0
    function Read-HostUiLine { $script:HostUiCallCount++; return "SHOULD-NOT-BE-CALLED" }
    function Read-Host {
        param($Prompt)
        [void]$Prompt
        return "redirected-value"
    }

    $redirectedResult = Read-ConsoleText -Prompt "Test"

    Assert-True "redirected input is returned unchanged" ($redirectedResult -eq "redirected-value")
    Assert-True "the non-redirected host-line reader is never called when input is redirected" ($script:HostUiCallCount -eq 0)

    $script:AdminSwitchCalls = 0
    function Invoke-AdminSwitch {
        param([string]$Reason = "")
        [void]$Reason
        $script:AdminSwitchCalls++
        return $false
    }
    function Read-Host {
        param($Prompt)
        [void]$Prompt
        return "admin"
    }
    $redirectedAdminResult = Read-ConsoleText -Prompt "Test"
    Assert-True "'admin' via the redirected branch triggers Invoke-AdminSwitch" ($script:AdminSwitchCalls -eq 1)
    Assert-True "'admin' via the redirected branch returns '0'" ($redirectedAdminResult -eq "0")
}
finally {
    # No sandbox directories are created in this file - every scenario is a
    # pure in-process function call with no filesystem side effects.
}

Write-TestSummaryAndExit
