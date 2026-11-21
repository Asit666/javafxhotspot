[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Source,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]] $AdditionalSources
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$sdk = Get-RequiredJavaFxPath
$null = Get-JavaFxSdkJars -SdkPath $sdk

$sources = @((Resolve-JavaSource -Source $Source))
foreach ($additionalSource in $AdditionalSources) {
    $sources += Resolve-JavaSource -Source $additionalSource
}

$jdk = Get-CurrentJdk
Assert-JavaFxMatchesJdk -JdkMajor $jdk.Major -SdkPath $sdk

$modules = Get-JavaFxModules -SdkPath $sdk
$projectDirectory = (Get-Location).Path
$buildDirectory = Join-Path $projectDirectory 'build'
$outputDirectory = Join-Path $buildDirectory 'classes'
$stagingDirectory = Join-Path $buildDirectory ('staging-' + [guid]::NewGuid().ToString('N'))

foreach ($directory in @($buildDirectory, $outputDirectory)) {
    if (Test-Path -LiteralPath $directory) {
        $directoryItem = Get-Item -LiteralPath $directory -Force
        if ($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to use linked build directory '$directory'. Use a real project build folder."
        }
    }
    if (Test-Path -LiteralPath $buildDirectory -PathType Container) {
        Get-ChildItem -LiteralPath $buildDirectory -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'staging-*' } |
            ForEach-Object {
                $oldDirectory = $_
                if ($oldDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    throw "Refusing to remove linked build recovery directory '$($oldDirectory.FullName)'."
                }
                Remove-Item -LiteralPath $oldDirectory.FullName -Recurse -Force -ErrorAction Stop
            }
    }
}

New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
$arguments = @('--module-path', $sdk, '--add-modules', $modules, '-d', $stagingDirectory) + $sources
& $jdk.Javac.Path @arguments
if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    exit $LASTEXITCODE
}

try {
    Copy-JavaResources -ProjectDirectory $projectDirectory -OutputDirectory $stagingDirectory
} catch {
    Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

$backupDirectory = $null
if (Test-Path -LiteralPath $outputDirectory) {
    $outputItem = Get-Item -LiteralPath $outputDirectory -Force
    if ($outputItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        throw "Refusing to replace linked build output '$outputDirectory'."
    }
    $linkedOutputDirectories = @(Get-ChildItem -LiteralPath $outputDirectory -Directory -Force -Recurse -ErrorAction Stop |
        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReparsePoint })
    if ($linkedOutputDirectories.Count -gt 0) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        throw "Refusing to replace build output '$outputDirectory' because it contains linked directories: $(($linkedOutputDirectories | ForEach-Object { $_.FullName }) -join '; ')."
    }
    $backupDirectory = Join-Path $buildDirectory ('classes-backup-' + [guid]::NewGuid().ToString('N'))
    try {
        Move-Item -LiteralPath $outputDirectory -Destination $backupDirectory
    } catch {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        throw "Could not preserve the previous build at '$outputDirectory': $($_.Exception.Message)"
    }
}

try {
    Move-Item -LiteralPath $stagingDirectory -Destination $outputDirectory
} catch {
    if ($backupDirectory -and (Test-Path -LiteralPath $backupDirectory)) {
        try {
            Move-Item -LiteralPath $backupDirectory -Destination $outputDirectory -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $stagingDirectory) {
                Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
            throw "Could not publish the successful build, and automatic restoration of the previous build failed. Previous build remains at '$backupDirectory'. $($_.Exception.Message)"
        }
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        if (Test-Path -LiteralPath $stagingDirectory) {
            Remove-Item -LiteralPath $stagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    throw "Could not publish the successful build at '$outputDirectory': $($_.Exception.Message)"
}

if ($backupDirectory -and (Test-Path -LiteralPath $backupDirectory)) {
    try {
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "The successful build was published, but the previous build backup could not be removed at '$backupDirectory': $($_.Exception.Message)"
    }
}
exit 0
