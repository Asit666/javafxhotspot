$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repositoryRoot 'scripts\common.ps1')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('javafxhotspot commands test-' + [guid]::NewGuid().ToString('N'))
$fakeJdkBin = Join-Path $tempRoot 'jdk\bin'
$sdkLib = Join-Path $tempRoot 'sdk\lib'
$projectRoot = Join-Path $tempRoot 'project'
$sourceDirectory = Join-Path $projectRoot 'src\main\java\example'
$resourceDirectory = Join-Path $projectRoot 'src\main\resources\example'
$javacLog = Join-Path $tempRoot 'javac.txt'
$javaLog = Join-Path $tempRoot 'java.txt'
$previousPath = $env:PATH
$previousPathToFx = $env:PATH_TO_FX
$previousOs = $env:OS
$previousLocation = (Get-Location).Path

try {
    New-Item -ItemType Directory -Path $fakeJdkBin, $sdkLib, $sourceDirectory, $resourceDirectory -Force | Out-Null
    foreach ($jarName in @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')) {
        Set-Content -LiteralPath (Join-Path $sdkLib $jarName) -Value 'test'
    }

@'
@echo off
if "%1"=="-version" (
  echo javac 21.0.2 1>&2
) else (
  setlocal enabledelayedexpansion
  set "args="
  :loop
  if "%~1"=="" goto done
  set "args=!args! <%~1>"
  shift
  goto loop
  :done
  echo !args!>>"%JAVAFX_TEST_JAVAC_LOG%"
)
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeJdkBin 'javac.cmd') -Encoding ASCII

@'
@echo off
if "%1"=="-version" (
  echo openjdk version "21.0.2" 1>&2
) else if "%1"=="-XshowSettings:properties" (
  echo os.arch = amd64
) else (
  setlocal enabledelayedexpansion
  set "args="
  :loop
  if "%~1"=="" goto done
  set "args=!args! <%~1>"
  shift
  goto loop
  :done
  echo !args!>>"%JAVAFX_TEST_JAVA_LOG%"
)
exit /b 0
'@ | Set-Content -LiteralPath (Join-Path $fakeJdkBin 'java.cmd') -Encoding ASCII

    @'
// package fake.comment.Example;
package example;
public class MyApp {
    public static void main(String[] args) {}
}
'@ | Set-Content -LiteralPath (Join-Path $sourceDirectory 'MyApp.java') -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $resourceDirectory 'app.css') -Value 'body {}'
    $env:PATH = $fakeJdkBin + ';' + $previousPath
    $env:PATH_TO_FX = $sdkLib
    $env:JAVAFX_TEST_JAVAC_LOG = $javacLog
    $env:JAVAFX_TEST_JAVA_LOG = $javaLog
    $env:OS = 'Windows_NT'

    Set-Location -LiteralPath $projectRoot
    & (Join-Path $repositoryRoot 'bin\javafxc-impl.ps1') 'MyApp.java'
    if ($LASTEXITCODE -ne 0) {
        throw 'javafxc failed in the command-level test.'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'build\classes\example\app.css') -PathType Leaf)) {
        throw 'javafxc did not copy the resource with its project-relative package folder.'
    }

    $javacArguments = Get-Content -LiteralPath $javacLog -Raw
    if ($javacArguments -notmatch [regex]::Escape($sdkLib) -or
        ($javacArguments -notmatch 'javafx\.controls,javafx\.fxml' -and
         $javacArguments -notmatch '<javafx\.controls>.*<javafx\.fxml>')) {
        throw "javafxc did not pass the JavaFX module path and default modules. Arguments: $javacArguments"
    }

    $runArguments = @('-Xms128m', '-Xmx512m', 'MyApp', '-Xmx-is-an-app-argument')
    & (Join-Path $repositoryRoot 'bin\javafx-impl.ps1') @runArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'javafx failed in the command-level test.'
    }
    $javaArguments = Get-Content -LiteralPath $javaLog -Raw
    if ($javaArguments -notmatch '<-Xms128m>' -or
        $javaArguments -notmatch '<-Xmx512m>' -or
        $javaArguments -notmatch '<example\.MyApp>' -or
        $javaArguments -notmatch '<-Xmx-is-an-app-argument>' -or
        $javaArguments.IndexOf('<-Xmx512m>') -gt $javaArguments.IndexOf('<example.MyApp>')) {
        throw "javafx did not preserve JVM options, package resolution, or application arguments. Arguments: $javaArguments"
    }

    $packageName = Get-JavaPackageName -SourcePath (Join-Path $sourceDirectory 'MyApp.java')
    if ($packageName -ne 'example') {
        throw "Package comments or string text were misdetected: $packageName"
    }
} finally {
    Set-Location -LiteralPath $previousLocation
    $env:PATH = $previousPath
    $env:PATH_TO_FX = $previousPathToFx
    $env:OS = $previousOs
    Remove-Item Env:JAVAFX_TEST_JAVAC_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:JAVAFX_TEST_JAVA_LOG -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'JavaFX compile/run command tests passed.'
