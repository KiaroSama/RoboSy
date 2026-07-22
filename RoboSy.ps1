# RoboSy Script
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Interactive helper for common Windows file relocation tasks.
#
# Options:
#   1. Move  - Default option. Press Enter on the main menu to choose it.
#   2. Copy  - Copy a file or folder with robocopy.
#   3. Fast Delete - Permanently delete a file or folder with robocopy purge.
#   4. Move + Symlink - Create a symbolic link at the original path.
#              If the original path already contains a real file/folder and
#              the target path does not exist, the item is moved to the target
#              path with robocopy first, then a symbolic link is created at the
#              original path.
#   5. Symlink Only - Create a symbolic link only; nothing is ever moved.
#              Order does not matter: whichever of the two paths holds the real
#              file/folder becomes the link target, and the other (missing) path
#              becomes the link. Refuses to run if both paths hold real items or
#              if neither does.
#
# Navigation:
#   - Type "exit" at any prompt to quit.
#   - Type "0" at path prompts to go back one step.
#
# Drag and drop:
#   - You can type a path normally.
#   - You can drag/drop an existing file or folder into the console.
#   - After typing, pasting, or dropping a path, press Enter to confirm it.
#     RoboSy never auto-accepts a path; you stay in control of every step.
#   - Each job also asks for a final confirmation before it runs.
#   - Windows blocks drag/drop from normal Explorer windows into elevated
#     Administrator terminals. Run RoboSy normally when you need drag/drop.
#
# Robocopy notes:
#   - Exit codes 0 through 7 are success or non-critical warnings.
#   - Exit codes 8 and above mean at least one failure occurred.
#
# Elevation:
#   - RoboSy runs non-elevated by default so Explorer drag/drop works.
#   - Use RoboSy Admin.cmd only when you intentionally need an Administrator
#     session for file symbolic links or protected paths.

$ErrorActionPreference = "Stop"
$script:OriginalScriptArguments = @($args)

function Convert-ToCommandLineArgument {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-ApplicationPath {
    param([string]$Name)

    try {
        $command = Get-Command $Name -CommandType Application -ErrorAction Stop
        return $command.Source
    }
    catch {
        return $null
    }
}

function Get-PreferredPowerShellPath {
    $pwshPath = Get-ApplicationPath "pwsh.exe"
    if (-not [string]::IsNullOrWhiteSpace($pwshPath)) {
        return $pwshPath
    }

    return (Get-ApplicationPath "powershell.exe")
}

function Get-WindowsTerminalCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]

    $wtFromPath = Get-ApplicationPath "wt.exe"
    if (-not [string]::IsNullOrWhiteSpace($wtFromPath)) {
        $candidates.Add($wtFromPath)
    }

    $windowsAppsWt = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Microsoft\WindowsApps\wt.exe"
    if (Test-Path -LiteralPath $windowsAppsWt) {
        $candidates.Add($windowsAppsWt)
    }

    # Keep a blind wt.exe attempt for systems where App Execution Alias works
    # with Start-Process even when Get-Command cannot resolve it here.
    $candidates.Add("wt.exe")

    return @($candidates | Select-Object -Unique)
}

function Get-ScriptLaunchArguments {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        (Convert-ToCommandLineArgument $PSCommandPath)
    )

    foreach ($arg in $script:OriginalScriptArguments) {
        $argumentList += (Convert-ToCommandLineArgument $arg)
    }

    return $argumentList
}

function Test-RunningAsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-ScriptAsAdministrator {
    if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return $false
    }

    $workingDirectory = Split-Path -Parent $PSCommandPath
    $shellPath = Get-PreferredPowerShellPath
    if ([string]::IsNullOrWhiteSpace($shellPath)) {
        return $false
    }

    $scriptArguments = Get-ScriptLaunchArguments
    $terminalArguments = @(
        "new-tab",
        "--title",
        (Convert-ToCommandLineArgument "RoboSy"),
        "--startingDirectory",
        (Convert-ToCommandLineArgument $workingDirectory),
        (Convert-ToCommandLineArgument $shellPath)
    ) + $scriptArguments

    foreach ($terminalPath in (Get-WindowsTerminalCandidates)) {
        try {
            Start-Process -FilePath $terminalPath -ArgumentList ($terminalArguments -join " ") -WorkingDirectory $workingDirectory -Verb RunAs -ErrorAction Stop
            return $true
        }
        catch {
            continue
        }
    }

    Start-Process -FilePath $shellPath -ArgumentList ($scriptArguments -join " ") -WorkingDirectory $workingDirectory -Verb RunAs -ErrorAction Stop
    return $true
}

if ($env:ROBOSY_FORCE_ELEVATION -eq "1" -and $env:ROBOSY_SKIP_ELEVATION -ne "1" -and -not (Test-RunningAsAdministrator)) {
    Write-Host "Restarting RoboSy as Administrator..." -ForegroundColor Yellow

    try {
        $started = Restart-ScriptAsAdministrator
        if ($started) {
            exit
        }
    }
    catch {
        Write-Host "Failed to restart as Administrator." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Open Windows Terminal as Administrator and run this script manually." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Host "Unable to locate the current script path for elevation." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

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

$script:LogInitialized = $false
$script:LogDirectory = $null
$script:LogFilePath = $null
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

function Initialize-LogPath {
    if ($script:LogInitialized) { return }
    $script:LogInitialized = $true

    $candidateDirs = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        $scriptDir = Split-Path -Parent $PSCommandPath
        if (-not [string]::IsNullOrWhiteSpace($scriptDir)) {
            $candidateDirs.Add((Join-Path -Path $scriptDir -ChildPath "logs"))
        }
    }

    $localAppData = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        $localAppData = Join-Path -Path $HOME -ChildPath "AppData\Local"
    }

    if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
        $candidateDirs.Add((Join-Path -Path $localAppData -ChildPath "RoboSy\logs"))
    }

    $date = (Get-Date).ToString("yyyy-MM-dd")

    foreach ($logDir in $candidateDirs) {
        try {
            if (-not (Test-Path -LiteralPath $logDir)) {
                New-RoboSyDirectory -Path $logDir | Out-Null
            }

            $probe = Join-Path -Path $logDir -ChildPath (".robosy-write-test-{0}.tmp" -f $PID)
            Set-Content -LiteralPath $probe -Value "test" -Encoding UTF8 -ErrorAction Stop
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue

            $script:LogDirectory = $logDir
            $script:LogFilePath = Join-Path -Path $logDir -ChildPath ("robosy-{0}.log" -f $date)
            return
        }
        catch {
            continue
        }
    }
}

function Write-Log {
    param(
        [string]$Level = "INFO",
        [AllowNull()][string]$Message
    )

    if (-not $script:LogInitialized) {
        Initialize-LogPath
    }

    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) { return }
    if ($null -eq $Message) { $Message = "" }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line = "{0} [{1}] {2}" -f $timestamp, $Level.ToUpper(), $Message

    try {
        Add-Content -LiteralPath $script:LogFilePath -Value $line -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Logging never breaks the user-facing flow.
    }
}

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

    if ($null -eq $Text) { $Text = "" }

    if (Test-AnsiOutputAvailable) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $script:HeaderAnsiColor, $Text, $reset)
        return
    }

    Write-Line $Text Magenta
}

function Write-LogPathLine {
    param([AllowNull()][string]$Text = "")

    if ($null -eq $Text) { $Text = "" }

    if (Test-AnsiOutputAvailable) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $script:LogPathAnsiColor, $Text, $reset)
        return
    }

    Write-Line $Text Yellow
}

function Write-Hint {
    param([AllowNull()][string]$Text = "")

    if ($null -eq $Text) { $Text = "" }
    $line = "({0})" -f $Text

    if (Test-AnsiOutputAvailable) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $script:HintAnsiColor, $line, $reset)
        return
    }

    Write-Line $line Yellow
}

