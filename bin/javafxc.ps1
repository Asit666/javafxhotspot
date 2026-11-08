[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $Source,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]] $AdditionalSources
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    throw 'JavaFX SDK is not configured. Run install.ps1 from the JavaFX Hotspot repository.'
}

$sources = @((Resolve-JavaSource -Source $Source))
foreach ($additionalSource in $AdditionalSources) {
    $sources += Resolve-JavaSource -Source $additionalSource
}

$outputDirectory = Join-Path (Get-Location).Path 'build\classes'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$jdk = Get-CurrentJdk
Assert-JavaFxMatchesJdk -JdkMajor $jdk.Major -SdkPath $sdk

$arguments = @('--module-path', $sdk, '--add-modules', 'ALL-MODULE-PATH', '-d', $outputDirectory) + $sources
& $jdk.Javac.Path @arguments
exit $LASTEXITCODE
