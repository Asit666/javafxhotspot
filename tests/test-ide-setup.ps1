$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$setupScript = Join-Path $repositoryRoot 'bin\javafxsetup-impl.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("javafxhotspot ide test-" + [guid]::NewGuid().ToString('N'))
$sdkPath = Join-Path $tempRoot 'fake-sdk\lib'
$projectPath = Join-Path $tempRoot 'project'
$testBin = Join-Path $tempRoot 'bin'
$testScripts = Join-Path $tempRoot 'scripts'
$previousPathToFx = $env:PATH_TO_FX
$previousPath = $env:PATH

try {
    New-Item -ItemType Directory -Path $sdkPath, (Join-Path $projectPath '.vscode'), $testBin, $testScripts -Force | Out-Null
    foreach ($jarName in @('javafx.base.jar', 'javafx.controls.jar', 'javafx.fxml.jar', 'javafx.graphics.jar')) {
        New-Item -ItemType File -Path (Join-Path $sdkPath $jarName) | Out-Null
    }
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
    "libs/example.jar",
  ],
  "example.url": "https://example.com/path/*literal*/",
  "example.escaped": "quote: \" slash: \\ // /*",
  "files.encoding": "utf8", // preserve this unrelated setting
}
'@ | Set-Content -LiteralPath $settingsPath
    New-Item -ItemType Directory -Path @(
        (Join-Path $projectPath 'src\main\java'),
        (Join-Path $projectPath 'src\main\resources'),
        (Join-Path $projectPath 'nbproject')
    ) -Force | Out-Null
    @'
javac.classpath=${file.reference.libs-example.jar}
run.classpath=${javac.classpath}
run.jvmargs=-Xmx512m --module-path "C:/old/javafx-sdk-21.0.1/lib" --add-modules javafx.controls
'@ | Set-Content -LiteralPath (Join-Path $projectPath 'nbproject\project.properties')
    @'
<?xml version="1.0" encoding="UTF-8"?>
<classpath>
  <classpathentry kind="src" path="src/test/java"/>
  <classpathentry kind="lib" path="libs/example.jar"/>
  <classpathentry kind="output" path="bin"/>
</classpath>
'@ | Set-Content -LiteralPath (Join-Path $projectPath '.classpath')
  @'
<?xml version="1.0" encoding="UTF-8"?>
<module type="JAVA_MODULE" version="4">
  <component name="NewModuleRootManager">
  <content url="file://$MODULE_DIR$">
    <sourceFolder url="file://$MODULE_DIR$/src/test/java" isTestSource="true"/>
  </content>
  <orderEntry type="inheritedJdk"/>
  </component>
