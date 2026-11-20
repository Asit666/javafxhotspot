$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repositoryRoot 'scripts\common.ps1')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot uninstall test-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $tempRoot 'JavaFXHotspot'
$bin = Join-Path $installRoot 'bin'
$sdkLib = Join-Path $installRoot 'sdk\javafx-test\lib'
$previousLocalAppData = $env:LOCALAPPDATA
$previousPath = $env:PATH
$previousPathToFx = $env:PATH_TO_FX
$previousUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$previousUserPathToFx = [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
try {
    New-Item -ItemType Directory -Path $bin, $sdkLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'marker.txt') -Value 'test'
    $env:LOCALAPPDATA = $tempRoot
    $env:PATH = $bin + ';' + $previousPath
    $env:PATH_TO_FX = $sdkLib
    $quotedBin = '"' + $bin.TrimEnd('\') + '\' + '"'
    $userPathWithDuplicates = $bin + ';%LOCALAPPDATA%\JavaFXHotspot\bin;' + $quotedBin + ';C:\Keep'
    [Environment]::SetEnvironmentVariable('Path', $userPathWithDuplicates, 'User')
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $sdkLib, 'User')

    if (-not (Test-PathEntryEquals -PathEntry ('"%LOCALAPPDATA%\JavaFXHotspot\bin\"') -Directory $bin) -or
        -not (Test-PathWithinDirectory -Path ('%LOCALAPPDATA%\JavaFXHotspot\sdk\javafx-test\lib') -Directory (Join-Path $installRoot 'sdk')) -or
        (Test-PathWithinDirectory -Path (Join-Path $tempRoot 'JavaFXHotspot-other\sdk') -Directory (Join-Path $installRoot 'sdk')) -or
        (Test-PathWithinDirectory -Path (Join-Path $tempRoot 'custom-javafx-sdk\lib') -Directory (Join-Path $installRoot 'sdk')) -or
        (Remove-PathEntriesForDirectory -PathValue $userPathWithDuplicates -Directory $bin) -ne 'C:\Keep') {
        throw 'PATH normalization did not identify duplicate, quoted, or environment-variable-based install paths.'
    }

    $externalDataPath = Join-Path $tempRoot 'external-data'
    New-Item -ItemType Directory -Path $externalDataPath -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $externalDataPath 'keep.txt') -Value 'preserve'
    $linkedDirectoryPath = Join-Path $installRoot 'linked-data'
    New-Item -ItemType Junction -Path $linkedDirectoryPath -Target $externalDataPath | Out-Null
    $junctionFailure = $null
    try {
        & (Join-Path $repositoryRoot 'uninstall.ps1')
    } catch {
        $junctionFailure = $_.Exception.Message
    }
    if ($junctionFailure -notmatch 'contains linked directories' -or
        (Get-Content -LiteralPath (Join-Path $externalDataPath 'keep.txt') -Raw) -ne "preserve$([Environment]::NewLine)" -or
        -not (Test-Path -LiteralPath $installRoot -PathType Container)) {
        throw 'Uninstaller did not safely refuse a linked directory without touching external files.'
    }
    [System.IO.Directory]::Delete($linkedDirectoryPath, $false)

    & (Join-Path $repositoryRoot 'uninstall.ps1')

    if (Test-Path -LiteralPath $installRoot) {
        throw 'Uninstaller did not remove the isolated JavaFX Hotspot install folder.'
    }
    if (@($env:PATH -split ';' | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') }).Count -gt 0) {
        throw 'Uninstaller did not remove its bin folder from the current process PATH.'
    }
    if ($env:PATH_TO_FX) {
        throw 'Uninstaller did not clear the current process PATH_TO_FX setting.'
    }
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne 'C:\Keep') {
        throw 'Uninstaller did not remove all managed and duplicate PATH entries while preserving unrelated entries.'
    }
    if ([Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')) {
        throw 'Uninstaller did not clear the persisted user PATH_TO_FX setting.'
    }

    New-Item -ItemType Directory -Path $bin, $sdkLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'marker.txt') -Value 'test'
    $env:PATH = $bin + ';' + $previousPath
    $env:PATH_TO_FX = $sdkLib
    [Environment]::SetEnvironmentVariable('Path', $bin + ';C:\Keep', 'User')
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $sdkLib, 'User')
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'uninstall.ps1') 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Uninstaller failed through the documented PowerShell invocation: $($output -join ' ')"
    }
    if (Test-Path -LiteralPath $installRoot) {
        throw 'PowerShell -File uninstall did not remove the isolated JavaFX Hotspot install folder.'
    }
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne 'C:\Keep' -or
        [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')) {
        throw 'PowerShell -File uninstall did not remove the persisted user environment settings.'
    }

} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:PATH = $previousPath
    $env:PATH_TO_FX = $previousPathToFx
    [Environment]::SetEnvironmentVariable('Path', $previousUserPath, 'User')
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $previousUserPathToFx, 'User')
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Isolated uninstall test passed.'
