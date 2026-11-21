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
$previousHome = $HOME
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

    $downloadedRepository = Join-Path $tempRoot 'javafxhotspot-download\javafxhotspot-main'
    $preservedParent = Join-Path $tempRoot 'javafxhotspot-bootstrap'
    $bootstrapRepository = Join-Path $preservedParent 'javafxhotspot-main'
    foreach ($repository in @($downloadedRepository, $bootstrapRepository)) {
        New-Item -ItemType Directory -Path (Join-Path $repository 'bin') -Force | Out-Null
        foreach ($requiredFile in @('install.ps1', 'uninstall.ps1', 'javafx-versions.json')) {
            Set-Content -LiteralPath (Join-Path $repository $requiredFile) -Value 'test'
        }
        Set-Content -LiteralPath (Join-Path $repository 'bin\javafxupdate.cmd') -Value '@echo off'
    }
    Set-Content -LiteralPath (Join-Path $preservedParent 'keep.txt') -Value 'preserve'

    $gitRepository = Join-Path $tempRoot 'javafxhotspot-uninstall\javafxhotspot-main'
    New-Item -ItemType Directory -Path (Join-Path $gitRepository '.git'), (Join-Path $gitRepository 'bin') -Force | Out-Null
    foreach ($requiredFile in @('install.ps1', 'uninstall.ps1', 'javafx-versions.json')) {
        Set-Content -LiteralPath (Join-Path $gitRepository $requiredFile) -Value 'test'
    }
    Set-Content -LiteralPath (Join-Path $gitRepository 'bin\javafxupdate.cmd') -Value '@echo off'

    $linkedRepository = Join-Path $tempRoot 'javafxhotspot-download-fresh\javafxhotspot-main'
    New-Item -ItemType Directory -Path (Join-Path $linkedRepository 'bin') -Force | Out-Null
    foreach ($requiredFile in @('install.ps1', 'uninstall.ps1', 'javafx-versions.json')) {
        Set-Content -LiteralPath (Join-Path $linkedRepository $requiredFile) -Value 'test'
    }
    Set-Content -LiteralPath (Join-Path $linkedRepository 'bin\javafxupdate.cmd') -Value '@echo off'
    $linkedDownloadTarget = Join-Path $tempRoot 'external-download-data'
    New-Item -ItemType Directory -Path $linkedDownloadTarget -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $linkedDownloadTarget 'keep.txt') -Value 'preserve'
    $linkedDownloadPath = Join-Path $linkedRepository 'linked-data'
    New-Item -ItemType Junction -Path $linkedDownloadPath -Target $linkedDownloadTarget | Out-Null

    $archiveSource = Join-Path $tempRoot 'javafxhotspot-main'
    New-Item -ItemType Directory -Path (Join-Path $archiveSource 'bin') -Force | Out-Null
    foreach ($requiredFile in @('install.ps1', 'uninstall.ps1', 'javafx-versions.json')) {
        Set-Content -LiteralPath (Join-Path $archiveSource $requiredFile) -Value 'test'
    }
    Set-Content -LiteralPath (Join-Path $archiveSource 'bin\javafxupdate.cmd') -Value '@echo off'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $knownArchivePath = Join-Path $tempRoot 'javafxhotspot-bootstrap.zip'
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $archiveSource,
        $knownArchivePath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true)
    $unrelatedArchivePath = Join-Path $tempRoot 'javafxhotspot-fresh.zip'
    Set-Content -LiteralPath $unrelatedArchivePath -Value 'not a JavaFX Hotspot ZIP'
    Set-Variable -Name HOME -Scope Global -Value $tempRoot -Force

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
    if ((Test-Path -LiteralPath (Join-Path $tempRoot 'javafxhotspot-download')) -or
        (Test-Path -LiteralPath $downloadedRepository) -or
        (Test-Path -LiteralPath (Join-Path $preservedParent 'javafxhotspot-main')) -or
        (Test-Path -LiteralPath $knownArchivePath)) {
        throw 'Uninstaller did not remove the recognized extracted JavaFX Hotspot repositories.'
    }
    if (-not (Test-Path -LiteralPath $gitRepository -PathType Container) -or
        -not (Test-Path -LiteralPath $linkedRepository -PathType Container) -or
        (Get-Content -LiteralPath (Join-Path $linkedDownloadTarget 'keep.txt') -Raw) -ne "preserve$([Environment]::NewLine)") {
        throw 'Uninstaller did not preserve the Git checkout or linked bootstrap data.'
    }
    if ((Get-Content -LiteralPath (Join-Path $preservedParent 'keep.txt') -Raw) -ne "preserve$([Environment]::NewLine)") {
        throw 'Uninstaller removed unrelated files from a bootstrap folder.'
    }
    if (-not (Test-Path -LiteralPath $unrelatedArchivePath -PathType Leaf)) {
        throw 'Uninstaller did not remove only recognized JavaFX Hotspot ZIP archives.'
    }
    [System.IO.Directory]::Delete($linkedDownloadPath, $false)

    New-Item -ItemType Directory -Path $bin, $sdkLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $bin 'marker.txt') -Value 'test'
    $env:PATH = $bin + ';' + $previousPath
    $customSdk = Join-Path $tempRoot 'custom-swing-sdk\lib'
    $env:PATH_TO_FX = $customSdk
    [Environment]::SetEnvironmentVariable('Path', $bin + ';C:\Keep', 'User')
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $customSdk, 'User')
    Set-Content -LiteralPath (Join-Path $installRoot 'managed-path-to-fx.txt') -Value $sdkLib -NoNewline
    Set-Content -LiteralPath (Join-Path $installRoot 'previous-path-to-fx.txt') -Value 'C:\OldJavaFX\lib'
    $scriptPath = (Join-Path $repositoryRoot 'uninstall.ps1').Replace("'", "''")
    $isolatedHome = $tempRoot.Replace("'", "''")
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command (
        "Set-Variable -Name HOME -Scope Global -Value '$isolatedHome' -Force; & '$scriptPath'") 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Uninstaller failed through the documented PowerShell invocation: $($output -join ' ')"
    }
    if (Test-Path -LiteralPath $installRoot) {
        throw 'PowerShell -File uninstall did not remove the isolated JavaFX Hotspot install folder.'
    }
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne 'C:\Keep' -or
        [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User') -ne $customSdk) {
        throw 'PowerShell -File uninstall did not remove the persisted user environment settings.'
    }

} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:PATH = $previousPath
    $env:PATH_TO_FX = $previousPathToFx
    Set-Variable -Name HOME -Scope Global -Value $previousHome -Force
    [Environment]::SetEnvironmentVariable('Path', $previousUserPath, 'User')
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $previousUserPathToFx, 'User')
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Isolated uninstall test passed.'
