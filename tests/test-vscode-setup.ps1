$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$setupScript = Join-Path $repositoryRoot 'bin\javafxsetup-impl.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("javafxhotspot-vscode-test-" + [guid]::NewGuid().ToString('N'))
$sdkPath = Join-Path $tempRoot 'fake-sdk\lib'
$projectPath = Join-Path $tempRoot 'project'
$testBin = Join-Path $tempRoot 'bin'
$testScripts = Join-Path $tempRoot 'scripts'
$previousPathToFx = $env:PATH_TO_FX
$previousPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $sdkPath, (Join-Path $projectPath '.vscode'), $testBin, $testScripts -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $sdkPath 'javafx.controls.jar') | Out-Null
    $env:PATH_TO_FX = $sdkPath

    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'bin\javafxsetup.cmd') -Destination $testBin
    Copy-Item -LiteralPath $setupScript -Destination $testBin
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'scripts\common.ps1') -Destination $testScripts
    $env:PATH = $testBin + ';' + $previousPath
    $setupCommand = Get-Command javafxsetup -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    if ([System.IO.Path]::GetExtension($setupCommand.Source) -ne '.cmd') {
        throw 'PowerShell should resolve javafxsetup to its policy-bypassing CMD launcher.'
    }

    $settingsPath = Join-Path $projectPath '.vscode\settings.json'
    @'
{
  "java.project.sourcePaths": ["src/main/java"],
  "java.project.referencedLibraries": [
    "C:/old/javafx-sdk-21.0.1/lib/*.jar",
    "libs/example.jar"
  ],
  "files.encoding": "utf8"
}
'@ | Set-Content -LiteralPath $settingsPath

    & $setupCommand.Source $projectPath
    if ($LASTEXITCODE -ne 0) {
        throw 'The javafxsetup command wrapper failed on the first run.'
    }
    & $setupCommand.Source $projectPath
    if ($LASTEXITCODE -ne 0) {
        throw 'The javafxsetup command wrapper failed on the second run.'
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $libraries = @($settings.'java.project.referencedLibraries')
    $expectedFxPath = $sdkPath.Replace('\', '/') + '/*.jar'
    if ($settings.'java.project.sourcePaths'[0] -ne 'src/main/java' -or
        $settings.'files.encoding' -ne 'utf8' -or
        $libraries -notcontains 'libs/example.jar' -or
        $libraries -notcontains $expectedFxPath -or
        @($libraries | Where-Object { $_ -match 'old/javafx-sdk' }).Count -gt 0 -or
        @($libraries | Where-Object { $_ -eq $expectedFxPath }).Count -ne 1) {
        throw 'javafxsetup did not preserve settings and configure exactly one current JavaFX library.'
    }
} finally {
    $env:PATH_TO_FX = $previousPathToFx
    $env:PATH = $previousPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'VS Code JavaFX classpath setup test passed.'
