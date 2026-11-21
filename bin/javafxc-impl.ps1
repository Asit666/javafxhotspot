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
        Move-Item -LiteralPath $backupDirectory -Destination $outputDirectory -ErrorAction SilentlyContinue
    }
    throw "Could not publish the successful build at '$outputDirectory': $($_.Exception.Message)"
}

if ($backupDirectory -and (Test-Path -LiteralPath $backupDirectory)) {
    Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
exit 0
