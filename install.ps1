[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\common.ps1')

if ($env:OS -ne 'Windows_NT') {
    throw 'The installer currently supports Windows only.'
}

$jdk = Get-CurrentJdk
$release = Get-CompatibleJavaFxRelease -JdkMajor $jdk.Major
$installRoot = Join-Path $env:LOCALAPPDATA 'JavaFXHotspot'
$sdkRoot = Join-Path $installRoot ("sdk\javafx-" + $release.version + "-windows-x64")
$sdkLib = Join-Path $sdkRoot 'lib'
$requiredSdkJars = @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')
$bin = Join-Path $installRoot 'bin'

Write-Host "Detected JDK $($jdk.Major) ($($jdk.Architecture))."
Write-Host "Selected JavaFX $($release.version) (minimum JDK $($release.minimumJdk))."

if (@($requiredSdkJars | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $sdkLib $_) -PathType Leaf)
}).Count -gt 0) {
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
                if ($entryPath.StartsWith('/') -or $entryPath -match '(^|/)\.\.(/|$)' -or $entryPath -match '^[A-Za-z]:') {
                    throw "Unsafe path in JavaFX SDK archive: $($entry.FullName)"
                }
            }
        } finally {
            $zip.Dispose()
        }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
        $extractedLib = Join-Path $extractPath ("javafx-sdk-$($release.version)\lib")
        $missingJars = @($requiredSdkJars | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $extractedLib $_) -PathType Leaf)
        })
        if ($missingJars.Count -gt 0) {
            throw 'The downloaded archive did not contain the expected JavaFX SDK.'
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $sdkRoot) -Force | Out-Null
        if (Test-Path -LiteralPath $sdkRoot) {
            Remove-Item -LiteralPath $sdkRoot -Recurse -Force
        }
        Move-Item -LiteralPath (Split-Path -Parent $extractedLib) -Destination $sdkRoot
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

New-Item -ItemType Directory -Path $bin -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installRoot 'scripts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxc.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafx.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxsetup.cmd') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxc-impl.ps1') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafx-impl.ps1') -Destination $bin -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bin\javafxsetup-impl.ps1') -Destination $bin -Force
foreach ($obsoleteCommandScript in @('javafxc.ps1', 'javafx.ps1', 'javafxsetup.ps1')) {
    $obsoletePath = Join-Path $bin $obsoleteCommandScript
    if (Test-Path -LiteralPath $obsoletePath -PathType Leaf) {
        Remove-Item -LiteralPath $obsoletePath -Force
    }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'scripts\common.ps1') -Destination (Join-Path $installRoot 'scripts\common.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'javafx-versions.json') -Destination $installRoot -Force

[Environment]::SetEnvironmentVariable('PATH_TO_FX', $sdkLib, 'User')
$env:PATH_TO_FX = $sdkLib
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @($userPath -split ';' | Where-Object { $_ })
if (-not ($pathEntries | Where-Object { $_.TrimEnd('\') -ieq $bin.TrimEnd('\') })) {
    $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $bin } else { $bin + ';' + $userPath.Trim(';') }
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
}
$persistedUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not (@($persistedUserPath -split ';' | Where-Object {
    $_.TrimEnd('\') -ieq $bin.TrimEnd('\')
}).Count -gt 0)) {
    throw "JavaFX Hotspot was installed, but '$bin' could not be added to your user PATH."
}
$processEntries = @($env:PATH -split ';' | Where-Object {
    $_ -and $_.TrimEnd('\') -ine $bin.TrimEnd('\')
})
$env:PATH = $bin + ';' + ($processEntries -join ';')

Write-Host ''
Write-Host "JavaFX $($release.version) installed at $sdkLib"
Write-Host 'Open a new terminal, then use:'
Write-Host '  javafxsetup'
Write-Host '  javafxc MyApp.java'
Write-Host '  javafx MyApp'
Write-Host 'If a command is not recognized in this same PowerShell window, refresh its PATH:'
Write-Host '  $env:Path = @([Environment]::GetEnvironmentVariable("Path", "Machine"), [Environment]::GetEnvironmentVariable("Path", "User")) -join ";"'
