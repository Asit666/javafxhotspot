$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$updaterPath = Join-Path $repositoryRoot 'bin\javafxupdate-impl.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'javafxhotspot updater test-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $tempRoot 'source\javafxhotspot-main'
$archivePath = Join-Path $tempRoot 'mock-repository.zip'
$markerPath = Join-Path $tempRoot 'installer-ran.txt'
$previousOS = $env:OS
$previousMarker = $env:JAVAFX_HOTSPOT_UPDATE_TEST_MARKER
$global:javafxHotspotMockArchivePath = $archivePath

try {
    New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'scripts'), (Join-Path $sourceRoot 'bin') -Force | Out-Null
    @'
[System.IO.File]::WriteAllText($env:JAVAFX_HOTSPOT_UPDATE_TEST_MARKER, 'installer-ran')
'@ | Set-Content -LiteralPath (Join-Path $sourceRoot 'install.ps1')
    Set-Content -LiteralPath (Join-Path $sourceRoot 'scripts\common.ps1') -Value '# test'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'javafx-versions.json') -Value '{}'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafx.cmd') -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafx-impl.ps1') -Value '# test'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxc.cmd') -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxc-impl.ps1') -Value '# test'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxsetup.cmd') -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxsetup-impl.ps1') -Value '# test'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxupdate.cmd') -Value '@echo off'
    Set-Content -LiteralPath (Join-Path $sourceRoot 'bin\javafxupdate-impl.ps1') -Value '# test'

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceRoot,
        $archivePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true)

    function Invoke-WebRequest {
        param(
            [string] $Uri,
            [string] $OutFile,
            [switch] $UseBasicParsing,
            [int] $TimeoutSec
        )

        if ($Uri -ne 'https://github.com/Asit666/javafxhotspot/archive/refs/heads/main.zip' -or
            $TimeoutSec -ne 60) {
            throw "Updater requested an unexpected archive URL: $Uri"
        }
        Copy-Item -LiteralPath $global:javafxHotspotMockArchivePath -Destination $OutFile -Force
    }

    $env:OS = 'Windows_NT'
    $env:JAVAFX_HOTSPOT_UPDATE_TEST_MARKER = $markerPath
    & $updaterPath
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf) -or
        (Get-Content -LiteralPath $markerPath -Raw) -ne 'installer-ran') {
        throw 'Updater did not invoke the installer from a complete downloaded archive.'
    }

    Remove-Item -LiteralPath $markerPath -Force
    Remove-Item -LiteralPath $archivePath -Force
    $maliciousArchive = [System.IO.Compression.ZipFile]::Open(
        $archivePath,
        [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $null = $maliciousArchive.CreateEntry('javafxhotspot-main/../escape.txt')
    } finally {
        $maliciousArchive.Dispose()
    }

    $unsafeArchiveFailure = $null
    try {
        & $updaterPath
    } catch {
        $unsafeArchiveFailure = $_.Exception.Message
    }
    if ($unsafeArchiveFailure -notmatch 'Unsafe path' -or
        (Test-Path -LiteralPath $markerPath)) {
        throw 'Updater did not reject an archive containing a path traversal entry before running its installer.'
    }
} finally {
    $env:OS = $previousOS
    $env:JAVAFX_HOTSPOT_UPDATE_TEST_MARKER = $previousMarker
    Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
    Remove-Variable -Name javafxHotspotMockArchivePath -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'JavaFX Hotspot update tests passed.'
