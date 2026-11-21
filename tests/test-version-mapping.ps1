$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$fakeJdkBin = Join-Path ([System.IO.Path]::GetTempPath()) ("javafxhotspot fake jdk-" + [guid]::NewGuid().ToString('N'))
$fakeJdkLog = Join-Path $fakeJdkBin 'version-arguments.txt'
$previousPath = $env:PATH
$previousFakeVersion = $env:JAVA_FAKE_VERSION
try {
    New-Item -ItemType Directory -Path $fakeJdkBin -Force | Out-Null
    @"
@echo off
echo %1>>"$fakeJdkLog"
if "%JAVA_FAKE_VERSION%"=="8" (
  echo java version "1.8.0_402" 1>&2
) else (
  echo openjdk version "21.0.2" 1>&2
)
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeJdkBin 'java.cmd') -Encoding ASCII
    @"
@echo off
echo %1>>"$fakeJdkLog"
if "%JAVA_FAKE_VERSION%"=="8" (
  echo javac 1.8.0_402 1>&2
) else (
  echo javac 21.0.2 1>&2
)
exit /b 0
"@ | Set-Content -LiteralPath (Join-Path $fakeJdkBin 'javac.cmd') -Encoding ASCII
    $env:PATH = $fakeJdkBin + ';' + $previousPath
    foreach ($fakeVersion in @(
        @{ Label = '8'; ExpectedMajor = 8 },
        @{ Label = '21'; ExpectedMajor = 21 }
    )) {
        $env:JAVA_FAKE_VERSION = $fakeVersion.Label
        $javaInfo = Get-JavaToolInfo -Name java
        $javacInfo = Get-JavaToolInfo -Name javac
        if ($javaInfo.Major -ne $fakeVersion.ExpectedMajor -or
            $javacInfo.Major -ne $fakeVersion.ExpectedMajor) {
            throw "Java version detection returned java=$($javaInfo.Major), javac=$($javacInfo.Major) for fake JDK $($fakeVersion.Label)."
        }
    }
    $queriedArguments = @(Get-Content -LiteralPath $fakeJdkLog)
    if ($queriedArguments.Count -ne 4 -or @($queriedArguments | Where-Object { $_ -ne '-version' }).Count -gt 0) {
        throw "JDK detection must use the backward-compatible -version option. Observed: $($queriedArguments -join ', ')"
    }
} finally {
    $env:PATH = $previousPath
    $env:JAVA_FAKE_VERSION = $previousFakeVersion
    if (Test-Path -LiteralPath $fakeJdkBin) {
        Remove-Item -LiteralPath $fakeJdkBin -Recurse -Force
    }
}

$cases = @(
    @{ Jdk = 26; Expected = '27.0.1.1' },
    @{ Jdk = 25; Expected = '27.0.1.1' },
    @{ Jdk = 24; Expected = '26.0.2' },
    @{ Jdk = 23; Expected = '25.0.5.1' },
    @{ Jdk = 22; Expected = '24.0.2' },
    @{ Jdk = 21; Expected = '23.0.2' },
    @{ Jdk = 17; Expected = '21.0.13.1' },
    @{ Jdk = 11; Expected = '17.0.21' }
)

foreach ($case in $cases) {
    $actual = Get-CompatibleJavaFxRelease -JdkMajor $case.Jdk
    if ($actual.version -ne $case.Expected) {
        throw "JDK $($case.Jdk): expected JavaFX $($case.Expected), got $($actual.version)."
    }
}

