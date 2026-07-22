# RoboSy module: Console-UI.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Console color/state, ANSI-aware line writers, prompts, breadcrumbs, and the session header.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

$script:UiColor = @{
    Border  = "Cyan"
    Title   = "White"
    Accent  = "Yellow"
    Text    = "White"
    Muted   = "Gray"
    Path    = "Cyan"
    Command = "White"
    Success = "Green"
    Warning = "Yellow"
    Error   = "Red"
}

# Ordered list of completed selections shown at the top of every step so the
# previous steps stay visible after the screen is redrawn.
$script:Breadcrumb = New-Object System.Collections.Generic.List[object]
# The screen is cleared only once at session start. After that every step is
# appended below the previous output so earlier prompts stay visible.
$script:HeaderShownOnce = $false
$script:HeaderTitle = "Robocopy + Symlink (RoboSy)"
$script:HeaderWidth = 120
# ANSI escape equivalent of "\033[38;2;255;50;115m".
$script:HeaderAnsiColor = ("{0}[38;2;255;50;115m" -f [char]27)
$script:LogPathAnsiColor = ("{0}[38;2;255;255;0m" -f [char]27)
$script:PromptOptionAnsiColor = ("{0}[92m" -f [char]27)
$script:PromptNavBackAnsiColor = ("{0}[38;5;166m" -f [char]27)
$script:PromptNavAdminAnsiColor = ("{0}[38;2;160;222;16m" -f [char]27)
$script:PromptNavQuitAnsiColor = ("{0}[38;5;32m" -f [char]27)
# Yellow hint color (ANSI 256-color 221) used for the parenthesized description
# lines shown under each prompt/command.
$script:HintAnsiColor = ("{0}[38;5;221m" -f [char]27)
# Light sky-blue used for command previews.
$script:CommandAnsiColor = ("{0}[38;2;135;206;235m" -f [char]27)
# Medium-bright red (ANSI 256-color 160) for the link-repoint warning header -
# brighter than ConsoleColor.DarkRed but less intense than plain Red/Error.
$script:LinkWarningAnsiColor = ("{0}[38;5;160m" -f [char]27)

function Write-Line {
    param(
        [AllowNull()][string]$Text = "",
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [string]$AnsiColor = ""
    )

    if ($null -eq $Text) { $Text = "" }

    if (-not [string]::IsNullOrWhiteSpace($AnsiColor) -and (Test-AnsiOutputAvailable)) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $AnsiColor, $Text, $reset)
        return
    }

    Write-Host $Text -ForegroundColor $Color
}

function Write-Blank {
    Write-Host ""
}

function Write-Rule {
    param([ConsoleColor]$Color = [ConsoleColor]::Cyan)
    Write-Line ("=" * $script:HeaderWidth) $Color
}

function Test-AnsiOutputAvailable {
    if ([Console]::IsOutputRedirected) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($env:WT_SESSION)) {
        return $true
    }

    try {
        return [bool]$Host.UI.SupportsVirtualTerminal
    }
    catch {
        return $false
    }
}

function Write-HeaderAccentLine {
    param([AllowNull()][string]$Text = "")
    Write-Line $Text Magenta $script:HeaderAnsiColor
}

function Write-LogPathLine {
    param([AllowNull()][string]$Text = "")
    Write-Line $Text Yellow $script:LogPathAnsiColor
}

function Write-Hint {
    param([AllowNull()][string]$Text = "")
    Write-Line ("({0})" -f $Text) Yellow $script:HintAnsiColor
}

function Write-CommandPreview {
    param(
        [AllowNull()][string]$CommandText,
        [string]$Label = "Command"
    )

    Write-Line ($Label + ":") $script:UiColor.Accent
    Write-Line $CommandText Cyan $script:CommandAnsiColor
    Write-Blank
}

