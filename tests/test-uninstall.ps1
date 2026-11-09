$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot uninstall test-' + [guid]::NewGuid().ToString('N'))
$installRoot = Join-Path $tempRoot 'JavaFXHotspot'
$bin = Join-Path $installRoot 'bin'
$sdkLib = Join-Path $installRoot 'sdk\javafx-test\lib'
$previousLocalAppData = $env:LOCALAPPDATA
$previousPath = $env:PATH
$previousPathToFx = $env:PATH_TO_FX

try {
    New-Item -ItemType Directory -Path $bin, $sdkLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'marker.txt') -Value 'test'
    $env:LOCALAPPDATA = $tempRoot
    $env:PATH = $bin + ';' + $previousPath
    $env:PATH_TO_FX = $sdkLib

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

    New-Item -ItemType Directory -Path $bin, $sdkLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'marker.txt') -Value 'test'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repositoryRoot 'uninstall.ps1') 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Uninstaller failed through the documented PowerShell invocation: $($output -join ' ')"
    }
    if (Test-Path -LiteralPath $installRoot) {
        throw 'PowerShell -File uninstall did not remove the isolated JavaFX Hotspot install folder.'
    }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:PATH = $previousPath
    $env:PATH_TO_FX = $previousPathToFx
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Isolated uninstall test passed.'
