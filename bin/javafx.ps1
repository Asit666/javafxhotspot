[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $ClassName,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]] $ProgramArguments
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    throw 'JavaFX SDK is not configured. Run install.ps1 from the JavaFX Hotspot repository.'
}

$mainClass = $ClassName
if ($ClassName.EndsWith('.java', [System.StringComparison]::OrdinalIgnoreCase)) {
    $source = Resolve-JavaSource -Source $ClassName
    $simpleName = [System.IO.Path]::GetFileNameWithoutExtension($source)
    $packageName = Get-JavaPackageName -SourcePath $source
    $mainClass = if ($packageName) { "$packageName.$simpleName" } else { $simpleName }
} elseif ($ClassName -notmatch '\.') {
    try {
        $source = Resolve-JavaSource -Source "$ClassName.java"
        $packageName = Get-JavaPackageName -SourcePath $source
        if ($packageName) {
            $mainClass = "$packageName.$ClassName"
        }
    } catch {
        if ($_.Exception.Message -like 'Found multiple files named*') {
            throw
        }
    }
}

$classDirectory = Join-Path (Get-Location).Path 'build\classes'
if (-not (Test-Path -LiteralPath $classDirectory -PathType Container)) {
    throw 'No build\classes folder found. Run javafxc MyApp.java first.'
}

$jdk = Get-CurrentJdk
Assert-JavaFxMatchesJdk -JdkMajor $jdk.Major -SdkPath $sdk

$arguments = @('--module-path', $sdk, '--add-modules', 'ALL-MODULE-PATH', '-cp', $classDirectory, $mainClass) + $ProgramArguments
& $jdk.Java.Path @arguments
exit $LASTEXITCODE
