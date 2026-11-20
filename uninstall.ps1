[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\common.ps1')

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Windows did not provide LOCALAPPDATA. Sign in with a Windows user account and run the uninstaller again.'
}

$installRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'JavaFXHotspot'))
$bin = Join-Path $installRoot 'bin'
$sdkRoot = Join-Path $installRoot 'sdk'
$installItem = Get-Item -LiteralPath $installRoot -Force -ErrorAction SilentlyContinue
if ($installItem -and ($installItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    throw "Refusing to remove '$installRoot' because it is a symbolic link or junction. Remove or inspect the link manually to avoid deleting files outside JavaFX Hotspot."
}
if ($installItem) {
    $linkedDirectories = @(Get-ChildItem -LiteralPath $installRoot -Directory -Force -Recurse -ErrorAction Stop |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
    if ($linkedDirectories.Count -gt 0) {
        $linkedPaths = ($linkedDirectories | ForEach-Object { $_.FullName }) -join '; '
        throw "Refusing to recursively remove JavaFX Hotspot because its install folder contains linked directories: $linkedPaths. Inspect and remove those links manually first."
    }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$remainingUserPath = Remove-PathEntriesForDirectory -PathValue $userPath -Directory $bin
if ($remainingUserPath -cne $userPath) {
    [Environment]::SetEnvironmentVariable('Path', $remainingUserPath, 'User')
}
$persistedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (@($persistedUserPath -split ';' | Where-Object {
    Test-PathEntryEquals -PathEntry $_ -Directory $bin
}).Count -gt 0) {
    throw "Could not remove JavaFX Hotspot's command folder '$bin' from the current user's PATH."
}

$userFxPath = [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
if (Test-PathWithinDirectory -Path $userFxPath -Directory $sdkRoot) {
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $null, 'User')
}
if (Test-PathWithinDirectory -Path ([Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')) -Directory $sdkRoot) {
    throw "Could not remove JavaFX Hotspot's managed JavaFX SDK path from the current user's PATH_TO_FX."
}

$env:PATH = Remove-PathEntriesForDirectory -PathValue $env:PATH -Directory $bin
if (Test-PathWithinDirectory -Path $env:PATH_TO_FX -Directory $sdkRoot) {
    $env:PATH_TO_FX = $null
}
if (@($env:PATH -split ';' | Where-Object {
    Test-PathEntryEquals -PathEntry $_ -Directory $bin
}).Count -gt 0) {
    throw "Could not remove JavaFX Hotspot's command folder '$bin' from this PowerShell process PATH."
}

if (-not (Publish-EnvironmentChange)) {
    Write-Warning 'Windows did not notify open applications about the PATH update. Close and reopen terminals and IDEs to refresh their environment.'
}

if ($installItem) {
    try {
        Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction Stop
    } catch {
        throw "JavaFX Hotspot PATH settings were removed, but the install folder '$installRoot' could not be deleted. Close programs using it and retry. $($_.Exception.Message)"
    }
}
if (Test-Path -LiteralPath $installRoot) {
    throw "JavaFX Hotspot PATH settings were removed, but files remain in '$installRoot'. Close programs using them and retry."
}

Write-Host 'JavaFX Hotspot commands and its managed SDKs have been removed.'
Write-Host 'Java and project files were left untouched. Close and reopen terminals and IDEs to refresh their environment.'
