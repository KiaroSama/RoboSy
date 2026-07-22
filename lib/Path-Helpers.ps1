# RoboSy module: Path-Helpers.ps1
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kiaro Sama
# Path normalization/comparison, link metadata, path status, and the protected-root guard.
# Dot-sourced by RoboSy.ps1 - not a standalone entry point.

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


function New-RoboSyDirectory {
    param([string]$Path)

    return [System.IO.Directory]::CreateDirectory($Path)
}