function Write-CommandPlan {
    param([AllowNull()][string[]]$Commands)

    $list = @()
    if ($null -ne $Commands) {
        $list = @($Commands | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($list.Count -eq 0) { return }

    # A single command keeps the plain "Command:" label; multiple commands are
    # numbered so the user sees every command that will run, in order.
    if ($list.Count -eq 1) {
        Write-CommandPreview $list[0]
        return
    }

    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-CommandPreview $list[$i] -Label ("Command {0}" -f ($i + 1))
    }
}

function Write-ColoredPromptSegment {
    param(
        [AllowNull()][string]$Text = "",
        [string]$AnsiColor = "",
        [ConsoleColor]$FallbackColor = [ConsoleColor]::White
    )

    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -eq 0) { return }

    if (-not [string]::IsNullOrWhiteSpace($AnsiColor) -and (Test-AnsiOutputAvailable)) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $AnsiColor, $Text, $reset) -NoNewline
        return
    }

    Write-Host $Text -NoNewline -ForegroundColor $FallbackColor
}

function Write-YesNoLetter {
    param([string]$Letter)

    # The uppercase letter is the default choice; show it green like option markers.
    if ($Letter -cmatch '[A-Z]') {
        Write-ColoredPromptSegment $Letter $script:PromptOptionAnsiColor Green
    }
    else {
        Write-ColoredPromptSegment $Letter "" $script:UiColor.Text
    }
}

function Write-PromptText {
    param([AllowNull()][string]$Text = "")

    if ($null -eq $Text) { $Text = "" }

    $optionMatch = [regex]::Match($Text, "\[\d+\]")
    if ($optionMatch.Success) {
        $before = $Text.Substring(0, $optionMatch.Index)
        $option = $optionMatch.Value
        $after = $Text.Substring($optionMatch.Index + $optionMatch.Length)

        Write-ColoredPromptSegment $before "" $script:UiColor.Text
        Write-ColoredPromptSegment $option $script:PromptOptionAnsiColor Green
        Write-ColoredPromptSegment $after "" $script:UiColor.Text
        return
    }

    $ynMatch = [regex]::Match($Text, "\[([yYnN])/([yYnN])\]")
    if ($ynMatch.Success) {
        $before = $Text.Substring(0, $ynMatch.Index)
        $after = $Text.Substring($ynMatch.Index + $ynMatch.Length)

        Write-ColoredPromptSegment $before "" $script:UiColor.Text
        Write-ColoredPromptSegment "[" "" $script:UiColor.Text
        Write-YesNoLetter $ynMatch.Groups[1].Value
        Write-ColoredPromptSegment "/" "" $script:UiColor.Text
        Write-YesNoLetter $ynMatch.Groups[2].Value
        Write-ColoredPromptSegment "]" "" $script:UiColor.Text
        Write-ColoredPromptSegment $after "" $script:UiColor.Text
        return
    }

    Write-ColoredPromptSegment $Text "" $script:UiColor.Text
}

function Write-ConsolePrompt {
    param(
        [string]$Prompt,
        [switch]$HideNavigation
    )

    Write-PromptText $Prompt

    if (-not $HideNavigation) {
        Write-ColoredPromptSegment " " "" $script:UiColor.Text
        Write-ColoredPromptSegment "{" "" $script:UiColor.Text
        Write-ColoredPromptSegment "back=0" $script:PromptNavBackAnsiColor DarkYellow
        Write-ColoredPromptSegment ", " "" $script:UiColor.Text
        Write-ColoredPromptSegment "Run as admin=admin" $script:PromptNavAdminAnsiColor Green
        Write-ColoredPromptSegment ", " "" $script:UiColor.Text
        Write-ColoredPromptSegment "quit=exit" $script:PromptNavQuitAnsiColor Blue
        Write-ColoredPromptSegment "}" "" $script:UiColor.Text
    }

    Write-ColoredPromptSegment ": " "" $script:UiColor.Text
}

function Format-ConsolePromptText {
    param(
        [string]$Prompt,
        [switch]$HideNavigation
    )

    if ($HideNavigation) {
        return $Prompt
    }

    return ("{0} {{back=0, Run as admin=admin, quit=exit}}" -f $Prompt)
}

function Format-HeaderTitleLine {
    $title = $script:HeaderTitle
    $width = $script:HeaderWidth

    if ([string]::IsNullOrWhiteSpace($title) -or $title.Length -ge $width) {
        return $title
    }

    $leftPadding = [int][Math]::Floor(($width - $title.Length) / 2)
    return ((" " * $leftPadding) + $title)
}