function Write-CommandPreview {
    param(
        [AllowNull()][string]$CommandText,
        [string]$Label = "Command"
    )

    if ($null -eq $CommandText) { $CommandText = "" }

    Write-Line ($Label + ":") $script:UiColor.Accent
    if (Test-AnsiOutputAvailable) {
        $reset = "{0}[0m" -f [char]27
        Write-Host ("{0}{1}{2}" -f $script:CommandAnsiColor, $CommandText, $reset)
    }
    else {
        Write-Line $CommandText Cyan
    }
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

function Normalize-UserPath {
    param([AllowNull()][string]$PathText)

    if ($null -eq $PathText) { return "" }

    $p = $PathText.Trim()

    # Dragging a path into PowerShell may insert "& 'C:\path with spaces'".
    if ($p.StartsWith("&")) {
        $candidate = $p.Substring(1).Trim()
        if ($candidate.Length -gt 0) {
            $p = $candidate
        }
    }

    while ($p.Length -ge 2) {
        $first = $p.Substring(0, 1)
        $last = $p.Substring($p.Length - 1, 1)

        if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
            $p = $p.Substring(1, $p.Length - 2).Trim()
            continue
        }

        break
    }

    $p = [Environment]::ExpandEnvironmentVariables($p)

    $homePath = $HOME
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        $homePath = [Environment]::GetFolderPath("UserProfile")
    }

    if ($p -eq "~" -and -not [string]::IsNullOrWhiteSpace($homePath)) {
        return $homePath
    }

    if (($p.StartsWith("~\") -or $p.StartsWith("~/")) -and -not [string]::IsNullOrWhiteSpace($homePath)) {
        return (Join-Path -Path $homePath -ChildPath $p.Substring(2))
    }

    return $p.Trim()
}

function Get-FullPathSafe {
    param([string]$Path)

    try {
        return [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $null
    }
}

function Get-PathLeafForCompare {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }

    $normalized = Normalize-PathForCompare $Path
    if ([string]::IsNullOrWhiteSpace($normalized)) { return "" }

    return (Split-Path -Leaf $normalized)
}

function Get-ItemLinkMetadata {
    param([AllowNull()]$Item)

    $metadata = @{
        IsReparsePoint = $false
        IsSymbolicLink = $false
        IsJunction = $false
        LinkType = ""
        LinkTarget = ""
        Kind = "Missing"
    }

    if ($null -eq $Item) {
        return $metadata
    }

    $metadata.IsReparsePoint = [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)

    if ($Item.PSObject.Properties.Name -contains "LinkType" -and $null -ne $Item.LinkType) {
        $metadata.LinkType = [string]$Item.LinkType
    }

    if ($Item.PSObject.Properties.Name -contains "Target" -and $null -ne $Item.Target) {
        if ($Item.Target -is [array]) {
            $metadata.LinkTarget = ($Item.Target -join "; ")
        }
        else {
            $metadata.LinkTarget = [string]$Item.Target
        }
    }

    $metadata.IsSymbolicLink = $metadata.IsReparsePoint -and $metadata.LinkType.Equals("SymbolicLink", [StringComparison]::OrdinalIgnoreCase)
    $metadata.IsJunction = $metadata.IsReparsePoint -and $metadata.LinkType.Equals("Junction", [StringComparison]::OrdinalIgnoreCase)

    if ($metadata.IsSymbolicLink) {
        $metadata.Kind = "SymbolicLink"
    }
    elseif ($metadata.IsJunction) {
        $metadata.Kind = "Junction"
    }
    elseif ($metadata.IsReparsePoint) {
        $metadata.Kind = "ReparsePoint"
    }
    elseif ($Item.PSIsContainer) {
        $metadata.Kind = "Directory"
    }
    else {
        $metadata.Kind = "File"
    }

    return $metadata
}

function Get-PathParentExists {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    $parent = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parent)) { return $false }

    return (Test-Path -LiteralPath $parent)
}

function Format-PathStatusForLog {
    param([hashtable]$Status)

    if ($null -eq $Status) { return "<null status>" }

    return ("path={0}; exists={1}; type={2}; kind={3}; parent={4}; parentExists={5}; isReparsePoint={6}; isSymbolicLink={7}; isJunction={8}; linkType={9}; linkTarget={10}" -f `
        $Status.Path, $Status.Exists, $Status.Type, $Status.Kind, $Status.Parent, $Status.ParentExists, `
        $Status.IsReparsePoint, $Status.IsSymbolicLink, $Status.IsJunction, $Status.LinkType, $Status.LinkTarget)
}

function Write-PathStatusLog {
    param(
        [string]$Label,
        [hashtable]$Status
    )

    Write-Log "INFO" ("{0}: {1}" -f $Label, (Format-PathStatusForLog $Status))
}

function Test-IsReplaceableLinkStatus {
    param([hashtable]$Status)

    return ($null -ne $Status -and $Status.Exists -and ($Status.IsSymbolicLink -or $Status.IsJunction))
}

function Get-ProtectedRootReason {
    param([AllowNull()][string]$Path)

    $normalized = Normalize-PathForCompare $Path
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return "The path is empty or invalid."
    }

    $root = [System.IO.Path]::GetPathRoot($normalized)
    if (-not [string]::IsNullOrWhiteSpace($root)) {
        $normalizedRoot = Normalize-PathForCompare $root
        if ($normalized.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return "Drive roots and share roots cannot be used for this operation."
        }
    }

    # Only the protected roots themselves are blocked. Ordinary folders located
    # under them stay usable.
    $blockedRoots = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($env:SystemRoot, $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $blockedRoots.Add((Normalize-PathForCompare $candidate))
        }
    }

    foreach ($blockedRoot in @($blockedRoots | Select-Object -Unique)) {
        if ($normalized.Equals($blockedRoot, [StringComparison]::OrdinalIgnoreCase)) {
            return ("Protected root path cannot be used for this operation: {0}" -f $blockedRoot)
        }
    }

    return $null
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

function Remove-EmptySourceDirectoryAfterMove {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    $remaining = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($remaining.Count -gt 0) {
        Write-Log "WARN" ("Source folder still has remaining items after move: {0}" -f $Path)
        return $false
    }

    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Log "INFO" ("Removed empty source folder after move: {0}" -f $Path)
        return $true
    }
    catch {
        Write-Log "WARN" ("Could not remove empty source folder {0}: {1}" -f $Path, $_.Exception.Message)
        Write-Line ("Empty source folder could not be removed: {0}" -f $Path) $script:UiColor.Warning
        Write-Line $_.Exception.Message $script:UiColor.Muted
        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "This may be a permission issue." $script:UiColor.Warning
        }
        return $false
    }
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

function Test-ExitInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }

    $trimmed = $Text.Trim()
    return ($trimmed.Equals("exit", [StringComparison]::OrdinalIgnoreCase) -or $trimmed.Equals("quit", [StringComparison]::OrdinalIgnoreCase))
}

function Test-BackInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }
    return ($Text.Trim() -eq "0")
}

