[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $ProjectDirectory = (Get-Location).Path,

    [ValidateSet('auto', 'all', 'vscode', 'eclipse', 'intellij', 'netbeans', 'zed', 'antigravity')]
    [string] $IDE = 'all'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

function Read-ProjectXml {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $RootName
    )

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try {
            $document.Load($Path)
        } catch {
            throw "Could not read '$Path' as XML: $($_.Exception.Message)"
        }
        if ($document.DocumentElement.LocalName -ne $RootName) {
            throw "Unexpected XML root in '$Path'. Expected '$RootName'."
        }
    } else {
        $document.AppendChild($document.CreateXmlDeclaration('1.0', 'UTF-8', $null)) | Out-Null
        $document.AppendChild($document.CreateElement($RootName)) | Out-Null
    }

    $document
}

function Write-ProjectXml {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlDocument] $Document,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $writerSettings = New-Object System.Xml.XmlWriterSettings
    $writerSettings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writerSettings.Indent = $true
    $writerSettings.NewLineChars = [Environment]::NewLine
    $writer = [System.Xml.XmlWriter]::Create($Path, $writerSettings)
    try {
        $Document.Save($writer)
    } finally {
        $writer.Dispose()
    }
}

function Add-XmlTextIfMissing {
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement] $Parent,

        [Parameter(Mandatory = $true)]
        [string] $ElementName,

        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    foreach ($child in $Parent.ChildNodes) {
        if ($child.LocalName -eq $ElementName -and $child.InnerText -eq $Text) {
            return
        }
    }
    $element = $Parent.OwnerDocument.CreateElement($ElementName)
    $element.InnerText = $Text
    $Parent.AppendChild($element) | Out-Null
}

function ConvertFrom-JsonWithComments {
    param(
        [Parameter(Mandatory = $true)]
        [string] $JsonText,

        [ref] $HadJsoncSyntax = $null
    )

    $withoutComments = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $lineComment = $false
    $blockComment = $false
    for ($index = 0; $index -lt $JsonText.Length; $index++) {
        $character = $JsonText[$index]
        $nextCharacter = if ($index + 1 -lt $JsonText.Length) { $JsonText[$index + 1] } else { [char] 0 }

        if ($lineComment) {
            if ($character -eq "`r" -or $character -eq "`n") {
                [void] $withoutComments.Append($character)
                $lineComment = $false
            } else {
                [void] $withoutComments.Append(' ')
            }
            continue
        }

        if ($blockComment) {
            if ($character -eq '*' -and $nextCharacter -eq '/') {
                [void] $withoutComments.Append('  ')
                $index++
                $blockComment = $false
            } elseif ($character -eq "`r" -or $character -eq "`n") {
                [void] $withoutComments.Append($character)
            } else {
                [void] $withoutComments.Append(' ')
            }
            continue
        }

        if ($inString) {
            [void] $withoutComments.Append($character)
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '/' -and $nextCharacter -eq '/') {
            if ($HadJsoncSyntax) { $HadJsoncSyntax.Value = $true }
            [void] $withoutComments.Append('  ')
            $index++
            $lineComment = $true
        } elseif ($character -eq '/' -and $nextCharacter -eq '*') {
            if ($HadJsoncSyntax) { $HadJsoncSyntax.Value = $true }
            [void] $withoutComments.Append('  ')
            $index++
            $blockComment = $true
        } else {
            [void] $withoutComments.Append($character)
            if ($character -eq '"') {
                $inString = $true
            }
        }
    }

    if ($blockComment) {
        throw 'Unterminated JSONC block comment.'
    }

    $commentFree = $withoutComments.ToString()
    $json = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $commentFree.Length; $index++) {
        $character = $commentFree[$index]
        if ($inString) {
            [void] $json.Append($character)
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
            [void] $json.Append($character)
        } elseif ($character -eq ',') {
            $lookahead = $index + 1
            while ($lookahead -lt $commentFree.Length -and [char]::IsWhiteSpace($commentFree[$lookahead])) {
                $lookahead++
            }
            if ($lookahead -ge $commentFree.Length -or $commentFree[$lookahead] -notin @('}', ']')) {
                [void] $json.Append($character)
            } elseif ($HadJsoncSyntax) {
                $HadJsoncSyntax.Value = $true
            }
        } else {
            [void] $json.Append($character)
        }
    }

    ConvertFrom-Json -InputObject $json.ToString()
}

