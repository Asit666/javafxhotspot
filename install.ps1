[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\common.ps1')

if ($env:OS -ne 'Windows_NT') {
    throw 'The installer currently supports Windows only.'
}

$jdk = Get-CurrentJdk
$release = Get-CompatibleJavaFxRelease -JdkMajor $jdk.Major
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    throw 'Windows did not provide LOCALAPPDATA. Sign in with a Windows user account and run the installer again.'
}
$installRoot = Join-Path $env:LOCALAPPDATA 'JavaFXHotspot'
$sdkRoot = Join-Path $installRoot ("sdk\javafx-" + $release.version + "-windows-x64")
$sdkLib = Join-Path $sdkRoot 'lib'
$requiredSdkJars = @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')
$requiredSdkNativeLibraries = @('glass.dll', 'javafx_font.dll', 'javafx_iio.dll', 'prism_d3d.dll', 'prism_sw.dll')
$bin = Join-Path $installRoot 'bin'

foreach ($directoryToCheck in @(
    $installRoot,
    $bin,
    (Join-Path $installRoot 'scripts'),
    (Join-Path $installRoot 'sdk'),
    $sdkRoot,
    $sdkLib
)) {
    if (Test-Path -LiteralPath $directoryToCheck) {
        $directoryItem = Get-Item -LiteralPath $directoryToCheck -Force
        if ($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to install through linked directory '$directoryToCheck'. Remove or inspect the link before retrying."
        }
    }
}

Write-Host "Detected JDK $($jdk.Major) ($($jdk.Architecture))."
Write-Host "Selected JavaFX $($release.version) (minimum JDK $($release.minimumJdk))."

