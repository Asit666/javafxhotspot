$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$setupScript = Join-Path $repositoryRoot 'bin\javafxsetup.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("javafxhotspot-vscode-test-" + [guid]::NewGuid().ToString('N'))
$sdkPath = Join-Path $tempRoot 'fake-sdk\lib'
$projectPath = Join-Path $tempRoot 'project'
$previousPathToFx = $env:PATH_TO_FX

try {
    New-Item -ItemType Directory -Path $sdkPath, (Join-Path $projectPath '.vscode') -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $sdkPath 'javafx.controls.jar') | Out-Null
    $env:PATH_TO_FX = $sdkPath

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

    & $setupScript -ProjectDirectory $projectPath
    if ($LASTEXITCODE -ne 0) {
        throw 'javafxsetup failed on the first run.'
    }
    & $setupScript -ProjectDirectory $projectPath
    if ($LASTEXITCODE -ne 0) {
        throw 'javafxsetup failed on the second run.'
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
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'VS Code JavaFX classpath setup test passed.'
