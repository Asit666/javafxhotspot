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
$homeRoot = [System.IO.Path]::GetFullPath($HOME)
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

$removedDownloads = [System.Collections.Generic.List[string]]::new()
$preservedDownloads = [System.Collections.Generic.List[string]]::new()
$knownFolderNames = @(
    'javafxhotspot-download',
    'javafxhotspot-download-fresh',
    'javafxhotspot-bootstrap',
    'javafxhotspot-uninstall'
)
$knownArchiveNames = @(
    'javafxhotspot.zip',
    'javafxhotspot-download.zip',
    'javafxhotspot-fresh.zip',
    'javafxhotspot-bootstrap.zip',
    'javafxhotspot-uninstall.zip'
)
$requiredRepositoryFiles = @(
    'install.ps1',
    'uninstall.ps1',
    'javafx-versions.json'
)

foreach ($folderName in $knownFolderNames) {
    $downloadFolder = Join-Path $homeRoot $folderName
    $repositoryFolder = Join-Path $downloadFolder 'javafxhotspot-main'
    if (-not (Test-Path -LiteralPath $repositoryFolder -PathType Container)) {
        continue
    }

    $repositoryItem = Get-Item -LiteralPath $repositoryFolder -Force
    if (($repositoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or
        (Test-Path -LiteralPath (Join-Path $repositoryFolder '.git'))) {
        $preservedDownloads.Add("$repositoryFolder (linked folder or Git checkout)")
        continue
    }

    $isRepositoryArchive = @($requiredRepositoryFiles | Where-Object {
        Test-Path -LiteralPath (Join-Path $repositoryFolder $_) -PathType Leaf
    }).Count -eq $requiredRepositoryFiles.Count
    if (-not $isRepositoryArchive) {
        $preservedDownloads.Add("$repositoryFolder (does not match the expected repository layout)")
        continue
    }

    $linkedDirectories = @(Get-ChildItem -LiteralPath $repositoryFolder -Directory -Force -Recurse -ErrorAction Stop |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
    if ($linkedDirectories.Count -gt 0) {
        $preservedDownloads.Add("$repositoryFolder (contains linked directories)")
        continue
    }

    Remove-Item -LiteralPath $repositoryFolder -Recurse -Force -ErrorAction Stop
    $removedDownloads.Add($repositoryFolder)
    if ((Test-Path -LiteralPath $downloadFolder -PathType Container) -and
        @(Get-ChildItem -LiteralPath $downloadFolder -Force).Count -eq 0) {
        Remove-Item -LiteralPath $downloadFolder -Force -ErrorAction Stop
        $removedDownloads.Add($downloadFolder)
    } elseif (Test-Path -LiteralPath $downloadFolder -PathType Container) {
        $preservedDownloads.Add("$downloadFolder (contains files other than the recognized repository)")
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($archiveName in $knownArchiveNames) {
    $archivePath = Join-Path $homeRoot $archiveName
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        continue
    }

    $archiveItem = Get-Item -LiteralPath $archivePath -Force
    if ($archiveItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        $preservedDownloads.Add("$archivePath (linked file)")
        continue
    }

    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        $archiveEntries = @($archive.Entries | ForEach-Object {
            $_.FullName.Replace('\', '/')
        })
        $rootEntry = @($archiveEntries | Where-Object {
            $_ -match '^[^/]+/install\.ps1$'
        } | Select-Object -First 1)
        if ($rootEntry.Count -eq 0) {
            $preservedDownloads.Add("$archivePath (not a recognized JavaFX Hotspot archive)")
            continue
        }

        $archiveRoot = $rootEntry[0] -replace '/install\.ps1$', '/'
        $isKnownArchive = $true
        foreach ($requiredFile in $requiredRepositoryFiles) {
            if ($archiveEntries -notcontains ($archiveRoot + $requiredFile.Replace('\', '/'))) {
                $isKnownArchive = $false
                break
            }
        }
        if (-not $isKnownArchive) {
            $preservedDownloads.Add("$archivePath (missing required JavaFX Hotspot files)")
            continue
        }
    } catch {
        $preservedDownloads.Add("$archivePath (could not validate as a ZIP archive: $($_.Exception.Message))")
        continue
    } finally {
        if ($archive) {
            $archive.Dispose()
        }
    }

    Remove-Item -LiteralPath $archivePath -Force -ErrorAction Stop
    $removedDownloads.Add($archivePath)
}

if ($removedDownloads.Count -gt 0) {
    Write-Host "Removed known JavaFX Hotspot downloads: $($removedDownloads -join '; ')"
}
foreach ($preservedDownload in $preservedDownloads) {
    Write-Warning "Preserved download because it could not be safely identified for removal: $preservedDownload"
}

Write-Host 'JavaFX Hotspot commands and its managed SDKs have been removed.'
Write-Host 'Java and project files were left untouched. Close and reopen terminals and IDEs to refresh their environment.'