function Format-ElapsedTime {
    param([TimeSpan]$Elapsed)

    $hours = [int][Math]::Floor($Elapsed.TotalHours)
    $minutes = $Elapsed.Minutes
    $seconds = $Elapsed.Seconds
    $milliseconds = $Elapsed.Milliseconds

    if ($hours -gt 0) {
        return ("{0:00}:{1:00}:{2:00}.{3:000}" -f $hours, $minutes, $seconds, $milliseconds)
    }

    $totalMinutes = [int][Math]::Floor($Elapsed.TotalMinutes)
    return ("{0:00}:{1:00}.{2:000}" -f $totalMinutes, $seconds, $milliseconds)
}

function Write-TotalElapsedTime {
    param([datetime]$StartedAt)

    $elapsed = (Get-Date) - $StartedAt
    Write-Line ("Total time elapsed: {0}" -f (Format-ElapsedTime $elapsed)) $script:UiColor.Accent
}

function Write-MenuOption {
    param(
        [string]$Key,
        [string]$Title,
        [string]$Description,
        [ConsoleColor]$Color,
        [switch]$Default,
        [string]$AnsiColor = ""
    )

    Write-Host "  [" -NoNewline -ForegroundColor $script:UiColor.Muted
    Write-Host $Key -NoNewline -ForegroundColor $script:UiColor.Accent
    Write-Host "] " -NoNewline -ForegroundColor $script:UiColor.Muted

    if (-not [string]::IsNullOrWhiteSpace($AnsiColor) -and (Test-AnsiOutputAvailable)) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $AnsiColor, $Title, $reset) -NoNewline
    }
    else {
        Write-Host $Title -NoNewline -ForegroundColor $Color
    }

    if ($Default) {
        Write-Host " (default)" -NoNewline -ForegroundColor $script:UiColor.Accent
    }

    Write-Host " - $Description" -ForegroundColor $script:UiColor.Text
}

function Write-LabelValue {
    param(
        [string]$Label,
        [AllowNull()][string]$Value,
        [ConsoleColor]$ValueColor = [ConsoleColor]::Gray
    )

    if ($null -eq $Value) { $Value = "" }
    Write-Host ("  {0,-18}" -f ($Label + ":")) -NoNewline -ForegroundColor $script:UiColor.Muted
    Write-Host $Value -ForegroundColor $ValueColor
}

function Get-ModeDisplayName {
    param([string]$Mode)

    switch ($Mode) {
        "MOVE" { return "Move" }
        "COPY" { return "Copy" }
        "DELETE" { return "Fast Delete" }
        "LINK" { return "Move + Symlink" }
        "SYMONLY" { return "Symlink Only" }
        default { return $Mode }
    }
}

function New-BreadcrumbStep {
    param(
        [string]$Label,
        [AllowNull()][string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    if ($null -eq $Value) { $Value = "" }
    return [pscustomobject]@{ Label = $Label; Value = $Value; Color = $Color }
}

function Reset-Breadcrumb {
    $script:Breadcrumb = New-Object System.Collections.Generic.List[object]
}

function Set-Breadcrumb {
    param([AllowNull()][object[]]$Steps)

    Reset-Breadcrumb
    if ($null -ne $Steps) {
        foreach ($step in $Steps) {
            if ($null -ne $step) {
                $script:Breadcrumb.Add($step)
            }
        }
    }
}

function Write-Breadcrumb {
    if ($script:Breadcrumb.Count -eq 0) { return }

    Write-Line "Selections so far:" $script:UiColor.Accent
    foreach ($step in $script:Breadcrumb) {
        Write-LabelValue $step.Label $step.Value $step.Color
    }
    Write-Blank
}

function Show-Header {
    if (-not $script:LogInitialized) {
        Initialize-LogPath
    }

    # The terminal is never cleared. The full title banner and log path are
    # printed once; every later step just adds the "Selections so far" block
    # below the existing terminal output, with no repeated separator line.
    if ($script:HeaderShownOnce) {
        Write-Blank
        Write-Breadcrumb
        return
    }

    $script:HeaderShownOnce = $true

    Write-Blank
    Write-HeaderAccentLine (Format-HeaderTitleLine)
    Write-HeaderAccentLine ("=" * $script:HeaderWidth)

    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        Write-Line "Logging to: <disabled - no writable log path found>" $script:UiColor.Warning
    }
    else {
        Write-LogPathLine ("Logging to: {0}" -f $script:LogFilePath)
    }

    Write-Blank
    Write-Breadcrumb
}