$invalidInstalledJars = @()
foreach ($jarName in $requiredSdkJars) {
   $jarPath = Join-Path $sdkLib $jarName
   $jar = Get-Item -LiteralPath $jarPath -ErrorAction SilentlyContinue
   if (-not $jar -or $jar.Length -le 0) {
       $invalidInstalledJars += $jarName
   }
}
foreach ($libraryName in $requiredSdkNativeLibraries) {
    $libraryPath = Join-Path $sdkRoot ("bin\" + $libraryName)
    $library = Get-Item -LiteralPath $libraryPath -ErrorAction SilentlyContinue
    if (-not $library -or $library.Length -le 0) {
        $invalidInstalledJars += $libraryName
    }
}
if ($invalidInstalledJars.Count -gt 0) {
    $downloadBase = "https://download2.gluonhq.com/openjfx/$($release.version)"
    $archiveName = "openjfx-$($release.version)_windows-x64_bin-sdk.zip"
    $archiveUri = "$downloadBase/$archiveName"
    $checksumUri = "$archiveUri.sha256"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("javafxhotspot-" + [guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $tempRoot $archiveName
    $extractPath = Join-Path $tempRoot 'extract'

    try {
        New-Item -ItemType Directory -Path $tempRoot, $extractPath -Force | Out-Null
        Write-Host "Downloading JavaFX SDK from Gluon..."
        Invoke-WebRequest -Uri $archiveUri -OutFile $archivePath -UseBasicParsing
        $checksumResponse = Invoke-WebRequest -Uri $checksumUri -UseBasicParsing
        $checksumText = if ($checksumResponse.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($checksumResponse.Content)
        } else {
            [string] $checksumResponse.Content
        }
        $checksumMatch = [regex]::Match($checksumText, '(?i)\b([0-9a-f]{64})\b')
        if (-not $checksumMatch.Success) {
            throw "Gluon did not return a valid SHA-256 checksum for $archiveName."
        }

        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne $checksumMatch.Groups[1].Value.ToUpperInvariant()) {
            throw "The JavaFX SDK checksum did not match. The downloaded archive was not installed."
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            foreach ($entry in $zip.Entries) {
                $entryPath = $entry.FullName.Replace('\', '/')
                if ($entryPath.StartsWith('/') -or
                    $entryPath -match '(^|/)\.\.(/|$)' -or
                    $entryPath -match '(^|/)[A-Za-z]:($|/)' -or
                    $entryPath.Contains([char] 0)) {
                    throw "Unsafe path in JavaFX SDK archive: $($entry.FullName)"
                }
            }
        } finally {
            $zip.Dispose()
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
        $extractedLib = Join-Path $extractPath ("javafx-sdk-$($release.version)\lib")
        $extractedBin = Join-Path $extractPath ("javafx-sdk-$($release.version)\bin")
        $missingJars = @()
        foreach ($jarName in $requiredSdkJars) {
            $jarPath = Join-Path $extractedLib $jarName
            $jar = Get-Item -LiteralPath $jarPath -ErrorAction SilentlyContinue
            if (-not $jar -or $jar.Length -le 0) {
                $missingJars += $jarName
            }
        }
        foreach ($libraryName in $requiredSdkNativeLibraries) {
            $libraryPath = Join-Path $extractedBin $libraryName
            $library = Get-Item -LiteralPath $libraryPath -ErrorAction SilentlyContinue
            if (-not $library -or $library.Length -le 0) {
                $missingJars += $libraryName
            }
        }
        if ($missingJars.Count -gt 0) {
            throw "The downloaded archive did not contain valid required JavaFX JAR(s): $($missingJars -join ', ')."
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $sdkRoot) -Force | Out-Null
        $backupSdkRoot = $null
        if (Test-Path -LiteralPath $sdkRoot) {
            $backupSdkRoot = $sdkRoot + '.backup-' + [guid]::NewGuid().ToString('N')
            try {
                Move-Item -LiteralPath $sdkRoot -Destination $backupSdkRoot
            } catch {
                throw "Could not move the existing JavaFX SDK '$sdkRoot' aside before repair. Close programs using it and retry. $($_.Exception.Message)"
            }
        }
        try {
            Move-Item -LiteralPath (Split-Path -Parent $extractedLib) -Destination $sdkRoot
        } catch {
            $installError = $_.Exception.Message
            if ($backupSdkRoot -and (Test-Path -LiteralPath $backupSdkRoot)) {
                try {
                    if (Test-Path -LiteralPath $sdkRoot) {
                        Remove-Item -LiteralPath $sdkRoot -Recurse -Force
                    }
                    Move-Item -LiteralPath $backupSdkRoot -Destination $sdkRoot
                } catch {
                    throw "Could not install the verified JavaFX SDK: $installError. Automatic restoration also failed; the previous SDK remains at '$backupSdkRoot'."
                }
            }
            throw "Could not install the verified JavaFX SDK at '$sdkRoot'. The previous SDK was restored when available. $installError"
        }
        if ($backupSdkRoot -and (Test-Path -LiteralPath $backupSdkRoot)) {
            try {
                Remove-Item -LiteralPath $backupSdkRoot -Recurse -Force
            } catch {
                Write-Warning "JavaFX installed successfully, but the previous SDK backup could not be removed at '$backupSdkRoot'. You can delete that backup after closing programs using it. $($_.Exception.Message)"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            try {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Warning "JavaFX Hotspot could not remove its temporary download folder '$tempRoot': $($_.Exception.Message)"
            }
        }
    }
}

New-Item -ItemType Directory -Path $bin -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installRoot 'scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxc.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafx.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxsetup.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxupdate.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxc-impl.ps1') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafx-impl.ps1') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxsetup-impl.ps1') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxupdate-impl.ps1') -Destination $bin -Force
foreach ($obsoleteCommandScript in @('javafxc.ps1', 'javafx.ps1', 'javafxsetup.ps1', 'javafxupdate.ps1')) {
    $obsoletePath = Join-Path $bin $obsoleteCommandScript
    if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) {
        Remove-Item -LiteralPath $obsoletePath -Force
    }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\common.ps1') -Destination (Join-Path $installRoot 'scripts\common.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'javafx-versions.json') -Destination $installRoot -Force
Set-Content -LiteralPath (Join-Path $sdkRoot 'javafx-version.txt') -Value $release.version -NoNewline

$previousPathToFxFile = Join-Path $installRoot 'previous-path-to-fx.txt'
$managedPathToFxFile = Join-Path $installRoot 'managed-path-to-fx.txt'
$currentUserFxPath = [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
if (Test-Path -LiteralPath $managedPathToFxFile -PathType Leaf) {
    $previousManagedFxPath = if (Test-Path -LiteralPath $managedPathToFxFile -PathType Leaf) {
        (Get-Content -LiteralPath $managedPathToFxFile -Raw).Trim()
    } else { $null }
    if ($currentUserFxPath -and $previousManagedFxPath -and
        (Test-PathEntryEquals -PathEntry $currentUserFxPath -Directory $previousManagedFxPath)) {
        $previousPathToFx = if (Test-Path -LiteralPath $previousPathToFxFile -PathType Leaf) {
            (Get-Content -LiteralPath $previousPathToFxFile -Raw).Trim()
        } else { $null }
    } else {
        $previousPathToFx = $currentUserFxPath
    }
} else {
    $previousPathToFx = $currentUserFxPath
}
Set-Content -LiteralPath $previousPathToFxFile -Value ([string] $previousPathToFx)
Set-Content -LiteralPath $managedPathToFxFile -Value $sdkLib -NoNewline

[Environment]::SetEnvironmentVariable('PATH_TO_FX', $sdkLib, 'User')
$env:PATH_TO_FX = $sdkLib
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @($userPath -split ';' | Where-Object { $_ })
if (-not ($pathEntries | Where-Object { Test-PathEntryEquals -PathEntry $_ -Directory $bin })) {
    $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $bin } else { $bin + ';' + $userPath.Trim(';') }
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
}
$persistedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (@($persistedUserPath -split ';' | Where-Object {
    Test-PathEntryEquals -PathEntry $_ -Directory $bin
}).Count -gt 0)) {
    throw "JavaFX Hotspot was installed, but '$bin' could not be added to your user PATH."
}
$processEntries = @($env:PATH -split ';' | Where-Object {
    $_ -and -not (Test-PathEntryEquals -PathEntry $_ -Directory $bin)
})
$env:PATH = $bin + ';' + ($processEntries -join ';')
if (-not (Publish-EnvironmentChange)) {
    Write-Warning 'Windows did not notify open applications about the PATH update. Open a new terminal or refresh PATH manually.'
}

Write-Host ''
Write-Host "JavaFX $($release.version) installed at $sdkLib"
Write-Host 'Open a new terminal, then use:'
Write-Host '  javafxsetup'
Write-Host '  javafxc MyApp.java'
Write-Host '  javafx MyApp'
Write-Host '  javafxupdate'
Write-Host 'If a command is not recognized in this same PowerShell window, refresh its PATH:'
Write-Host '  $env:Path = @([Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User")) -join ";"'