function Set-VsCodeClassPath {
    param([string] $Root, [string] $Sdk)

    $directory = Join-Path $Root '.vscode'
    $path = Join-Path $directory 'settings.json'
    $settings = [pscustomobject]@{}
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $settingsText = Get-Content -LiteralPath $path -Raw
        $hadJsoncSyntax = $false
        try {
            $settings = ConvertFrom-JsonWithComments -JsonText $settingsText -HadJsoncSyntax ([ref]$hadJsoncSyntax)
        } catch {
            throw "Could not read '$path' as JSONC. Check its JSON syntax before running javafxsetup. $($_.Exception.Message)"
        }
        if ($hadJsoncSyntax) {
            Write-Warning "Converting '$path' from JSONC to standard JSON; comments and trailing commas will be removed."
        }
        if ($null -eq $settings -or $settings -is [array] -or $settings -is [string] -or $settings -is [ValueType]) {
            throw "Expected '$path' to contain a JSON object."
        }
    }

    $property = $settings.PSObject.Properties['java.project.referencedLibraries']
    $libraries = @()
    if ($property -and $null -ne $property.Value) {
        $libraries = @($property.Value)
    }
    $libraries = @($libraries | Where-Object {
        $_ -and $_ -notmatch '(?i)javafx-sdk-[^/\\]+[/\\]lib[/\\].*\.jar'
    })
    $libraryPath = ($Sdk.TrimEnd('\', '/') + '/*.jar').Replace('\', '/')
    if ($libraries -notcontains $libraryPath) {
        $libraries += $libraryPath
    }
    if ($property) {
        $property.Value = @($libraries)
    } else {
        $settings | Add-Member -MemberType NoteProperty -Name 'java.project.referencedLibraries' -Value @($libraries)
    }

    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $json = ConvertTo-Json -InputObject $settings -Depth 100
    [System.IO.File]::WriteAllText(
        $path,
        $json + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false)))
}

function Set-EclipseClassPath {
    param([string] $Root, [System.IO.FileInfo[]] $Jars)

    $projectPath = Join-Path $Root '.project'
    $project = Read-ProjectXml -Path $projectPath -RootName 'projectDescription'
    if (-not $project.DocumentElement.SelectSingleNode('name')) {
        Add-XmlTextIfMissing -Parent $project.DocumentElement -ElementName 'name' -Text (Split-Path -Leaf $Root)
    }
    foreach ($elementName in @('comment', 'projects')) {
        if (-not $project.DocumentElement.SelectSingleNode($elementName)) {
            $element = $project.CreateElement($elementName)
            $buildSpecNode = $project.DocumentElement.SelectSingleNode('buildSpec')
            if ($buildSpecNode) {
                $project.DocumentElement.InsertBefore($element, $buildSpecNode) | Out-Null
            } else {
                $project.DocumentElement.AppendChild($element) | Out-Null
            }
        }
    }
    $buildSpec = $project.DocumentElement.SelectSingleNode('buildSpec')
    if (-not $buildSpec) {
        $buildSpec = $project.CreateElement('buildSpec')
        $naturesNode = $project.DocumentElement.SelectSingleNode('natures')
        if ($naturesNode) {
            $project.DocumentElement.InsertBefore($buildSpec, $naturesNode) | Out-Null
        } else {
            $project.DocumentElement.AppendChild($buildSpec) | Out-Null
        }
    }
    $hasJavaBuilder = $false
    foreach ($command in @($buildSpec.SelectNodes('buildCommand'))) {
        $name = $command.SelectSingleNode('name')
        if ($name -and $name.InnerText -eq 'org.eclipse.jdt.core.javabuilder') {
            $hasJavaBuilder = $true
        }
    }
    if (-not $hasJavaBuilder) {
        $command = $project.CreateElement('buildCommand')
        $name = $project.CreateElement('name')
        $name.InnerText = 'org.eclipse.jdt.core.javabuilder'
        $command.AppendChild($name) | Out-Null
        $arguments = $project.CreateElement('arguments')
        $command.AppendChild($arguments) | Out-Null
        $buildSpec.AppendChild($command) | Out-Null
    }
    $natures = $project.DocumentElement.SelectSingleNode('natures')
    if (-not $natures) {
        $natures = $project.CreateElement('natures')
        $project.DocumentElement.AppendChild($natures) | Out-Null
    }
    Add-XmlTextIfMissing -Parent $natures -ElementName 'nature' -Text 'org.eclipse.jdt.core.javanature'
    Write-ProjectXml -Document $project -Path $projectPath

    $classpathPath = Join-Path $Root '.classpath'
    $classpath = Read-ProjectXml -Path $classpathPath -RootName 'classpath'
    foreach ($entry in @($classpath.DocumentElement.SelectNodes('classpathentry'))) {
        $entryPath = $entry.GetAttribute('path')
        if ($entry.GetAttribute('kind') -eq 'lib' -and
            ($entryPath -match '(?i)javafx-sdk[^/\\]*[/\\]lib[/\\]' -or
                [System.IO.Path]::GetFileName($entryPath) -match '(?i)^javafx.*\.jar$')) {
            $classpath.DocumentElement.RemoveChild($entry) | Out-Null
        }
    }
    foreach ($sourceRoot in @(
        @{ Path = 'src/main/java'; Directory = 'src\main\java' },
        @{ Path = 'src/main/resources'; Directory = 'src\main\resources' }
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $sourceRoot.Directory) -PathType Container)) {
            continue
        }

        $rootCovered = $false
        foreach ($sourceEntry in @($classpath.DocumentElement.SelectNodes("classpathentry[@kind='src']"))) {
            $sourcePath = $sourceEntry.GetAttribute('path').Replace('\', '/').TrimEnd('/')
            if ($sourcePath -eq $sourceRoot.Path -or
                ($sourcePath -and $sourceRoot.Path.StartsWith($sourcePath + '/', [System.StringComparison]::OrdinalIgnoreCase))) {
                $rootCovered = $true
                break
            }
        }
        if (-not $rootCovered) {
            $sourceEntry = $classpath.CreateElement('classpathentry')
            $sourceEntry.SetAttribute('kind', 'src')
            $sourceEntry.SetAttribute('path', $sourceRoot.Path)
            $classpath.DocumentElement.AppendChild($sourceEntry) | Out-Null
        }
    }
    foreach ($jar in $Jars) {
        $entry = $classpath.CreateElement('classpathentry')
        $entry.SetAttribute('kind', 'lib')
        $entry.SetAttribute('path', $jar.FullName.Replace('\', '/'))
        $classpath.DocumentElement.AppendChild($entry) | Out-Null
    }
    if (@($classpath.DocumentElement.SelectNodes("classpathentry[@kind='output']")).Count -eq 0) {
        $outputEntry = $classpath.CreateElement('classpathentry')
        $outputEntry.SetAttribute('kind', 'output')
        $outputEntry.SetAttribute('path', 'bin')
        $classpath.DocumentElement.AppendChild($outputEntry) | Out-Null
    }
    Write-ProjectXml -Document $classpath -Path $classpathPath
}

function Set-IntelliJClassPath {
    param([string] $Root, [System.IO.FileInfo[]] $Jars)

    $ideaDirectory = Join-Path $Root '.idea'
    $libraryDirectory = Join-Path $ideaDirectory 'libraries'
    New-Item -ItemType Directory -Path $libraryDirectory -Force | Out-Null
    $libraryPath = Join-Path $libraryDirectory 'JavaFX_Hotspot.xml'
    $library = Read-ProjectXml -Path $libraryPath -RootName 'component'
    $library.DocumentElement.SetAttribute('name', 'libraryTable')
    foreach ($child in @($library.DocumentElement.ChildNodes)) {
        if ($child.LocalName -eq 'library') {
            $library.DocumentElement.RemoveChild($child) | Out-Null
        }
    }
    $entry = $library.CreateElement('library')
    $entry.SetAttribute('name', 'JavaFX Hotspot')
    $classes = $library.CreateElement('CLASSES')
    foreach ($jar in $Jars) {
        $jarRootElement = $library.CreateElement('root')
        $jarRootElement.SetAttribute('url', 'jar://' + $jar.FullName.Replace('\', '/') + '!/')
        $classes.AppendChild($jarRootElement) | Out-Null
    }
    $entry.AppendChild($classes) | Out-Null
    $entry.AppendChild($library.CreateElement('JAVADOC')) | Out-Null
    $entry.AppendChild($library.CreateElement('SOURCES')) | Out-Null
    $library.DocumentElement.AppendChild($entry) | Out-Null
    Write-ProjectXml -Document $library -Path $libraryPath

    $modules = @(Get-ChildItem -LiteralPath $Root -Filter '*.iml' -File)
    $createdModule = $false
    if ($modules.Count -eq 0) {
        $modulePath = Join-Path $Root ((Split-Path -Leaf $Root) + '.iml')
        $module = New-Object System.Xml.XmlDocument
        $module.AppendChild($module.CreateXmlDeclaration('1.0', 'UTF-8', $null)) | Out-Null
        $moduleRoot = $module.CreateElement('module')
        $moduleRoot.SetAttribute('type', 'JAVA_MODULE')
        $moduleRoot.SetAttribute('version', '4')
        $module.AppendChild($moduleRoot) | Out-Null
        $manager = $module.CreateElement('component')
        $manager.SetAttribute('name', 'NewModuleRootManager')
        $manager.SetAttribute('inherit-compiler-output', 'true')
        $manager.AppendChild($module.CreateElement('exclude-output')) | Out-Null
        $content = $module.CreateElement('content')
        $content.SetAttribute('url', 'file://$MODULE_DIR$')
        $source = $module.CreateElement('sourceFolder')
        $source.SetAttribute('url', 'file://$MODULE_DIR$/src/main/java')
        $source.SetAttribute('isTestSource', 'false')
        $content.AppendChild($source) | Out-Null
        $manager.AppendChild($content) | Out-Null
        $orderEntry = $module.CreateElement('orderEntry')
        $orderEntry.SetAttribute('type', 'inheritedJdk')
        $manager.AppendChild($orderEntry) | Out-Null
        $orderEntry = $module.CreateElement('orderEntry')
        $orderEntry.SetAttribute('type', 'sourceFolder')
        $orderEntry.SetAttribute('forTests', 'false')
        $manager.AppendChild($orderEntry) | Out-Null
        $orderEntry = $module.CreateElement('orderEntry')
        $orderEntry.SetAttribute('type', 'library')
        $orderEntry.SetAttribute('name', 'JavaFX Hotspot')
        $orderEntry.SetAttribute('level', 'project')
        $manager.AppendChild($orderEntry) | Out-Null
        $moduleRoot.AppendChild($manager) | Out-Null
        Write-ProjectXml -Document $module -Path $modulePath
        $modules = @(Get-Item -LiteralPath $modulePath)
        $createdModule = $true
    }

    foreach ($moduleFile in $modules) {
        $module = Read-ProjectXml -Path $moduleFile.FullName -RootName 'module'
        $manager = $module.DocumentElement.SelectSingleNode("component[@name='NewModuleRootManager']")
        if (-not $manager) {
            $manager = $module.CreateElement('component')
            $manager.SetAttribute('name', 'NewModuleRootManager')
            $module.DocumentElement.AppendChild($manager) | Out-Null
        }
        $resourceDirectory = Join-Path $Root 'src\main\resources'
        if (Test-Path -LiteralPath $resourceDirectory -PathType Container) {
            $content = $manager.SelectSingleNode('content')
            if (-not $content) {
                $content = $module.CreateElement('content')
                $content.SetAttribute('url', 'file://$MODULE_DIR$')
                $manager.AppendChild($content) | Out-Null
            }
            $resourceUrl = 'file://$MODULE_DIR$/src/main/resources'
            $hasResourceRoot = $false
            foreach ($sourceFolder in @($content.SelectNodes('sourceFolder'))) {
                if ($sourceFolder.GetAttribute('url') -eq $resourceUrl) {
                    $sourceFolder.SetAttribute('type', 'java-resource')
                    $hasResourceRoot = $true
                }
            }
            if (-not $hasResourceRoot) {
                $sourceFolder = $module.CreateElement('sourceFolder')
                $sourceFolder.SetAttribute('url', $resourceUrl)
                $sourceFolder.SetAttribute('type', 'java-resource')
                $content.AppendChild($sourceFolder) | Out-Null
            }
        }
        $hasLibrary = $false
        foreach ($orderEntry in @($manager.SelectNodes("orderEntry[@type='library']"))) {
            if ($orderEntry.GetAttribute('name') -eq 'JavaFX Hotspot' -and
                $orderEntry.GetAttribute('level') -eq 'project') {
                $hasLibrary = $true
            }
        }
        if (-not $hasLibrary) {
            $orderEntry = $module.CreateElement('orderEntry')
            $orderEntry.SetAttribute('type', 'library')
            $orderEntry.SetAttribute('name', 'JavaFX Hotspot')
            $orderEntry.SetAttribute('level', 'project')
            $manager.AppendChild($orderEntry) | Out-Null
        }
        Write-ProjectXml -Document $module -Path $moduleFile.FullName
    }

    $modulesPath = Join-Path $ideaDirectory 'modules.xml'
    $modulesDocument = Read-ProjectXml -Path $modulesPath -RootName 'project'
    $moduleManager = $modulesDocument.DocumentElement.SelectSingleNode("component[@name='ProjectModuleManager']")
    if (-not $moduleManager) {
        $moduleManager = $modulesDocument.CreateElement('component')
        $moduleManager.SetAttribute('name', 'ProjectModuleManager')
        $modulesDocument.DocumentElement.AppendChild($moduleManager) | Out-Null
    }
    $moduleList = $moduleManager.SelectSingleNode('modules')
    if (-not $moduleList) {
        $moduleList = $modulesDocument.CreateElement('modules')
        $moduleManager.AppendChild($moduleList) | Out-Null
    }
    foreach ($moduleFile in $modules) {
        $relative = $moduleFile.Name
        $url = 'file://$PROJECT_DIR$/' + $relative
        $exists = $false
        foreach ($moduleElement in @($moduleList.SelectNodes('module'))) {
            if ($moduleElement.GetAttribute('fileurl') -eq $url) {
                $exists = $true
            }
        }
        if (-not $exists) {
            $moduleElement = $modulesDocument.CreateElement('module')
            $moduleElement.SetAttribute('fileurl', $url)
            $moduleElement.SetAttribute('filepath', '$PROJECT_DIR$/' + $relative)
            $moduleList.AppendChild($moduleElement) | Out-Null
        }
    }
    Write-ProjectXml -Document $modulesDocument -Path $modulesPath
    if ($createdModule) {
        Write-Host "Created IntelliJ module '$($modules[0].Name)' with JavaFX configured."
    }
}

function Set-NetBeansClassPath {
    param([string] $Root, [System.IO.FileInfo[]] $Jars, [string] $Sdk, [string] $Modules)

    $propertiesPath = Join-Path $Root 'nbproject\project.properties'
    if (-not (Test-Path -LiteralPath $propertiesPath -PathType Leaf)) {
        return $false
    }

    $lines = @(Get-Content -LiteralPath $propertiesPath)
    $references = @()
    foreach ($jar in $Jars) {
        $propertyName = 'file.reference.' + $jar.Name
        $reference = '${' + $propertyName + '}'
        $references += $reference
        $propertyLine = $propertyName + '=' + $jar.FullName.Replace('\', '/')
        $found = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match ('^' + [regex]::Escape($propertyName) + '=')) {
                $lines[$index] = $propertyLine
                $found = $true
                break
            }
        }
        if (-not $found) {
            $lines += $propertyLine
        }
    }

    foreach ($key in @('javac.classpath', 'run.classpath')) {
        $found = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match ('^' + [regex]::Escape($key) + '=')) {
                $current = $lines[$index].Substring($key.Length + 1)
                foreach ($reference in $references) {
                    if ($current -notlike "*$reference*") {
                        $current = if ($current) { $current + ';' + $reference } else { $reference }
                    }
                }
                $lines[$index] = $key + '=' + $current
                $found = $true
                break
            }
        }
        if (-not $found) {
            $lines += $key + '=' + ($references -join ';')
        }
    }

    $runtimeSdkPath = $Sdk.Replace('\', '/')
    $runtimeArgs = '--module-path "' + $runtimeSdkPath + '" --add-modules ' + $Modules
    $foundRuntime = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^run\.jvmargs=') {
            $current = $lines[$index].Substring('run.jvmargs='.Length)
            if ($current -match '--module-path\s+(?:"[^"]+"|\S+)') {
                $current = [regex]::Replace($current, '--module-path\s+(?:"[^"]+"|\S+)', [System.Text.RegularExpressions.MatchEvaluator] {
                    param($match)
                    '--module-path "' + $runtimeSdkPath + '"'
                })
            } else {
                $current = ($current + ' ' + $runtimeArgs).Trim()
            }
            if ($current -match '--add-modules\s+\S+') {
                $current = [regex]::Replace($current, '--add-modules\s+\S+', '--add-modules ' + $Modules)
            }
            $lines[$index] = 'run.jvmargs=' + $current
            $foundRuntime = $true
            break
        }
    }
    if (-not $foundRuntime) {
        $lines += 'run.jvmargs=' + $runtimeArgs
    }

    [System.IO.File]::WriteAllLines($propertiesPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    $true
}

$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    throw 'JavaFX SDK is not configured. Run install.ps1 from the JavaFX Hotspot repository.'
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    throw "Project folder does not exist: $projectPath"
}

$jars = @(Get-ChildItem -LiteralPath $sdk -Filter 'javafx*.jar' -File | Sort-Object Name)
if ($jars.Count -eq 0) {
    throw "No JavaFX JARs were found in the installed SDK folder '$sdk'."
}
$modules = Get-JavaFxModules
$configured = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

if ($IDE -in @('all', 'vscode', 'antigravity') -or
    ($IDE -eq 'auto' -and (Test-Path -LiteralPath (Join-Path $projectPath '.vscode') -PathType Container))) {
    Set-VsCodeClassPath -Root $projectPath -Sdk $sdk
    if ($IDE -eq 'antigravity') {
        $configured.Add('Antigravity (VS Code workspace settings)')
    } else {
        $configured.Add('VS Code')
    }
}

if ($IDE -in @('all', 'eclipse', 'zed') -or
    ($IDE -eq 'auto' -and ((Test-Path (Join-Path $projectPath '.project')) -or
        (Test-Path (Join-Path $projectPath '.classpath')) -or
        (Test-Path (Join-Path $projectPath '.zed') -PathType Container)))) {
    Set-EclipseClassPath -Root $projectPath -Jars $jars
    if ($IDE -eq 'zed') {
        $configured.Add('Zed (JDTLS project classpath)')
    } else {
        $configured.Add('Eclipse')
        if ($IDE -eq 'all' -or ($IDE -eq 'auto' -and
            (Test-Path -LiteralPath (Join-Path $projectPath '.zed') -PathType Container))) {
            $configured.Add('Zed (JDTLS project classpath)')
        }
    }
}

if ($IDE -in @('all', 'intellij') -or
    ($IDE -eq 'auto' -and ((Test-Path (Join-Path $projectPath '.idea')) -or
        @(Get-ChildItem -LiteralPath $projectPath -Filter '*.iml' -File).Count -gt 0))) {
    Set-IntelliJClassPath -Root $projectPath -Jars $jars
    $configured.Add('IntelliJ IDEA')
}

$netBeansProperties = Join-Path $projectPath 'nbproject\project.properties'
if (($IDE -in @('all', 'netbeans') -or $IDE -eq 'auto') -and
    (Test-Path -LiteralPath $netBeansProperties -PathType Leaf)) {
    Set-NetBeansClassPath -Root $projectPath -Jars $jars -Sdk $sdk -Modules $modules | Out-Null
    $configured.Add('Apache NetBeans')
} elseif ($IDE -eq 'netbeans') {
    throw "No NetBeans Ant project was found at '$projectPath'. Open or create a Java with Ant project first."
} elseif ($IDE -ne 'netbeans') {
    $skipped.Add('Apache NetBeans (no nbproject\project.properties found)')
}

Write-Host "JavaFX configured for: $($configured -join ', ')"
foreach ($message in $skipped) {
    Write-Host "Skipped $message"
}
Write-Host 'If an IDE still shows stale import errors, reload the project or refresh its Java classpath.'