function Test-AdminInput {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $false }
    return $Text.Trim().Equals("admin", [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-AdminSwitch {
    param([string]$Reason = "Restarting RoboSy as Administrator...")

    if (Test-RunningAsAdministrator) {
        Write-Line "RoboSy is already running as Administrator." $script:UiColor.Warning
        Start-Sleep -Seconds 1
        return $false
    }

    if ($env:ROBOSY_SKIP_ELEVATION -eq "1") {
        Write-Line "Admin relaunch is disabled for this session." $script:UiColor.Warning
        return $false
    }

    Write-Line $Reason $script:UiColor.Warning

    try {
        $started = Restart-ScriptAsAdministrator
        if ($started) {
            exit
        }
    }
    catch {
        Write-Line "Failed to restart as Administrator." $script:UiColor.Error
        Write-Line $_.Exception.Message $script:UiColor.Error
        Write-Line "Open Windows Terminal as Administrator and run RoboSy manually." $script:UiColor.Warning
        Start-Sleep -Seconds 2
        return $false
    }

    Write-Line "Unable to locate the current script path for elevation." $script:UiColor.Error
    Start-Sleep -Seconds 2
    return $false
}

function Normalize-PathForCompare {
    param([string]$Path)

    $fullPath = Get-FullPathSafe $Path
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        return $Path
    }

    $trimmed = $fullPath.TrimEnd([char[]]@('\', '/'))
    if ($trimmed.EndsWith(":")) {
        return ($trimmed + "\")
    }

    return $trimmed
}

function Test-IsSameOrChildPath {
    param(
        [string]$Parent,
        [string]$Child
    )

    $parentPath = Normalize-PathForCompare $Parent
    $childPath = Normalize-PathForCompare $Child

    if ([string]::Equals($parentPath, $childPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $parentPath
    if (-not $prefix.EndsWith("\")) {
        $prefix = $prefix + "\"
    }

    return $childPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Format-PowerShellArgument {
    param([AllowNull()][string]$Argument)

    if ($null -eq $Argument) { return "''" }
    if ($Argument -match "[\s']") {
        return "'" + ($Argument -replace "'", "''") + "'"
    }

    return $Argument
}

function Get-RobocopyExitDescription {
    param([int]$Code)

    switch ($Code) {
        0 { return "No files were copied. Source and destination were already in sync." }
        1 { return "Files were copied successfully." }
        2 { return "Extra files or folders exist at the destination. No copy failures." }
        3 { return "Files were copied, and extra destination items were detected." }
        4 { return "Mismatched files or folders were detected. No copy failures." }
        5 { return "Files were copied, and mismatched items were detected." }
        6 { return "Extra and mismatched destination items were detected. No copy failures." }
        7 { return "Files were copied, with extra or mismatched destination items. No copy failures." }
        default {
            if ($Code -ge 8) {
                return "At least one copy or move failure occurred."
            }

            return "Robocopy returned an unusual exit code."
        }
    }
}

# Wraps [Console]::IsInputRedirected in a function so tests can force the
# non-redirected branch of Read-ConsoleText without a real, piped-free
# terminal session.
function Test-ConsoleInputIsRedirected {
    return [Console]::IsInputRedirected
}

# The last-resort line reader when the active host has no usable UI. Kept as
# its own function (instead of calling [Console]::ReadLine() inline) purely so
# tests can replace it and avoid ever blocking on a real console.
function Read-ConsoleFallbackLine {
    return [Console]::ReadLine()
}

# Delegates line editing to the active PowerShell host instead of a
# hand-rolled key-processing loop. PSHostUserInterface.ReadLine() guarantees
# line input, but exact editing behavior (backspace, arrow keys, Escape,
# history, Ctrl+C) is host-defined and can vary between ConsoleHost, Windows
# Terminal, PowerShell 5.1, PowerShell 7+, and other hosts. $HostUi defaults
# to the real $Host.UI in production; tests inject a fake UI object to
# exercise the fallback paths deterministically, since $Host itself is
# read-only and cannot be replaced. A host with no usable UI, or whose
# ReadLine() throws NotImplementedException, falls back to
# Read-ConsoleFallbackLine. Any other exception (including cancellation) is
# never caught here.
function Read-HostUiLine {
    param($HostUi = $Host.UI)

    if ($null -ne $HostUi) {
        try {
            return $HostUi.ReadLine()
        }
        catch [System.NotImplementedException] {
            # Fall through to the console fallback below.
        }
    }

    return Read-ConsoleFallbackLine
}

function Read-ConsoleText {
    param(
        [string]$Prompt,
        [switch]$HideNavigation
    )

    $displayPrompt = Format-ConsolePromptText -Prompt $Prompt -HideNavigation:$HideNavigation

    if (Test-ConsoleInputIsRedirected) {
        $redirectedInput = Read-Host $displayPrompt
        if (Test-AdminInput $redirectedInput) {
            $null = Invoke-AdminSwitch
            return "0"
        }

        return $redirectedInput
    }

    while ($true) {
        Write-ConsolePrompt -Prompt $Prompt -HideNavigation:$HideNavigation
        $inputText = Read-HostUiLine

        if (Test-AdminInput $inputText) {
            $null = Invoke-AdminSwitch
            continue
        }

        return $inputText
    }
}

function Read-ReturnToMenu {
    # Return to the main menu automatically without prompting. The screen is
    # never cleared, so the finished job output stays visible above the menu.
    return "MENU"
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$DefaultNo = $true
    )

    while ($true) {
        if ($DefaultNo) {
            $suffix = " [y/N]"
        }
        else {
            $suffix = " [Y/n]"
        }

        $answer = Read-ConsoleText ($Prompt + $suffix)

        if (Test-ExitInput $answer) {
            return "EXIT"
        }

        if (Test-BackInput $answer) {
            return "BACK"
        }

        if ([string]::IsNullOrWhiteSpace($answer)) {
            return (-not $DefaultNo)
        }

        switch ($answer.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default {
                Write-Line "Please answer y or n. Type exit to quit." $script:UiColor.Error
            }
        }
    }
}

function Get-PathInfo {
    param(
        [string]$InputPath,
        [switch]$AllowMissing
    )

    $path = Normalize-UserPath $InputPath
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    $fullInputPath = Get-FullPathSafe $path
    if (-not [string]::IsNullOrWhiteSpace($fullInputPath)) {
        $path = $fullInputPath
    }

    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    }
    catch {
        $item = $null
    }

    if ($null -ne $item) {
        $metadata = Get-ItemLinkMetadata $item
        $type = if ($item.PSIsContainer) { "Directory" } else { "File" }
        $parent = if ($item.PSIsContainer) { Split-Path -Parent $item.FullName } else { $item.DirectoryName }
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = Split-Path -Parent $item.FullName
        }

        return @{
            Exists = $true
            Type = $type
            Path = $item.FullName
            Parent = $parent
            ParentExists = (Get-PathParentExists $item.FullName)
            Name = $item.Name
            IsReparsePoint = $metadata.IsReparsePoint
            IsSymbolicLink = $metadata.IsSymbolicLink
            IsJunction = $metadata.IsJunction
            LinkType = $metadata.LinkType
            LinkTarget = $metadata.LinkTarget
            Kind = $metadata.Kind
        }
    }

    if (-not $AllowMissing) {
        return $null
    }

    $fullPath = Get-FullPathSafe $path
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        return $null
    }

    return @{
        Exists = $false
        Type = "Missing"
        Path = $fullPath
        Parent = (Split-Path -Parent $fullPath)
        ParentExists = (Get-PathParentExists $fullPath)
        Name = (Split-Path -Leaf (Normalize-PathForCompare $fullPath))
        IsReparsePoint = $false
        IsSymbolicLink = $false
        IsJunction = $false
        LinkType = ""
        LinkTarget = ""
        Kind = "Missing"
    }
}

function Get-PathStatus {
    param([string]$Path)

    $status = Get-PathInfo -InputPath $Path -AllowMissing
    if ($null -ne $status) {
        return $status
    }

    $normalized = Normalize-UserPath $Path
    $fullPath = Get-FullPathSafe $normalized
    if ([string]::IsNullOrWhiteSpace($fullPath)) {
        $fullPath = $normalized
    }

    return @{
        Exists = $false
        Type = "Invalid"
        Path = $fullPath
        Parent = (Split-Path -Parent $fullPath)
        ParentExists = (Get-PathParentExists $fullPath)
        Name = (Split-Path -Leaf $fullPath)
        IsReparsePoint = $false
        IsSymbolicLink = $false
        IsJunction = $false
        LinkType = ""
        LinkTarget = ""
        Kind = "Invalid"
    }
}

function Get-ExistingItem {
    param([string]$Path)

    try {
        return (Get-Item -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Assert-RobocopyAvailable {
    $robocopyCommand = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($null -eq $robocopyCommand) {
        Write-Line "robocopy.exe was not found on PATH." $script:UiColor.Error
        Write-Line "Robocopy is normally included with Windows. Check the system PATH or run this from a standard Windows shell." $script:UiColor.Muted
        return $false
    }

    return $true
}

function Get-CommonRobocopyArgs {
    return @(
        "/COPY:DAT",
        "/DCOPY:DAT",
        "/R:3",
        "/W:5",
        "/MT:16",
        "/TEE",
        "/ETA",
        "/XJ"
    )
}

function Get-RobocopyCommandText {
    param([string[]]$Arguments)

    return "robocopy " + (($Arguments | ForEach-Object { Format-PowerShellArgument $_ }) -join " ")
}

function Invoke-RobocopyCommand {
    param(
        [string[]]$Arguments,
        [switch]$PreviewShown
    )

    $commandPreview = Get-RobocopyCommandText -Arguments $Arguments

    if (-not $PreviewShown) {
        Write-CommandPreview $commandPreview
    }

    Write-Log "INFO" ("Robocopy command: {0}" -f $commandPreview)

    # Out-Host keeps robocopy's live output visible while keeping it out of the
    # success pipeline. Without it the native output is returned to the caller
    # together with the exit code, and "$code = Invoke-RobocopyCommand ..." gets
    # an Object[] instead of an integer.
    & robocopy @Arguments | Out-Host
    $code = [int]$LASTEXITCODE
    $description = Get-RobocopyExitDescription $code

    Write-Blank
    if ($code -le 7) {
        Write-Line ("Robocopy finished. Exit code: {0}" -f $code) $script:UiColor.Success
        Write-Line $description $script:UiColor.Muted
        Write-Log "INFO" ("Robocopy exit code {0}: {1}" -f $code, $description)
    }
    else {
        Write-Line ("Robocopy failed. Exit code: {0}" -f $code) $script:UiColor.Error
        Write-Line $description $script:UiColor.Muted
        Write-Log "ERROR" ("Robocopy exit code {0}: {1}" -f $code, $description)

        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "Robocopy failure can be caused by missing Administrator permission." $script:UiColor.Warning
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
        }
    }

    # Callers compare this against 7, so it must stay a single integer.
    return $code
}

function Read-MainChoice {
    while ($true) {
        Reset-Breadcrumb
        Show-Header
        Write-MenuOption "1" "Move" "Move a folder tree or a single file with robocopy." Magenta -Default -AnsiColor ("{0}[38;2;210;170;255m" -f [char]27)
        Write-MenuOption "2" "Copy" "Copy a folder tree or a single file with robocopy." Green
        Write-MenuOption "3" "Fast Delete" "Permanently delete a file or folder with robocopy purge; no Recycle Bin." Red
        Write-MenuOption "4" "Move + Symlink" "Move the real item to a target path, then leave a link at the original path." Cyan
        Write-MenuOption "5" "Symlink Only" "Only create a symbolic link; nothing is moved. Order of the two paths does not matter." Cyan -AnsiColor ("{0}[38;5;117m" -f [char]27)
        Write-Blank

        $choice = Read-ConsoleText "Choose Option [1]"

        if (Test-ExitInput $choice) {
            return "EXIT"
        }

        if (Test-BackInput $choice) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($choice)) {
            return "MOVE"
        }

        switch ($choice.Trim()) {
            "1" { return "MOVE" }
            "2" { return "COPY" }
            "3" { return "DELETE" }
            "4" { return "LINK" }
            "5" { return "SYMONLY" }
            default {
                Write-Blank
                Write-Line "Invalid option. Choose 1, 2, 3, 4, 5, or press Enter for 1." $script:UiColor.Error
                Start-Sleep -Seconds 1
            }
        }
    }
}

function Read-SourcePath {
    param([string]$Mode)

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent)
    )

    while ($true) {
        Show-Header

        switch ($Mode) {
            "LINK" {
                Write-Line "Enter the original path where the link should exist." $script:UiColor.Text
                Write-Hint "If this path currently contains a real file/folder, it can be moved to the target path first."
                Write-Hint "If this path does not exist, the script will create only the link after you enter an existing target."
            }
            "SYMONLY" {
                Write-Line "Enter the first path. Nothing is ever moved or deleted." $script:UiColor.Text
                Write-Hint "If only one path is a real file/folder, order does not matter - the real side is the link target."
                Write-Hint "If BOTH paths exist, Path 1 is the real source and the link is created inside Path 2 (which must be a folder)."
            }
            "DELETE" {
                Write-Line "Enter the existing file or folder to permanently delete." $script:UiColor.Text
                Write-Hint "This bypasses the Recycle Bin and uses robocopy purge for faster folder deletion."
            }
            default {
                Write-Line "Enter the existing source path." $script:UiColor.Text
                Write-Hint "The source can be a folder or one single file."
            }
        }

        Write-Hint "Type, paste, or drag/drop a path, then press Enter to confirm."
        Write-Blank

        $prompt = switch ($Mode) {
            "DELETE" { "Delete path" }
            "SYMONLY" { "Path 1 (real source if both exist)" }
            default { "Source" }
        }
        $inputPath = Read-ConsoleText $prompt
        if (Test-ExitInput $inputPath) { return @{ Action = "EXIT" } }
        if (Test-BackInput $inputPath) { return @{ Action = "BACK" } }

        $normalizedInputPath = Normalize-UserPath $inputPath
        Write-Log "INFO" ("Source path received: raw={0}; normalized={1}; mode={2}" -f $inputPath, $normalizedInputPath, $Mode)

        $allowMissing = ($Mode -eq "LINK" -or $Mode -eq "SYMONLY")
        $sourceInfo = Get-PathInfo -InputPath $inputPath -AllowMissing:$allowMissing
        if ($null -ne $sourceInfo) {
            Write-PathStatusLog "Source path normalized" $sourceInfo
        }

        if ($null -eq $sourceInfo) {
            Write-Blank
            if ($Mode -eq "LINK") {
                Write-Line "Source/link path is invalid." $script:UiColor.Error
            }
            elseif ($Mode -eq "SYMONLY") {
                Write-Line "First path is invalid." $script:UiColor.Error
            }
            elseif ($Mode -eq "DELETE") {
                Write-Line "Delete path does not exist." $script:UiColor.Error
            }
            else {
                Write-Line "Source path does not exist." $script:UiColor.Error
            }
            Start-Sleep -Seconds 1
            continue
        }

        if ($Mode -eq "MOVE" -or $Mode -eq "COPY") {
            $protectedReason = Get-ProtectedRootReason $sourceInfo.Path
            if (-not [string]::IsNullOrWhiteSpace($protectedReason)) {
                Write-Blank
                Write-Line "Move/Copy source cannot be a drive root, share root, or protected system/profile root." $script:UiColor.Error
                Write-Line $protectedReason $script:UiColor.Warning
                Write-Line "Choose a specific folder or file inside it instead." $script:UiColor.Muted
                Write-Log "ERROR" ("Move/Copy source rejected as a protected root: {0}; reason={1}" -f $sourceInfo.Path, $protectedReason)
                Start-Sleep -Seconds 3
                continue
            }
        }

        if (($Mode -eq "MOVE" -or $Mode -eq "COPY") -and $sourceInfo.IsReparsePoint) {
            Write-Blank
            Write-Line "Move/Copy source cannot be a symbolic link, junction, or other reparse point." $script:UiColor.Error
            Write-Line "Robocopy can follow a source link and move/copy the real target's contents instead." $script:UiColor.Warning
            if (-not [string]::IsNullOrWhiteSpace($sourceInfo.LinkTarget)) {
                Write-Line ("Detected link target: {0}" -f $sourceInfo.LinkTarget) $script:UiColor.Muted
            }
            Write-Line "Choose the real target path directly, or use Move + Symlink when you want to manage a link." $script:UiColor.Muted
            Write-Log "ERROR" ("Move/Copy source rejected because it is a reparse point: {0}" -f (Format-PathStatusForLog $sourceInfo))
            Start-Sleep -Seconds 3
            continue
        }

        $sourceInfo.Action = "OK"
        return $sourceInfo
    }
}

function Read-DestinationPath {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo
    )

    $sourceLabel = switch ($Mode) {
        "LINK" { "Original/link" }
        "SYMONLY" { "Path 1" }
        default { "Source" }
    }
    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent),
        (New-BreadcrumbStep $sourceLabel $SourceInfo.Path $script:UiColor.Path)
    )

    while ($true) {
        Show-Header

        if ($Mode -eq "SYMONLY") {
            Write-Line "Enter the second path. Nothing is ever moved or deleted." $script:UiColor.Text
            Write-Hint "If only Path 1 is real, this is where the link is created (order does not matter)."
            Write-Hint "If both paths exist, the link is created INSIDE this folder as <Path 2>\<Path 1 name> -> Path 1."
            Write-Hint "If neither path is a real file/folder, RoboSy stops without changing anything."
        }
        elseif ($Mode -eq "LINK") {
            Write-Line "Enter the real target path." $script:UiColor.Text
            Write-Hint "If the original path exists and this target path is missing, the original item is moved here first."
            Write-Hint "If the original path is missing, this target path must already exist."
            Write-Hint "If you enter an existing folder while moving an existing item, the item is moved inside it with the same name."
        }
        else {
            Write-Line "Enter the destination folder path." $script:UiColor.Text
            Write-Hint "This is the folder the selected item is transferred into."
            Write-Hint "If the destination folder does not exist, robocopy will create it."

            if ($SourceInfo.Type -eq "Directory") {
                Write-Hint ("The selected folder is transferred as a folder, so it becomes <destination>\{0}." -f $SourceInfo.Name)
                Write-Hint ("A destination that already ends with '{0}' is used as the final folder instead." -f $SourceInfo.Name)
            }
            else {
                Write-Hint ("The original file name is kept, so the file becomes <destination>\{0}." -f $SourceInfo.Name)
            }
        }

        Write-Blank
        $destPrompt = if ($Mode -eq "SYMONLY") { "Path 2 (link location; a folder if both exist)" } else { "Destination/target" }
        $inputPath = Read-ConsoleText $destPrompt
        if (Test-ExitInput $inputPath) { return @{ Action = "EXIT" } }
        if (Test-BackInput $inputPath) { return @{ Action = "BACK" } }

        $normalizedInputPath = Normalize-UserPath $inputPath
        Write-Log "INFO" ("Destination/target path received: raw={0}; normalized={1}; mode={2}" -f $inputPath, $normalizedInputPath, $Mode)

        $destInfo = Get-PathInfo -InputPath $inputPath -AllowMissing
        if ($null -ne $destInfo) {
            Write-PathStatusLog "Destination/target path normalized" $destInfo
        }

        if ($null -eq $destInfo) {
            Write-Blank
            Write-Line "Destination path is invalid." $script:UiColor.Error
            Start-Sleep -Seconds 1
            continue
        }

        if ($Mode -ne "LINK" -and $Mode -ne "SYMONLY") {
            if ($destInfo.Exists -and $destInfo.Type -ne "Directory") {
                Write-Blank
                Write-Line "Destination must be a folder path, but this path is an existing file." $script:UiColor.Error
                Start-Sleep -Seconds 2
                continue
            }

            $rejectReason = Get-StandardDestinationRejectReason -SourceInfo $SourceInfo -DestinationPath $destInfo.Path
            if (-not [string]::IsNullOrWhiteSpace($rejectReason)) {
                Write-Blank
                Write-Line $rejectReason $script:UiColor.Error
                Write-Line "That can cause recursive copies or destructive move behavior." $script:UiColor.Warning
                Write-Log "ERROR" ("Destination rejected: {0}; source={1}; destinationInput={2}" -f $rejectReason, $SourceInfo.Path, $destInfo.Path)
                Start-Sleep -Seconds 3
                continue
            }

            if (-not $destInfo.Exists) {
                $leaf = [System.IO.Path]::GetFileName($destInfo.Path.TrimEnd([char[]]@('\', '/')))
                $extension = [System.IO.Path]::GetExtension($leaf)

                if (-not [string]::IsNullOrWhiteSpace($extension)) {
                    Write-Blank
                    Write-Line "This destination looks like a file name:" $script:UiColor.Warning
                    Write-Line ("  {0}" -f $destInfo.Path) $script:UiColor.Path
                    Write-Line "Robocopy will treat it as a destination folder path, not as an output file or archive." $script:UiColor.Muted
                    $useAnyway = Read-YesNo "Use this as a destination folder anyway" $true

                    if ($useAnyway -is [string] -and $useAnyway -eq "EXIT") { return @{ Action = "EXIT" } }
                    if ($useAnyway -is [string] -and $useAnyway -eq "BACK") { continue }
                    if (-not $useAnyway) { continue }
                }
            }
        }

        $destInfo.Action = "OK"
        return $destInfo
    }
}

# Standard Move/Copy transfer the selected item itself, not only its contents.
# A directory source therefore keeps its own leaf name at the destination:
# "E:\A\Docs" sent to "F:\B" becomes "F:\B\Docs", never "F:\B\<contents>".
# A destination whose leaf already equals the source folder name is treated as
# the final directory, so the same input can never produce "F:\B\Docs\Docs".
# A file source keeps its original file name inside the destination folder, so
# the destination folder itself is the effective destination.
# Move + Symlink keeps its own exact-target semantics in Resolve-LinkTargetPath.
function Resolve-EffectiveDestinationPath {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $destination = Normalize-PathForCompare $DestinationPath

    if ($SourceInfo.Type -ne "Directory") {
        return $destination
    }

    $destinationLeaf = Get-PathLeafForCompare $destination
    if (-not [string]::IsNullOrWhiteSpace($destinationLeaf) -and $destinationLeaf.Equals($SourceInfo.Name, [StringComparison]::OrdinalIgnoreCase)) {
        return $destination
    }

    return (Join-Path -Path $destination -ChildPath $SourceInfo.Name)
}

# The path of the transferred item once the job has run. For a directory source
# this is the effective destination itself; for a file source it is the file
# inside the effective destination folder.
function Resolve-StandardFinalItemPath {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    if ($SourceInfo.Type -eq "Directory") {
        return $effectiveDestination
    }

    return (Join-Path -Path $effectiveDestination -ChildPath $SourceInfo.Name)
}

# Validates the entered destination against the resolved effective destination
# rather than the raw input, so "E:\A\Docs" -> "E:\A" is caught as a same-path
# job instead of being handed to robocopy.
function Get-StandardDestinationRejectReason {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $finalItemPath = Resolve-StandardFinalItemPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath

    $sourceCompare = Normalize-PathForCompare $SourceInfo.Path
    $finalCompare = Normalize-PathForCompare $finalItemPath

    if ([string]::Equals($sourceCompare, $finalCompare, [StringComparison]::OrdinalIgnoreCase)) {
        return ("Source and destination resolve to the same path: {0}" -f $finalItemPath)
    }

    if ($SourceInfo.Type -eq "Directory" -and (Test-IsSameOrChildPath -Parent $SourceInfo.Path -Child $effectiveDestination)) {
        return "Destination cannot be the source folder or a folder inside the source."
    }

    return $null
}

function Get-NearestExistingAncestorStatus {
    param([AllowNull()][string]$Path)

    $current = Normalize-PathForCompare $Path
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            return (Get-PathStatus $current)
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Equals($current, [StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }

        $current = $parent
    }

    return $null
}

# Centralizes what standard Move/Copy will actually do at the effective final
# path: fresh creation, safe reuse, an explicit merge/overwrite that needs
# confirmation, or a hard block (type conflict / unsupported reparse point).
# Both the review screen and the execution-time revalidation call this, so
# they can never disagree about what is about to happen. A reparse point
# anywhere in the write path is unsafe because robocopy writes through it -
# /XJ only excludes junctions encountered while recursing, it does not make a
# linked destination argument safe.
function Get-StandardFinalPathClassification {
    param(
        [hashtable]$SourceInfo,
        [AllowNull()][string]$DestinationPath
    )

    $effectiveDestination = Resolve-EffectiveDestinationPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $finalItemPath = Resolve-StandardFinalItemPath -SourceInfo $SourceInfo -DestinationPath $DestinationPath
    $destinationInputStatus = Get-PathStatus $DestinationPath
    $effectiveDestinationStatus = Get-PathStatus $effectiveDestination
    $finalStatus = Get-PathStatus $finalItemPath

    $result = @{
        EffectiveDestination = $effectiveDestination
        FinalItemPath        = $finalItemPath
        FinalStatus          = $finalStatus
        Classification       = $null
        BlockReason          = $null
        RequiresConfirmation = $false
        ExistingItemCount    = 0
    }

    foreach ($candidate in @($destinationInputStatus, $effectiveDestinationStatus, $finalStatus)) {
        if ($candidate.Exists -and $candidate.IsReparsePoint) {
            $result.Classification = "UnsupportedReparsePoint"
            $result.BlockReason = ("The destination path is a symbolic link, junction, or other reparse point: {0}" -f $candidate.Path)
            return $result
        }
    }

    $ancestorStatus = Get-NearestExistingAncestorStatus $effectiveDestination
    if ($null -ne $ancestorStatus -and $ancestorStatus.IsReparsePoint) {
        $result.Classification = "UnsupportedReparsePoint"
        $result.BlockReason = ("An existing parent folder in the destination path is a symbolic link, junction, or other reparse point: {0}" -f $ancestorStatus.Path)
        return $result
    }

    if (-not $finalStatus.Exists) {
        $result.Classification = if ($SourceInfo.Type -eq "Directory") { "CreateDirectory" } else { "CreateFile" }
        return $result
    }

    if ($SourceInfo.Type -eq "Directory") {
        if ($finalStatus.Type -ne "Directory") {
            $result.Classification = "TypeConflictDirectoryOntoFile"
            $result.BlockReason = ("A folder cannot be transferred onto an existing file: {0}" -f $finalItemPath)
            return $result
        }

        $result.ExistingItemCount = @(Get-ChildItem -LiteralPath $finalItemPath -Force -ErrorAction SilentlyContinue).Count
        if ($result.ExistingItemCount -eq 0) {
            $result.Classification = "ReuseEmptyDirectory"
        }
        else {
            $result.Classification = "MergeDirectory"
            $result.RequiresConfirmation = $true
        }

        return $result
    }

    if ($finalStatus.Type -eq "Directory") {
        $result.Classification = "TypeConflictFileOntoDirectory"
        $result.BlockReason = ("A file cannot overwrite an existing folder: {0}" -f $finalItemPath)
        return $result
    }

    $result.Classification = "OverwriteFile"
    $result.RequiresConfirmation = $true
    return $result
}

function Get-StandardRobocopyArgs {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo,
        [string]$EffectiveDestination
    )

    $commonArgs = Get-CommonRobocopyArgs

    if ($SourceInfo.Type -eq "Directory") {
        $robocopyArgs = @($SourceInfo.Path, $EffectiveDestination, "/E") + $commonArgs

        if ($Mode -eq "MOVE") {
            $robocopyArgs += "/MOVE"
        }

        return $robocopyArgs
    }

    $robocopyArgs = @($SourceInfo.Parent, $EffectiveDestination, $SourceInfo.Name) + $commonArgs

    if ($Mode -eq "MOVE") {
        $robocopyArgs += "/MOV"
    }

    return $robocopyArgs
}

function Invoke-RobocopyJob {
    param(
        [string]$Mode,
        [hashtable]$SourceInfo,
        [hashtable]$DestinationInfo
    )

    $startedAt = Get-Date

    $classification = Get-StandardFinalPathClassification -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    $effectiveDestination = $classification.EffectiveDestination
    $finalItemPath = $classification.FinalItemPath

    $breadcrumbSteps = New-Object System.Collections.Generic.List[object]
    $breadcrumbSteps.Add((New-BreadcrumbStep "Mode" (Get-ModeDisplayName $Mode) $script:UiColor.Accent))
    $breadcrumbSteps.Add((New-BreadcrumbStep "Source" $SourceInfo.Path $script:UiColor.Path))
    $breadcrumbSteps.Add((New-BreadcrumbStep "Destination" $DestinationInfo.Path $script:UiColor.Path))
    if (-not [string]::Equals((Normalize-PathForCompare $DestinationInfo.Path), (Normalize-PathForCompare $finalItemPath), [StringComparison]::OrdinalIgnoreCase)) {
        $breadcrumbSteps.Add((New-BreadcrumbStep "Final path" $finalItemPath $script:UiColor.Path))
    }
    Set-Breadcrumb $breadcrumbSteps.ToArray()

    Show-Header
    Write-Line "Review the job below before it runs." $script:UiColor.Accent
    Write-Blank

    if (-not (Assert-RobocopyAvailable)) {
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $rejectReason = Get-StandardDestinationRejectReason -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    if (-not [string]::IsNullOrWhiteSpace($rejectReason)) {
        Write-Line "Job stopped before anything was transferred." $script:UiColor.Error
        Write-Line $rejectReason $script:UiColor.Warning
        Write-Log "ERROR" ("Standard job blocked: {0}; source={1}; destinationInput={2}" -f $rejectReason, $SourceInfo.Path, $DestinationInfo.Path)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    if (-not [string]::IsNullOrWhiteSpace($classification.BlockReason)) {
        Write-Line "Job stopped before anything was transferred." $script:UiColor.Error
        Write-Line $classification.BlockReason $script:UiColor.Warning
        Write-Log "ERROR" ("Standard job blocked by final-path classification: {0}; classification={1}; source={2}; destinationInput={3}" -f `
            $classification.BlockReason, $classification.Classification, $SourceInfo.Path, $DestinationInfo.Path)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $robocopyArgs = Get-StandardRobocopyArgs -Mode $Mode -SourceInfo $SourceInfo -EffectiveDestination $effectiveDestination
    $finalStatus = $classification.FinalStatus

    $finalPlan = switch ($classification.Classification) {
        "CreateDirectory"     { "Create (does not exist yet)" }
        "CreateFile"          { "Create (does not exist yet)" }
        "ReuseEmptyDirectory" { "Reuse (existing empty folder)" }
        "MergeDirectory"      { "Merge into an existing folder that already holds {0} item(s)" -f $classification.ExistingItemCount }
        "OverwriteFile"       { "Overwrite (an existing file is already at this path)" }
        default               { $classification.Classification }
    }

    $collisionMessage = switch ($classification.Classification) {
        "MergeDirectory" { "Existing files with the same names inside that folder will be overwritten. Unrelated files already there are kept." }
        "OverwriteFile"  { "The existing file at the final path will be overwritten." }
        default          { $null }
    }

    Write-LabelValue "Source type" $SourceInfo.Type $script:UiColor.Text
    Write-LabelValue "Final path" $finalItemPath $script:UiColor.Path
    Write-LabelValue "Final path plan" $finalPlan $script:UiColor.Text

    Write-PathStatusLog "Standard job source check" $SourceInfo
    Write-PathStatusLog "Standard job destination check" $DestinationInfo
    Write-PathStatusLog "Standard job final path check" $finalStatus
    Write-Log "INFO" ("Job start: mode={0}, sourceType={1}, source={2}, destinationInput={3}, effectiveDestination={4}, finalPath={5}, classification={6}" -f `
        $Mode, $SourceInfo.Type, $SourceInfo.Path, $DestinationInfo.Path, $effectiveDestination, $finalItemPath, $classification.Classification)

    if ($Mode -eq "MOVE") {
        Write-Hint "Move mode deletes source items after robocopy confirms they were copied."
    }

    Write-Blank
    Write-CommandPreview (Get-RobocopyCommandText -Arguments $robocopyArgs)

    if ($classification.RequiresConfirmation) {
        Write-Line "The final path already exists." $script:UiColor.Warning
        Write-Line $collisionMessage $script:UiColor.Muted
        Write-Blank

        $collisionConfirm = Read-YesNo ("Continue into the existing path {0}" -f $finalItemPath) $true
        if ($collisionConfirm -is [string] -and $collisionConfirm -eq "EXIT") { return "EXIT" }
        if ($collisionConfirm -is [string] -and $collisionConfirm -eq "BACK") { return "BACK" }
        if (-not $collisionConfirm) {
            Write-Log "INFO" ("Job canceled at the final-path collision prompt: mode={0}; finalPath={1}" -f $Mode, $finalItemPath)
            return "MENU"
        }

        Write-Blank
    }

    $confirm = Read-YesNo ("Run this {0} job now" -f (Get-ModeDisplayName $Mode)) $false
    if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
    if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
    if (-not $confirm) {
        Write-Log "INFO" ("Job canceled by user before execution: mode={0}" -f $Mode)
        return "MENU"
    }

    Write-Blank

    # Re-read the source immediately before the destructive step so a path that
    # changed between the review and the confirmation cannot be acted on.
    $sourceRecheck = Get-PathStatus $SourceInfo.Path
    Write-PathStatusLog "Standard job source recheck before execution" $sourceRecheck
    if (-not $sourceRecheck.Exists -or $sourceRecheck.Type -ne $SourceInfo.Type -or $sourceRecheck.IsReparsePoint) {
        Write-Line "The source path changed after the review, so nothing was transferred." $script:UiColor.Error
        Write-Line ("  {0}" -f $SourceInfo.Path) $script:UiColor.Path
        Write-Log "ERROR" ("Standard job aborted because the source changed after review: {0}" -f (Format-PathStatusForLog $sourceRecheck))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    # Recompute the classification from the same confirmed inputs and compare
    # it to what was shown at review time. The command that runs below is the
    # SAME $robocopyArgs computed at preview time - this never recomputes it,
    # it only decides whether it is still safe to run unchanged.
    $executionClassification = Get-StandardFinalPathClassification -SourceInfo $SourceInfo -DestinationPath $DestinationInfo.Path
    Write-PathStatusLog "Standard job final path recheck before execution" $executionClassification.FinalStatus
    Write-Log "INFO" ("Execution-time classification: {0}; effectiveDestination={1}; finalPath={2}" -f `
        $executionClassification.Classification, $executionClassification.EffectiveDestination, $executionClassification.FinalItemPath)

    $classificationDrifted = (-not [string]::Equals($executionClassification.EffectiveDestination, $effectiveDestination, [StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::Equals($executionClassification.FinalItemPath, $finalItemPath, [StringComparison]::OrdinalIgnoreCase)) -or
        ($executionClassification.Classification -ne $classification.Classification) -or
        (-not [string]::IsNullOrWhiteSpace($executionClassification.BlockReason))

    if ($classificationDrifted) {
        Write-Line "The destination state changed after the review, so nothing was transferred." $script:UiColor.Error
        if (-not [string]::IsNullOrWhiteSpace($executionClassification.BlockReason)) {
            Write-Line $executionClassification.BlockReason $script:UiColor.Warning
        }
        else {
            Write-Line ("Reviewed as: {0}; now: {1}" -f $classification.Classification, $executionClassification.Classification) $script:UiColor.Warning
        }
        Write-Log "ERROR" ("Standard job aborted: final-path classification drifted between review and execution. reviewed={0}; execution={1}" -f `
            $classification.Classification, $executionClassification.Classification)
        Write-Blank
        return (Read-ReturnToMenu)
    }

    $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown
    $sourceCleanupOk = $true

    if ($code -le 7 -and $Mode -eq "MOVE" -and $SourceInfo.Type -eq "Directory") {
        $sourceCleanupOk = Remove-EmptySourceDirectoryAfterMove -Path $SourceInfo.Path
    }

    Write-Blank
    Write-Rule $script:UiColor.Border
    if ($code -le 7 -and $sourceCleanupOk) {
        Write-Line "Job completed." $script:UiColor.Success
        Write-Log "INFO" ("Job completed: mode={0}, exitCode={1}" -f $Mode, $code)
    }
    elseif ($code -le 7) {
        Write-Line "Job completed, but the empty source folder could not be removed." $script:UiColor.Warning
        Write-Log "WARN" ("Job completed with source cleanup warning: mode={0}, exitCode={1}, source={2}" -f $Mode, $code, $SourceInfo.Path)
    }
    else {
        Write-Line "Job completed with errors." $script:UiColor.Error
        Write-Log "ERROR" ("Job completed with errors: mode={0}, exitCode={1}" -f $Mode, $code)
    }
    Write-TotalElapsedTime $startedAt
    Write-Log "INFO" ("Elapsed: {0}" -f (Format-ElapsedTime ((Get-Date) - $startedAt)))
    Write-Rule $script:UiColor.Border
    Write-Blank

    return (Read-ReturnToMenu)
}

function Assert-CmdAvailable {
    $cmdCommand = Get-Command cmd.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $cmdCommand) {
        Write-Line "cmd.exe was not found on PATH." $script:UiColor.Error
        Write-Line "Fast Delete uses cmd.exe for file deletion and final cleanup after robocopy purge." $script:UiColor.Muted
        return $false
    }

    return $true
}

function Format-CmdPathArgument {
    param([string]$Path)

    return ('"{0}"' -f ($Path -replace '"', '""'))
}

function New-RoboSyDirectory {
    param([string]$Path)

    return [System.IO.Directory]::CreateDirectory($Path)
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

function New-RobocopyEmptySourceDirectory {
    param([string]$TargetPath)

    if (-not $script:LogInitialized) {
        Initialize-LogPath
    }

    $candidateRoots = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @([System.IO.Path]::GetTempPath(), $env:TEMP, $env:TMP, $script:LogDirectory)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            $candidateRoots.Add($candidate)
        }
    }

    foreach ($candidateRoot in @($candidateRoots | Select-Object -Unique)) {
        try {
            $rootPath = Get-FullPathSafe $candidateRoot
            if ([string]::IsNullOrWhiteSpace($rootPath)) {
                continue
            }

            if (-not (Test-Path -LiteralPath $rootPath)) {
                New-RoboSyDirectory -Path $rootPath | Out-Null
            }

            $emptySource = Join-Path -Path $rootPath -ChildPath (".robosy-empty-delete-{0}" -f ([Guid]::NewGuid().ToString("N")))
            $emptySourceFullPath = Get-FullPathSafe $emptySource
            if ([string]::IsNullOrWhiteSpace($emptySourceFullPath)) {
                continue
            }

            if (Test-IsSameOrChildPath -Parent $TargetPath -Child $emptySourceFullPath) {
                continue
            }

            New-RoboSyDirectory -Path $emptySourceFullPath | Out-Null
            return $emptySourceFullPath
        }
        catch {
            Write-Log "WARN" ("Could not create robocopy empty source under {0}: {1}" -f $candidateRoot, $_.Exception.Message)
            continue
        }
    }

    return $null
}

function Test-UnsafeFastDeletePath {
    param([hashtable]$Status)

    if ($null -eq $Status -or -not $Status.Exists) {
        return "The delete target does not exist."
    }

    $protectedReason = Get-ProtectedRootReason $Status.Path
    if (-not [string]::IsNullOrWhiteSpace($protectedReason)) {
        return $protectedReason
    }

    if ($Status.IsReparsePoint -and -not (Test-IsReplaceableLinkStatus $Status)) {
        return "Unsupported reparse points are not deleted automatically, to avoid deleting an unexpected target."
    }

    return $null
}

function Invoke-CmdDeleteCommand {
    param(
        [string]$CommandText,
        [switch]$PreviewShown
    )

    $commandPreview = "cmd.exe /d /c " + $CommandText

    if (-not $PreviewShown) {
        Write-CommandPreview $commandPreview
    }

    Write-Log "INFO" ("Fast delete command: {0}" -f $commandPreview)

    # See Invoke-RobocopyCommand: Out-Host keeps the command output visible
    # without letting it become part of this function's return value.
    & cmd.exe /d /c $CommandText | Out-Host
    $code = [int]$LASTEXITCODE

    Write-Blank
    if ($code -eq 0) {
        Write-Line ("Fast delete command finished. Exit code: {0}" -f $code) $script:UiColor.Success
        Write-Log "INFO" ("Fast delete command exit code {0}" -f $code)
    }
    else {
        Write-Line ("Fast delete command failed. Exit code: {0}" -f $code) $script:UiColor.Error
        Write-Log "ERROR" ("Fast delete command exit code {0}" -f $code)

        if (-not (Test-RunningAsAdministrator)) {
            Write-Line "Delete failure can be caused by missing Administrator permission or locked files." $script:UiColor.Warning
            $null = Invoke-AdminSwitch "Relaunching RoboSy as Administrator..."
        }
    }

    # Callers compare this against 0, so it must stay a single integer.
    return $code
}

function Invoke-RobocopyPurgeDirectoryDelete {
    param(
        [string]$TargetPath,
        [switch]$PreviewShown
    )

    if (-not (Assert-RobocopyAvailable)) {
        return 16
    }

    if (-not (Assert-CmdAvailable)) {
        return 16
    }

    $emptySource = New-RobocopyEmptySourceDirectory -TargetPath $TargetPath
    if ([string]::IsNullOrWhiteSpace($emptySource)) {
        Write-Line "Could not create an empty source folder for robocopy purge." $script:UiColor.Error
        Write-Log "ERROR" ("Could not create robocopy purge empty source for target: {0}" -f $TargetPath)
        return 16
    }

    try {
        Write-Hint "Robocopy purges everything inside the selected folder, then RoboSy deletes the selected folder itself."
        Write-Blank

        $robocopyArgs = @(
            $emptySource,
            $TargetPath,
            "/MIR",
            "/MT:32",
            "/R:0",
            "/W:0",
            "/XJ",
            "/NFL",
            "/NDL",
            "/NJH",
            "/NJS",
            "/NP"
        )

        $code = Invoke-RobocopyCommand -Arguments $robocopyArgs -PreviewShown:$PreviewShown
        if ($code -gt 7) {
            return $code
        }

        if (Test-Path -LiteralPath $TargetPath) {
            $quotedPath = Format-CmdPathArgument $TargetPath
            $cleanupCode = Invoke-CmdDeleteCommand -CommandText "rmdir /s /q $quotedPath" -PreviewShown:$PreviewShown
            if ($cleanupCode -ne 0) {
                return $cleanupCode
            }
        }

        return 0
    }
    finally {
        if (Test-Path -LiteralPath $emptySource) {
            Remove-Item -LiteralPath $emptySource -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-FastDeleteJob {
    param([hashtable]$DeleteInfo)

    $startedAt = Get-Date

    Set-Breadcrumb @(
        (New-BreadcrumbStep "Mode" (Get-ModeDisplayName "DELETE") $script:UiColor.Error),
        (New-BreadcrumbStep "Delete target" $DeleteInfo.Path $script:UiColor.Path)
    )

    Show-Header
    Write-Line "Review the delete target below before it runs." $script:UiColor.Error
    Write-Blank

    $deleteStatus = Get-PathStatus $DeleteInfo.Path

    Write-LabelValue "Target type" $deleteStatus.Type $script:UiColor.Text
    Write-LabelValue "Target kind" $deleteStatus.Kind $script:UiColor.Text
    Write-PathStatusLog "Fast delete target check" $deleteStatus
    Write-Log "INFO" ("Fast delete start: {0}" -f (Format-PathStatusForLog $deleteStatus))

    $unsafeReason = Test-UnsafeFastDeletePath -Status $deleteStatus
    if (-not [string]::IsNullOrWhiteSpace($unsafeReason)) {
        Write-Blank
        Write-Line "Fast Delete stopped before deleting anything." $script:UiColor.Error
        Write-Line $unsafeReason $script:UiColor.Warning
        Write-Log "ERROR" ("Fast delete blocked: {0}; target=({1})" -f $unsafeReason, (Format-PathStatusForLog $deleteStatus))
        Write-Blank
        return (Read-ReturnToMenu)
    }

    Write-Blank
    Write-Line "This is permanent. The selected path will not go to the Recycle Bin." $script:UiColor.Warning
    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        Write-Hint "The selected path is a link or junction. RoboSy will delete only the link entry, not its target."
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        Write-Hint "The selected folder and everything inside it will be permanently deleted."
    }
    else {
        Write-Hint "The selected file will be deleted directly."
    }
    Write-Blank

    # Show the command that will run before asking for the final confirmation.
    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        # Link removal uses a direct delete, so there is no shell command to preview.
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        $purgePreviewArgs = @("<temporary empty folder>", $deleteStatus.Path, "/MIR", "/MT:32", "/R:0", "/W:0", "/XJ", "/NFL", "/NDL", "/NJH", "/NJS", "/NP")
        $purgeCmd = Get-RobocopyCommandText -Arguments $purgePreviewArgs
        $rmdirCmd = "cmd.exe /d /c rmdir /s /q " + (Format-CmdPathArgument $deleteStatus.Path)
        Write-CommandPlan @($purgeCmd, $rmdirCmd)
    }
    else {
        Write-CommandPreview ("cmd.exe /d /c del /f /q /a " + (Format-CmdPathArgument $deleteStatus.Path))
    }

    $confirm = Read-YesNo "Permanently delete this path now" $true
    if ($confirm -is [string] -and $confirm -eq "EXIT") { return "EXIT" }
    if ($confirm -is [string] -and $confirm -eq "BACK") { return "BACK" }
    if (-not $confirm) {
        Write-Log "INFO" ("Fast delete canceled by user: {0}" -f $deleteStatus.Path)
        return "MENU"
    }

    Write-Blank

    if (Test-IsReplaceableLinkStatus $deleteStatus) {
        $deleted = Remove-ExistingLinkOnly -Path $deleteStatus.Path -Status $deleteStatus
        $code = if ($deleted) { 0 } else { 1 }
    }
    elseif ($deleteStatus.Type -eq "Directory") {
        $code = Invoke-RobocopyPurgeDirectoryDelete -TargetPath $deleteStatus.Path -PreviewShown
    }
    else {
        if (-not (Assert-CmdAvailable)) {
            Write-Blank
            return (Read-ReturnToMenu)
        }

        $quotedPath = Format-CmdPathArgument $deleteStatus.Path
        $commandText = "del /f /q /a $quotedPath"
        $code = Invoke-CmdDeleteCommand -CommandText $commandText -PreviewShown
    }

    $after = Get-PathStatus $deleteStatus.Path
    Write-PathStatusLog "Fast delete target after delete" $after

    Write-Blank
    Write-Rule $script:UiColor.Border
    if ($code -eq 0 -and -not $after.Exists) {
        Write-Line "Fast delete completed." $script:UiColor.Success
        Write-Log "INFO" ("Fast delete completed: {0}" -f $deleteStatus.Path)
    }
    else {
        Write-Line "Fast delete did not complete." $script:UiColor.Error
        if ($after.Exists) {
            Write-Line "The target path still exists. It may be locked or require Administrator permission." $script:UiColor.Warning
        }
        Write-Log "ERROR" ("Fast delete incomplete: code={0}; after=({1})" -f $code, (Format-PathStatusForLog $after))
    }
    Write-TotalElapsedTime $startedAt
    Write-Log "INFO" ("Elapsed: {0}" -f (Format-ElapsedTime ((Get-Date) - $startedAt)))
    Write-Rule $script:UiColor.Border
    Write-Blank

    return (Read-ReturnToMenu)
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

# Test hook: dot-sourcing this script with ROBOSY_LIB_ONLY=1 loads the helper
# functions without starting the interactive menu. Used by tests\RoboSy.Tests.ps1.
if ($env:ROBOSY_LIB_ONLY -eq "1") { return }

Initialize-LogPath
Write-Log "INFO" ("RoboSy session started. PSVersion={0}, PID={1}, Admin={2}" -f $PSVersionTable.PSVersion, $PID, (Test-RunningAsAdministrator))

:MainMenu while ($true) {
    $mode = Read-MainChoice

    if ($mode -eq "EXIT") {
        Write-Log "INFO" "Mode selected: EXIT"
        break MainMenu
    }

    Write-Log "INFO" ("Mode selected: {0}" -f $mode)

    :SourcePrompt while ($true) {
        $sourceInfo = Read-SourcePath -Mode $mode

        if ($sourceInfo.Action -eq "EXIT") {
            exit
        }

        if ($sourceInfo.Action -eq "BACK") {
            continue MainMenu
        }

        if ($mode -eq "DELETE") {
            $result = Invoke-FastDeleteJob -DeleteInfo $sourceInfo

            if ($result -eq "EXIT") {
                exit
            }

            if ($result -eq "BACK") {
                continue SourcePrompt
            }

            continue MainMenu
        }

        :DestinationPrompt while ($true) {
            $destInfo = Read-DestinationPath -Mode $mode -SourceInfo $sourceInfo

            if ($destInfo.Action -eq "EXIT") {
                exit
            }

            if ($destInfo.Action -eq "BACK") {
                break DestinationPrompt
            }

            if ($mode -eq "LINK") {
                $result = Invoke-MoveAndLinkJob -SourceInfo $sourceInfo -TargetInputInfo $destInfo
            }
            elseif ($mode -eq "SYMONLY") {
                $result = Invoke-SymlinkOnlyJob -FirstInfo $sourceInfo -SecondInfo $destInfo
            }
            else {
                $result = Invoke-RobocopyJob -Mode $mode -SourceInfo $sourceInfo -DestinationInfo $destInfo
            }

            if ($result -eq "EXIT") {
                exit
            }

            if ($result -eq "BACK") {
                continue DestinationPrompt
            }

            # Pressing Enter after a completed job returns to the main menu.
            continue MainMenu
        }
    }
}

Write-Blank
Write-Line "Goodbye." $script:UiColor.Accent
Write-Log "INFO" "RoboSy session ended."
Start-Sleep -Milliseconds 500
