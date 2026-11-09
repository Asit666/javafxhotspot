[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\common.ps1')

$installRoot = Join-Path $env:LOCALAPPDATA 'JavaFXHotspot'
$bin = Join-Path $installRoot 'bin'

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$remainingEntries = @($userPath -split ';' | Where-Object {
    $_ -and $_.TrimEnd('\') -ine $bin.TrimEnd('\')
})
[Environment]::SetEnvironmentVariable('Path', ($remainingEntries -join ';'), 'User')

$userFxPath = [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
$sdkPrefix = (Join-Path $installRoot 'sdk').TrimEnd('\') + '\'
if ($userFxPath -and $userFxPath.StartsWith($sdkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $null, 'User')
}
$processEntries = @($env:PATH -split ';' | Where-Object {
    $_ -and $_.TrimEnd('\') -ine $bin.TrimEnd('\')
})
$env:PATH = $processEntries -join ';'
if ($env:PATH_TO_FX -and $env:PATH_TO_FX.StartsWith($sdkPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:PATH_TO_FX = $null
}
if (-not (Publish-EnvironmentChange)) {
    Write-Warning 'Windows did not notify open applications about the PATH update. Open a new terminal to refresh its environment.'
}

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host 'JavaFX Hotspot commands and its managed SDKs have been removed.'
Write-Host 'Open a new terminal to refresh its PATH.'
