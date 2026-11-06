@echo off
setlocal DisableDelayedExpansion
set "SEMVER_ACTIVATE_FILE=%~f0"
set "SEMVER_ACTIVATE_PARENT=%~1"
set "SEMVER_ACTIVATE_OPTION=%~2"
powershell.exe -NoLogo -NoProfile -Command "try { $source = [IO.File]::ReadAllText($env:SEMVER_ACTIVATE_FILE); $body = ($source -split '(?m)^# POWERSHELL-BODY\r?$', 2)[1]; & ([scriptblock]::Create($body)) } catch { Write-Host ('SemVer: ' + $_.Exception.Message); exit 1 }"
exit /b %errorlevel%

# POWERSHELL-BODY
$ErrorActionPreference = 'Stop'
$parentFolder = $env:SEMVER_ACTIVATE_PARENT
$noPrompt = $env:SEMVER_ACTIVATE_OPTION -eq '-NoPrompt'
if ($parentFolder -eq '-NoPrompt') { $parentFolder = ''; $noPrompt = $true }
if ($env:SEMVER_ACTIVATE_OPTION -and $env:SEMVER_ACTIVATE_OPTION -ne '-NoPrompt') {
    Write-Host 'Usage: activate-semver.bat [parent-folder] [-NoPrompt]'
    exit 1
}
if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) {
    Write-Host 'SemVer: Git is required on PATH.'
    exit 1
}

function Test-SemverAlias([string]$Value) {
    # Match the shell installer's quoting/whitespace and optional argument forms.
    # Inspect the value only; never execute an alias to identify it.
    $normalized = ($Value -replace '[\s"''\\]', '').TrimEnd(';')
    return ($normalized -cin @('!sh.githooks/semver', '!sh.githooks/semver$@',
        '!f(){iftest-f.githooks/semver;thensh.githooks/semver;fi;};f',
        '!f(){iftest-f.githooks/semver;thensh.githooks/semver$@;fi;};f') -or
        $normalized -clike '*semver-release/engine*')
}

$alias = '!f() { if test -f .githooks/semver; then sh .githooks/semver "$@"; fi; }; f'
# Windows PowerShell requires escaping embedded quotes for native arguments.
$nativeAlias = $alias.Replace('"', '\"')
$globalAlias = & git config --global --get alias.semver
if ($LASTEXITCODE -ne 0 -or -not (Test-SemverAlias $globalAlias)) {
    & git config --global --replace-all alias.semver $nativeAlias
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Write-Host 'SemVer: Global alias configured.'
} else {
    Write-Host 'SemVer: Global alias already configured.'
}

$visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$installed = [Collections.Generic.List[string]]::new()
$skipped = [Collections.Generic.List[string]]::new()
$failed = [Collections.Generic.List[string]]::new()
$scanErrors = [Collections.Generic.List[string]]::new()

function Search-Repositories([string]$Root) {
    try {
        $item = Get-Item -LiteralPath $Root -Force
        if (-not $item.PSIsContainer -or $item.PSProvider.Name -ne 'FileSystem') {
            throw 'Enter a filesystem folder path.'
        }
    } catch {
        Write-Host "Cannot search: $Root ($($_.Exception.Message))"
        $scanErrors.Add($Root)
        return
    }
    Write-Host "`nSearching: $($item.FullName)"
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($item.FullName)
    while ($pending.Count -gt 0) {
        $folder = $pending.Pop()
        if (-not $visited.Add($folder)) { continue }
        if (Test-Path -LiteralPath (Join-Path $folder '.git')) {
            try {
                $top = & git -C $folder rev-parse --show-toplevel
                if ($LASTEXITCODE -ne 0 -or -not $top -or
                    [IO.Path]::GetFullPath($top) -ne [IO.Path]::GetFullPath($folder)) {
                    throw 'Git could not verify this repository root.'
                }
                if (-not (Test-Path -LiteralPath (Join-Path $folder '.githooks\semver') -PathType Leaf)) {
                    $skipped.Add($folder)
                } else {
                    Write-Host "Installing: $folder"
                    # Check without executing an unrelated repository-local alias.
                    $existing = & git -C $folder config --get alias.semver
                    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the SemVer alias.' }
                    if (-not (Test-SemverAlias $existing)) {
                        throw 'An unrelated local semver alias exists; integrate it manually.'
                    }
                    & git -C $folder semver --install
                    if ($LASTEXITCODE -eq 0) { $installed.Add($folder) }
                    else { $failed.Add($folder) }
                }
            } catch {
                Write-Host "SemVer: $($_.Exception.Message)"
                $failed.Add($folder)
            }
        }
        try {
            $children = @(Get-ChildItem -LiteralPath $folder -Directory -Force -ErrorAction Stop)
        } catch {
            $scanErrors.Add($folder)
            continue
        }
        foreach ($child in $children) {
            # Skip dependency trees and link cycles. OneDrive cloud directories
            # may have ReparsePoint set without being directory links.
            if ($child.Name -in @('.git', 'node_modules') -or
                $child.LinkType -in @('Junction', 'SymbolicLink')) { continue }
            $pending.Push($child.FullName)
        }
    }
}

function Show-Results {
    Write-Host "`nHooks installed successfully ($($installed.Count)):"
    foreach ($path in $installed) { Write-Host "  $path" }
    if ($installed.Count -eq 0) { Write-Host '  None.' }
    if ($skipped.Count -gt 0) {
        Write-Host "Repositories without git-semver-hooks ($($skipped.Count)); skipped:"
        foreach ($path in $skipped) { Write-Host "  $path" }
    }
    if ($failed.Count -gt 0) {
        Write-Host "Repositories with errors ($($failed.Count)); see messages above:"
        foreach ($path in $failed) { Write-Host "  $path" }
    }
    if ($scanErrors.Count -gt 0) {
        Write-Host 'Folders that could not be searched:'
        foreach ($path in $scanErrors) { Write-Host "  $path" }
    }
}

if ($parentFolder) {
    Search-Repositories $parentFolder
} else {
    $roots = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # Honor redirected Documents, Desktop, and Downloads locations.
    $shellFolders = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
    foreach ($name in @('Personal', 'Desktop', '{374DE290-123F-4565-9164-39C4925E467B}')) {
        if ($shellFolders -and $shellFolders.$name) {
            [void]$roots.Add([Environment]::ExpandEnvironmentVariables($shellFolders.$name))
        }
    }
    foreach ($name in @('Documents', 'Downloads', 'Desktop', 'OneDrive')) {
        [void]$roots.Add((Join-Path $env:USERPROFILE $name))
    }
    foreach ($name in @('OneDrive', 'OneDriveConsumer', 'OneDriveCommercial')) {
        $path = [Environment]::GetEnvironmentVariable($name)
        if ($path) { [void]$roots.Add($path) }
    }
    foreach ($root in $roots) {
        if (Test-Path -LiteralPath $root -PathType Container) { Search-Repositories $root }
    }
}
Show-Results
if (-not $noPrompt) {
    while ($true) {
        $extra = Read-Host "`nEnter another parent folder to search, or press Enter to finish"
        if ([string]::IsNullOrWhiteSpace($extra)) { break }
        Search-Repositories ($extra.Trim().Trim('"'))
        Show-Results
    }
}
if ($failed.Count -gt 0 -or $scanErrors.Count -gt 0) { exit 1 }
exit 0
