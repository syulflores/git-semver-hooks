@echo off
setlocal DisableDelayedExpansion
set "SEMVER_MENU_FILE=%~f0"
set "SEMVER_MENU_PARENT=%~1"
set "SEMVER_MENU_OPTION=%~2"
powershell.exe -NoLogo -NoProfile -Command "try { $source = [IO.File]::ReadAllText($env:SEMVER_MENU_FILE); $body = ($source -split '(?m)^# POWERSHELL-BODY\r?$', 2)[1]; & ([scriptblock]::Create($body)) } catch { Write-Host ('SemVer: ' + $_.Exception.Message); exit 1 }"
exit /b %errorlevel%

# POWERSHELL-BODY
$ErrorActionPreference = 'Stop'
$parentFolder = $env:SEMVER_MENU_PARENT
$noPrompt = $env:SEMVER_MENU_OPTION -eq '--no-prompt'
if ($parentFolder -eq '--no-prompt') { $parentFolder = ''; $noPrompt = $true }
if ($env:SEMVER_MENU_OPTION -and $env:SEMVER_MENU_OPTION -ne '--no-prompt') {
    Write-Host 'Usage: semver-scripts.bat [parent-folder] [--no-prompt]'
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

function Get-SemverStatus([string]$Folder) {
    $hooksPath = & git -C $Folder config --path --get core.hooksPath
    if ($LASTEXITCODE -notin @(0, 1)) { throw 'Cannot read core.hooksPath.' }
    $enabled = & git -C $Folder config --get semver.enabled
    if ($LASTEXITCODE -notin @(0, 1)) { throw 'Cannot read semver.enabled.' }
    $expectedPath = Join-Path $Folder '.githooks'
    $hooksSelected = $false
    if ($hooksPath) {
        if (-not [IO.Path]::IsPathRooted($hooksPath)) { $hooksPath = Join-Path $Folder $hooksPath }
        $hooksSelected = [IO.Path]::GetFullPath($hooksPath).TrimEnd('\', '/') -eq $expectedPath
    }
    $files = @('semver', 'post-commit', 'pre-push', 'post-index-change')
    $present = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $expectedPath $_) -PathType Leaf }).Count
    if ($present -eq 0 -and -not $hooksSelected -and $enabled -cne 'true') { return 'Not installed' }
    if ($present -ne $files.Count) { return 'Incomplete' }
    if ($hooksSelected -and $enabled -ceq 'true') { return 'Activated' }
    return 'Not activated'
}

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
                if ($action -eq 'List') {
                    $status = Get-SemverStatus $folder
                    $version = ''
                    if ($status -eq 'Activated') {
                        try {
                            $output = & git -C $folder semver --version
                            if ($LASTEXITCODE -ne 0 -or -not $output) { throw 'git semver --version did not return a version.' }
                            $version = ($output -join ' ').Trim()
                        } catch {
                            $version = 'Version unavailable'
                            Write-Host "SemVer: Cannot read version in $folder ($($_.Exception.Message))"
                            $failed.Add($folder)
                        }
                    }
                    $repositories.Add([pscustomobject]@{ Path = $folder; Status = $status; Version = $version })
                } elseif (-not (Test-Path -LiteralPath (Join-Path $folder '.githooks\semver') -PathType Leaf)) {
                    $skipped.Add($folder)
                } else {
                    $verb = if ($action -eq 'Activate') { 'Installing' } else { 'Updating' }
                    $command = if ($action -eq 'Activate') { '--install' } else { '--update' }
                    Write-Host "${verb}: $folder"
                    # Never execute an unrelated repository-local alias.
                    $existing = & git -C $folder config --get alias.semver
                    if ($LASTEXITCODE -ne 0) { throw 'Cannot read the SemVer alias.' }
                    if (-not (Test-SemverAlias $existing)) {
                        throw 'An unrelated local semver alias exists; integrate it manually.'
                    }
                    & git -C $folder semver $command
                    if ($LASTEXITCODE -eq 0) { $completed.Add($folder) }
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
    if ($action -eq 'List') {
        Write-Host "`nGit repositories found ($($repositories.Count)):"
        foreach ($status in @('Activated', 'Not activated', 'Incomplete', 'Not installed')) {
            $matches = @($repositories | Where-Object { $_.Status -eq $status } | Sort-Object Path)
            Write-Host "$status ($($matches.Count)):"
            foreach ($repo in $matches) {
                $details = if ($repo.Version) { " - $($repo.Version)" } else { '' }
                Write-Host "  [$status] $($repo.Path)$details"
            }
            if ($matches.Count -eq 0) { Write-Host '  None.' }
        }
    } else {
        $label = if ($action -eq 'Activate') { 'Hooks installed successfully' } else { 'Hooks updated successfully' }
        Write-Host "`n$label ($($completed.Count)):"
        foreach ($path in ($completed | Sort-Object)) { Write-Host "  $path" }
        if ($completed.Count -eq 0) { Write-Host '  None.' }
        if ($skipped.Count -gt 0) {
            Write-Host "Repositories without git-semver-hooks ($($skipped.Count)); skipped:"
            foreach ($path in ($skipped | Sort-Object)) { Write-Host "  $path" }
        }
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

function Invoke-SemverAction([string]$Action) {
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $repositories = [Collections.Generic.List[object]]::new()
    $completed = [Collections.Generic.List[string]]::new()
    $skipped = [Collections.Generic.List[string]]::new()
    $failed = [Collections.Generic.List[string]]::new()
    $scanErrors = [Collections.Generic.List[string]]::new()
    if ($action -ne 'List') {
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
            $extra = Read-Host "`nEnter another parent folder to search, or press Enter to return to the menu"
            if ([string]::IsNullOrWhiteSpace($extra)) { break }
            Search-Repositories ($extra.Trim().Trim('"'))
            Show-Results
        }
    }
    if ($failed.Count -gt 0 -or $scanErrors.Count -gt 0) { $script:exitCode = 1 }
}

$script:exitCode = 0
do {
    Write-Host "`nGit SemVer Hooks"
    Write-Host '1. List repositories (status and version)'
    Write-Host '2. Activate SemVer hooks'
    Write-Host '3. Update SemVer hooks'
    Write-Host '0. Exit'
    $choice = Read-Host 'Select an option'
    $action = switch ($choice.Trim()) {
        '1' { 'List' }
        '2' { 'Activate' }
        '3' { 'Update' }
        '0' { exit $script:exitCode }
        default { '' }
    }
    if (-not $action) {
        Write-Host 'Please select 1, 2, 3, or 0.'
        continue
    }
    Invoke-SemverAction $action
    if ($noPrompt) { break }
} while ($true)
exit $script:exitCode
