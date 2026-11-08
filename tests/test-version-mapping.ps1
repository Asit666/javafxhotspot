$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

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
