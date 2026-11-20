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
    @{ Jdk = 26; Expected = '27.0.1' },
    @{ Jdk = 25; Expected = '27.0.1' },
    @{ Jdk = 24; Expected = '26.0.2' },
    @{ Jdk = 23; Expected = '25.0.5' },
    @{ Jdk = 22; Expected = '24.0.2' },
    @{ Jdk = 21; Expected = '23.0.2' },
    @{ Jdk = 17; Expected = '21.0.13' },
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
$previousModules = $env:JAVAFX_MODULES
try {
    $env:JAVAFX_MODULES = 'javafx.controls, javafx.media'
    if ((Get-JavaFxModules) -ne 'javafx.controls,javafx.media') {
        throw 'Custom JavaFX module selection was not preserved.'
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
}

Assert-JavaFxMatchesJdk -JdkMajor 25 -SdkPath 'C:\JavaFX\javafx-sdk-25.0.5\lib'
try {
    Assert-JavaFxMatchesJdk -JdkMajor 21 -SdkPath 'C:\JavaFX\javafx-25.0.5-windows-x64\lib'
    throw 'JavaFX 25 should not run on JDK 21.'
} catch {
    if ($_.Exception.Message -notlike 'JavaFX 25.0.5 requires JDK 23*') {
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