</module>
'@ | Set-Content -LiteralPath (Join-Path $projectPath 'project.iml')

  & $setupCommand.Source $projectPath -IDE all
    if ($LASTEXITCODE -ne 0) {
        throw 'The javafxsetup command wrapper failed on the first run.'
    }
    & $setupCommand.Source $projectPath -IDE all
    if ($LASTEXITCODE -ne 0) {
        throw 'The javafxsetup command wrapper failed on the second run.'
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $libraries = @($settings.'java.project.referencedLibraries')
    $expectedFxPath = $sdkPath.Replace('\', '/') + '/*.jar'
    [xml] $eclipseClasspath = Get-Content -LiteralPath (Join-Path $projectPath '.classpath') -Raw
    [xml] $eclipseProject = Get-Content -LiteralPath (Join-Path $projectPath '.project') -Raw
    [xml] $intellijLibrary = Get-Content -LiteralPath (Join-Path $projectPath '.idea\libraries\JavaFX_Hotspot.xml') -Raw
    [xml] $intellijModule = Get-Content -LiteralPath (Join-Path $projectPath 'project.iml') -Raw
    [xml] $intellijModules = Get-Content -LiteralPath (Join-Path $projectPath '.idea\modules.xml') -Raw
    $netBeansProperties = Get-Content -LiteralPath (Join-Path $projectPath 'nbproject\project.properties') -Raw
    $eclipseJavaFxEntries = @($eclipseClasspath.classpath.classpathentry | Where-Object { $_.path -match 'javafx.*\.jar' })
    $netBeansRuntimeArgs = @($netBeansProperties -split "`r?`n" | Where-Object { $_ -match '^run\.jvmargs=' })
    $netBeansJavaFxReferenceCount = [regex]::Matches(
        (($netBeansProperties -split "`r?`n" | Where-Object { $_ -match '^javac\.classpath=' }) -join ''),
        'file\.reference\.javafx\.controls\.jar').Count
    if ($settings.'java.project.sourcePaths'[0] -ne 'src/main/java' -or
        $settings.'files.encoding' -ne 'utf8' -or
        $settings.'example.url' -ne 'https://example.com/path/*literal*/' -or
        $settings.'example.escaped' -ne 'quote: " slash: \ // /*' -or
        $libraries -notcontains 'libs/example.jar' -or
        $libraries -notcontains $expectedFxPath -or
        @($libraries | Where-Object { $_ -match 'old/javafx-sdk' }).Count -gt 0 -or
        @($libraries | Where-Object { $_ -eq $expectedFxPath }).Count -ne 1 -or
        $eclipseJavaFxEntries.Count -ne 4 -or
        @($eclipseClasspath.classpath.classpathentry | Where-Object { $_.path -eq 'libs/example.jar' }).Count -ne 1 -or
        @($eclipseClasspath.classpath.classpathentry | Where-Object { $_.path -eq 'src/main/java' }).Count -ne 1 -or
        @($eclipseClasspath.classpath.classpathentry | Where-Object { $_.path -eq 'src/main/resources' }).Count -ne 1 -or
        @($eclipseClasspath.classpath.classpathentry | Where-Object { $_.path -eq 'src/test/java' }).Count -ne 1 -or
        -not $eclipseProject.projectDescription.SelectSingleNode('comment') -or
        -not $eclipseProject.projectDescription.SelectSingleNode('projects') -or
        @($eclipseProject.projectDescription.natures.nature | Where-Object { $_ -eq 'org.eclipse.jdt.core.javanature' }).Count -ne 1 -or
        @($intellijLibrary.component.library.CLASSES.root | Where-Object { $_.url -like 'jar://*/javafx.controls.jar!/' }).Count -ne 1 -or
        @($intellijModule.module.component.content.sourceFolder | Where-Object {
            $_.url -eq 'file://$MODULE_DIR$/src/main/java' -and $_.isTestSource -eq 'false'
        }).Count -ne 1 -or
        @($intellijModule.module.component.content.sourceFolder | Where-Object {
            $_.url -eq 'file://$MODULE_DIR$/src/main/resources' -and $_.type -eq 'java-resource'
        }).Count -ne 1 -or
        @($intellijModule.module.component.content.sourceFolder | Where-Object {
            $_.url -eq 'file://$MODULE_DIR$/src/test/java' -and $_.isTestSource -eq 'true'
        }).Count -ne 1 -or
        @($intellijModule.module.component.orderEntry | Where-Object { $_.name -eq 'JavaFX Hotspot' }).Count -ne 1 -or
        @($intellijModules.project.component.modules.module | Where-Object { $_.filepath -eq '$PROJECT_DIR$/project.iml' }).Count -ne 1 -or
        $netBeansProperties -notmatch 'javac\.classpath=.*file\.reference\.javafx\.controls\.jar' -or
        $netBeansProperties -notmatch 'javac\.classpath=.*file\.reference\.libs-example\.jar' -or
        $netBeansJavaFxReferenceCount -ne 1 -or
        $netBeansRuntimeArgs.Count -ne 1 -or
        $netBeansRuntimeArgs[0] -notmatch [regex]::Escape($sdkPath.Replace('\', '/')) -or
        $netBeansRuntimeArgs[0] -notmatch 'javafx\.controls,javafx\.fxml' -or
        $netBeansRuntimeArgs[0] -match 'old/javafx-sdk') {
        throw 'javafxsetup did not configure the expected IDE projects while preserving existing settings.'
    }

    $invalidProjectPath = Join-Path $tempRoot 'invalid-jsonc-project'
    $invalidSettingsPath = Join-Path $invalidProjectPath '.vscode\settings.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $invalidSettingsPath) -Force | Out-Null
    '{"files.encoding":"utf8"} /* unfinished comment' | Set-Content -LiteralPath $invalidSettingsPath
    $invalidSettingsRejected = $false
    try {
        & $setupScript $invalidProjectPath -IDE vscode
    } catch {
        $invalidSettingsRejected = $_.Exception.Message -match 'Could not read .* as JSONC'
    }
    if (-not $invalidSettingsRejected -or
        (Get-Content -LiteralPath $invalidSettingsPath -Raw) -notmatch 'unfinished comment') {
        throw 'javafxsetup should reject malformed JSONC without overwriting the existing settings.'
    }

    $explicitProjectPath = Join-Path $tempRoot 'explicit-project'
    New-Item -ItemType Directory -Path $explicitProjectPath -Force | Out-Null
    $explicitOutput = @(& $setupCommand.Source -ProjectDirectory $explicitProjectPath -IDE vscode 2>&1 |
        ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0 -or
        ($explicitOutput -join "`n") -notmatch [regex]::Escape($explicitProjectPath) -or
        ($explicitOutput -join "`n") -notmatch 'No Java source folder or project file was found' -or
        -not (Test-Path -LiteralPath (Join-Path $explicitProjectPath '.vscode\settings.json') -PathType Leaf)) {
        throw 'javafxsetup did not clearly report and configure the explicitly supplied project directory.'
    }

    & $setupCommand.Source $projectPath -IDE auto
    if ($LASTEXITCODE -ne 0) {
        throw 'javafxsetup auto-detection failed.'
    }

    foreach ($ide in @('vscode', 'eclipse', 'intellij', 'netbeans', 'zed', 'antigravity')) {
        $ideProjectPath = Join-Path $tempRoot ('only-' + $ide)
        New-Item -ItemType Directory -Path (Join-Path $ideProjectPath 'src\main\java') -Force | Out-Null
        if ($ide -eq 'netbeans') {
            New-Item -ItemType Directory -Path (Join-Path $ideProjectPath 'nbproject') -Force | Out-Null
            'javac.classpath=' | Set-Content -LiteralPath (Join-Path $ideProjectPath 'nbproject\project.properties')
        }

        & $setupCommand.Source $ideProjectPath -IDE $ide
        if ($LASTEXITCODE -ne 0) {
            throw "javafxsetup failed for IDE '$ide'."
        }

        $expectedDirectory = switch ($ide) {
            'vscode' { '.vscode' }
            'eclipse' { $null }
            'intellij' { '.idea' }
            'netbeans' { 'nbproject' }
        }
        if ($expectedDirectory -and -not (Test-Path -LiteralPath (Join-Path $ideProjectPath $expectedDirectory) -PathType Container)) {
            throw "javafxsetup did not create the expected $ide configuration."
        }
        if ($ide -eq 'vscode') {
            $vscodeSettings = Get-Content -LiteralPath (Join-Path $ideProjectPath '.vscode\settings.json') -Raw | ConvertFrom-Json
            if (@($vscodeSettings.'java.project.sourcePaths') -notcontains 'src/main/java') {
                throw 'javafxsetup did not register src/main/java as a VS Code Java source path.'
            }
        }
        if ($ide -eq 'eclipse' -and
            (-not (Test-Path -LiteralPath (Join-Path $ideProjectPath '.project') -PathType Leaf) -or
                -not (Test-Path -LiteralPath (Join-Path $ideProjectPath '.classpath') -PathType Leaf))) {
            throw 'javafxsetup did not create Eclipse project metadata.'
        }
        if ($ide -eq 'zed' -and
            (-not (Test-Path -LiteralPath (Join-Path $ideProjectPath '.project') -PathType Leaf) -or
                -not (Test-Path -LiteralPath (Join-Path $ideProjectPath '.classpath') -PathType Leaf))) {
            throw 'javafxsetup did not create JDTLS project metadata for Zed.'
        }
        if ($ide -eq 'antigravity' -and
            -not (Test-Path -LiteralPath (Join-Path $ideProjectPath '.vscode\settings.json') -PathType Leaf)) {
            throw 'javafxsetup did not create VS Code-compatible settings for Antigravity.'
        }
        if ($ide -ne 'vscode' -and (Test-Path -LiteralPath (Join-Path $ideProjectPath '.vscode') -PathType Container)) {
            if ($ide -ne 'antigravity') {
                throw "javafxsetup configured VS Code when only '$ide' was selected."
            }
        }
    }

    $zedAutoProject = Join-Path $tempRoot 'zed-auto-project'
    New-Item -ItemType Directory -Path (Join-Path $zedAutoProject '.zed') -Force | Out-Null
    & $setupCommand.Source $zedAutoProject -IDE auto
    if ($LASTEXITCODE -ne 0 -or
        -not (Test-Path -LiteralPath (Join-Path $zedAutoProject '.project') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $zedAutoProject '.classpath') -PathType Leaf)) {
        throw 'javafxsetup auto-detection did not configure a Zed project.'
    }
} finally {
    $env:PATH_TO_FX = $previousPathToFx
    $env:PATH = $previousPath
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'Multi-IDE JavaFX setup test passed.'
