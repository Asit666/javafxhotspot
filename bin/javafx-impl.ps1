[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]] $CommandArguments
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    throw 'JavaFX SDK is not configured. Run install.ps1 from the JavaFX Hotspot repository.'
}

if (-not $CommandArguments -or $CommandArguments.Count -eq 0) {
    throw 'Usage: javafx [-Xmx<size>] ClassName [application arguments]'
}

$vmOptions = [System.Collections.Generic.List[string]]::new()
$programArguments = [System.Collections.Generic.List[string]]::new()
$className = $null
$readingProgramArguments = $false
foreach ($argument in $CommandArguments) {
    if (-not $readingProgramArguments -and $argument -eq '--') {
        $readingProgramArguments = $true
        continue
    }

    if (-not $className -and -not $readingProgramArguments -and $argument -match '^-Xm([sx])(.+)$') {
        if ($argument -notmatch '^-Xm[sx][1-9]\d*[kKmMgG]?$') {
            throw "Invalid JVM memory option '$argument'. Use a positive size such as -Xmx512m."
        }
        if (($argument.StartsWith('-Xmx') -and @($vmOptions | Where-Object { $_ -like '-Xmx*' }).Count -gt 0) -or
            ($argument.StartsWith('-Xms') -and @($vmOptions | Where-Object { $_ -like '-Xms*' }).Count -gt 0)) {
            throw "Specify each JVM memory option only once: '$argument'."
        }
        $vmOptions.Add($argument)
        continue
    }

    if (-not $className) {
        $className = $argument
    } else {
        $programArguments.Add($argument)
    }
}

if (-not $className) {
    throw 'Missing main class. Usage: javafx [-Xmx<size>] ClassName [application arguments]'
}

$mainClass = $className
if ($className.EndsWith('.java', [System.StringComparison]::OrdinalIgnoreCase)) {
    $source = Resolve-JavaSource -Source $className
    $simpleName = [System.IO.Path]::GetFileNameWithoutExtension($source)
    $packageName = Get-JavaPackageName -SourcePath $source
    $mainClass = if ($packageName) { "$packageName.$simpleName" } else { $simpleName }
} elseif ($className -notmatch '\.') {
    try {
        $source = Resolve-JavaSource -Source "$className.java"
        $packageName = Get-JavaPackageName -SourcePath $source
        if ($packageName) {
            $mainClass = "$packageName.$className"
        }
    } catch {
        if ($_.Exception.Message -like 'Found multiple files named*') {
            throw
        }
        if ($_.Exception.Message -notlike "Could not find '*.java' in the current folder or its project subfolders.") {
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

$modules = Get-JavaFxModules
$arguments = @('--module-path', $sdk, '--add-modules', $modules) +
    $vmOptions.ToArray() +
    @('-cp', $classDirectory, $mainClass) +
    $programArguments.ToArray()
& $jdk.Java.Path @arguments
exit $LASTEXITCODE
