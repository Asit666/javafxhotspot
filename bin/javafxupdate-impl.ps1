[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'The updater currently supports Windows only.'
}

$repositoryArchive = 'https://github.com/Asit666/javafxhotspot/archive/refs/heads/main.zip'
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'javafxhotspot-update-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'javafxhotspot-main.zip'
$extractPath = Join-Path $temporaryRoot 'extract'
$requiredFiles = @(
    'install.ps1',
    'scripts\common.ps1',
    'javafx-versions.json',
    'bin\javafx.cmd',
    'bin\javafx-impl.ps1',
    'bin\javafxc.cmd',
    'bin\javafxc-impl.ps1',
    'bin\javafxsetup.cmd',
    'bin\javafxsetup-impl.ps1',
    'bin\javafxupdate.cmd',
    'bin\javafxupdate-impl.ps1'
)

try {
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Write-Host 'Downloading the latest JavaFX Hotspot files from GitHub...'
    Invoke-WebRequest -Uri $repositoryArchive -OutFile $archivePath -UseBasicParsing -TimeoutSec 60

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $entryPath = $entry.FullName.Replace('\', '/')
            if ($entryPath.StartsWith('/') -or
                $entryPath -match '(^|/)\.\.(/|$)' -or
                $entryPath -match '(^|/)[A-Za-z]:($|/)' -or
                $entryPath.Contains([char] 0)) {
                throw "Unsafe path in the downloaded JavaFX Hotspot archive: '$($entry.FullName)'."
            }
        }
    } finally {
        $archive.Dispose()
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $repositoryRoot = Join-Path $extractPath 'javafxhotspot-main'
    if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
        throw 'The downloaded archive did not contain the expected javafxhotspot-main folder.'
    }

    $missingFiles = @($requiredFiles | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $repositoryRoot $_) -PathType Leaf)
    })
    if ($missingFiles.Count -gt 0) {
        throw "The downloaded archive is incomplete. Missing required file(s): $($missingFiles -join ', ')."
    }

    Write-Host 'Updating JavaFX Hotspot commands and the compatible JavaFX SDK...'
    & (Join-Path $repositoryRoot 'install.ps1')
    Write-Host 'JavaFX Hotspot update completed. Open a new terminal to use the updated commands.'
} catch {
    throw "JavaFX Hotspot update failed: $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $temporaryRoot -PathType Container) {
        try {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not remove the temporary JavaFX Hotspot update folder '$temporaryRoot': $($_.Exception.Message)"
        }
    }
}