if ((Get-JavaFxModules) -ne 'javafx.controls,javafx.fxml') {
    throw 'The default JavaFX modules should include controls and FXML only.'
}
$previousPathToFx = $env:PATH_TO_FX
$previousUserPathToFx = [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
$sdkFallbackRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot fallback-' + [guid]::NewGuid().ToString('N'))
$incompleteLib = Join-Path $sdkFallbackRoot 'incomplete\lib'
$completeLib = Join-Path $sdkFallbackRoot 'complete\javafx-25.0.5.1-windows-x64\lib'
try {
    New-Item -ItemType Directory -Path $incompleteLib, $completeLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $incompleteLib 'javafx.controls.jar') -Value 'test'
    foreach ($jarName in @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')) {
        Set-Content -LiteralPath (Join-Path $completeLib $jarName) -Value 'test'
    }
    $completeBin = Join-Path (Split-Path -Parent $completeLib) 'bin'
    New-Item -ItemType Directory -Path $completeBin -Force | Out-Null
    foreach ($dllName in @('glass.dll', 'javafx_font.dll', 'javafx_iio.dll', 'prism_d3d.dll', 'prism_sw.dll')) {
        Set-Content -LiteralPath (Join-Path $completeBin $dllName) -Value 'test'
    }
    $env:PATH_TO_FX = $incompleteLib
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $completeLib, 'User')
    if ((Get-InstalledJavaFxPath) -ne $completeLib) {
        throw 'An incomplete process SDK must not hide a complete persisted SDK.'
    }
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $incompleteLib, 'User')
    if ($null -ne (Get-InstalledJavaFxPath)) {
        throw 'An incomplete SDK must not be returned as a usable JavaFX SDK.'
    }
} finally {
    $env:PATH_TO_FX = $previousPathToFx
    [Environment]::SetEnvironmentVariable('PATH_TO_FX', $previousUserPathToFx, 'User')
    if (Test-Path -LiteralPath $sdkFallbackRoot) {
        Remove-Item -LiteralPath $sdkFallbackRoot -Recurse -Force
    }
}
$previousModules = $env:JAVAFX_MODULES
$sdkTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot sdk validation-' + [guid]::NewGuid().ToString('N'))
$sdkTestLib = Join-Path $sdkTestRoot 'lib'
try {
    New-Item -ItemType Directory -Path $sdkTestLib -Force | Out-Null
    foreach ($jarName in @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')) {
        Set-Content -LiteralPath (Join-Path $sdkTestLib $jarName) -Value 'test'
    }
    $sdkTestBin = Join-Path $sdkTestRoot 'bin'
    New-Item -ItemType Directory -Path $sdkTestBin -Force | Out-Null
    foreach ($dllName in @('glass.dll', 'javafx_font.dll', 'javafx_iio.dll', 'prism_d3d.dll', 'prism_sw.dll')) {
        Set-Content -LiteralPath (Join-Path $sdkTestBin $dllName) -Value 'test'
    }
    if (@(Get-JavaFxSdkJars -SdkPath $sdkTestLib).Count -ne 4) {
        throw 'JavaFX SDK validation did not return all installed JARs.'
    }
    if (@(Get-JavaFxSdkJars -SdkPath $sdkTestLib -ValidateNativeLibraries).Count -ne 4) {
        throw 'JavaFX SDK native-library validation did not preserve JAR enumeration.'
    }
    [System.IO.File]::WriteAllText((Join-Path $sdkTestBin 'glass.dll'), '')
    try {
        Get-JavaFxSdkJars -SdkPath $sdkTestLib -ValidateNativeLibraries | Out-Null
        throw 'An empty required JavaFX native DLL should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike '*incomplete or damaged*glass.dll*') {
            throw
        }
    }
    Set-Content -LiteralPath (Join-Path $sdkTestBin 'glass.dll') -Value 'test'
    Remove-Item -LiteralPath (Join-Path $sdkTestBin 'prism_sw.dll') -Force
    try {
        Get-JavaFxSdkJars -SdkPath $sdkTestLib -ValidateNativeLibraries | Out-Null
        throw 'A missing required JavaFX native DLL should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike '*incomplete or damaged*prism_sw.dll*') {
            throw
        }
    }

    $env:JAVAFX_MODULES = 'javafx.controls, javafx.media'
    if ((Get-JavaFxModules) -ne 'javafx.controls,javafx.media') {
        throw 'Custom JavaFX module selection was not preserved.'
    }
    $env:JAVAFX_MODULES = 'javafx.controls, javafx.controls'
    if ((Get-JavaFxModules -SdkPath $sdkTestLib) -ne 'javafx.controls') {
        throw 'Duplicate JavaFX modules should be removed and requested modules validated against the SDK.'
    }
    $env:JAVAFX_MODULES = 'javafx.controls,javafx.web'
    try {
        Get-JavaFxModules -SdkPath $sdkTestLib | Out-Null
        throw 'A JavaFX module missing from the installed SDK should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike "JavaFX module 'javafx.web' was requested*") {
            throw
        }
    }
    $env:JAVAFX_MODULES = 'javafx.Controls'
    try {
        Get-JavaFxModules | Out-Null
        throw 'Non-canonical JavaFX module names should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike 'Invalid JAVAFX_MODULES value*') {
            throw
        }
    }

    [System.IO.File]::WriteAllText((Join-Path $sdkTestLib 'javafx.fxml.jar'), '')
    try {
        Get-JavaFxSdkJars -SdkPath $sdkTestLib | Out-Null
        throw 'An empty required JavaFX JAR should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike '*incomplete or damaged*javafx.fxml.jar*') {
            throw
        }
    }

    $env:JAVAFX_MODULES = 'javafx.controls,javafx.web;Remove-Item'
    try {
        Get-JavaFxModules | Out-Null
        throw 'Invalid JavaFX module input should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike 'Invalid JAVAFX_MODULES value*') {
            throw
        }
    }
} finally {
    $env:JAVAFX_MODULES = $previousModules
    if (Test-Path -LiteralPath $sdkTestRoot) {
        Remove-Item -LiteralPath $sdkTestRoot -Recurse -Force
    }
}

$metadataRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot metadata-' + [guid]::NewGuid().ToString('N'))
$metadataLib = Join-Path $metadataRoot 'MyCustomSDK\lib'
try {
    New-Item -ItemType Directory -Path $metadataLib -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $metadataRoot 'MyCustomSDK\javafx-version.txt') -Value '25.0.5.1'
    Assert-JavaFxMatchesJdk -JdkMajor 25 -SdkPath $metadataLib
    try {
        Assert-JavaFxMatchesJdk -JdkMajor 21 -SdkPath $metadataLib
        throw 'Custom SDK metadata should enforce its minimum JDK.'
    } catch {
        if ($_.Exception.Message -notlike 'JavaFX 25.0.5.1 requires JDK 23*') {
            throw
        }
    }
    Set-Content -LiteralPath (Join-Path $metadataRoot 'MyCustomSDK\javafx-version.txt') -Value '99.0.0'
    try {
        Assert-JavaFxMatchesJdk -JdkMajor 25 -SdkPath $metadataLib
        throw 'Unknown JavaFX SDK versions should be rejected.'
    } catch {
        if ($_.Exception.Message -notlike "Unknown JavaFX SDK version '99.0.0'*") {
            throw
        }
    }
} finally {
    if (Test-Path -LiteralPath $metadataRoot) {
        Remove-Item -LiteralPath $metadataRoot -Recurse -Force
    }
}

Assert-JavaFxMatchesJdk -JdkMajor 25 -SdkPath 'C:\JavaFX\javafx-sdk-25.0.5.1\lib'
try {
    Assert-JavaFxMatchesJdk -JdkMajor 21 -SdkPath 'C:\JavaFX\javafx-25.0.5.1-windows-x64\lib'
    throw 'JavaFX 25 should not run on JDK 21.'
} catch {
    if ($_.Exception.Message -notlike 'JavaFX 25.0.5.1 requires JDK 23*') {
        throw
    }
}

try {
    Get-CompatibleJavaFxRelease -JdkMajor 10 | Out-Null
    throw 'JDK 10 should not have a supported JavaFX release.'
} catch {
    if ($_.Exception.Message -notlike 'JDK 10 is not supported*') {
        throw
    }
}

Write-Host "Passed $($cases.Count) JavaFX/JDK compatibility cases and the unsupported-JDK check."
