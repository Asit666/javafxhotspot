[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
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

if (Test-Path -LiteralPath $installRoot) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
}

Write-Host 'JavaFX Hotspot commands and its managed SDKs have been removed.'
Write-Host 'Open a new terminal to refresh its PATH.'
