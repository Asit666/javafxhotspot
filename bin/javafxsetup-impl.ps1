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

    $sourceDirectory = Join-Path $Root 'src\main\java'
    if (Test-Path -LiteralPath $sourceDirectory -PathType Container) {
        $sourceProperty = $settings.PSObject.Properties['java.project.sourcePaths']
        $sourcePaths = @()
        if ($sourceProperty -and $null -ne $sourceProperty.Value) {
            if ($sourceProperty.Value -isnot [array]) {
                throw "Expected 'java.project.sourcePaths' in '$path' to be an array."
            }
            $sourcePaths = @($sourceProperty.Value)
        }
        if ($sourcePaths -notcontains 'src/main/java') {
            $sourcePaths += 'src/main/java'
        }
        if ($sourceProperty) {
            $sourceProperty.Value = $sourcePaths
        } else {
            $settings | Add-Member -MemberType NoteProperty -Name 'java.project.sourcePaths' -Value $sourcePaths
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

    $modules = @()
    $projectPrefix = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($moduleElement in @($moduleList.SelectNodes('module'))) {
        $moduleRelativePath = $moduleElement.GetAttribute('filepath')
        if (-not $moduleRelativePath.StartsWith('$PROJECT_DIR$/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $moduleUrl = $moduleElement.GetAttribute('fileurl')
            if ($moduleUrl.StartsWith('file://$PROJECT_DIR$/', [System.StringComparison]::OrdinalIgnoreCase)) {
                $moduleRelativePath = $moduleUrl.Substring('file://$PROJECT_DIR$/'.Length)
            } else {
                continue
            }
        } else {
            $moduleRelativePath = $moduleRelativePath.Substring('$PROJECT_DIR$/'.Length)
        }

        $candidatePath = [System.IO.Path]::GetFullPath((Join-Path $Root $moduleRelativePath.Replace('/', '\')))
        if (-not $candidatePath.StartsWith($projectPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $modules += Get-Item -LiteralPath $candidatePath
        } else {
            $moduleList.RemoveChild($moduleElement) | Out-Null
        }
    }

    foreach ($moduleFile in @(Get-ChildItem -LiteralPath $Root -Filter '*.iml' -File)) {
        if (@($modules | Where-Object { $_.FullName -eq $moduleFile.FullName }).Count -eq 0) {
            $modules += $moduleFile
        }
    }

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
    }

    foreach ($moduleFile in $modules) {
        $module = Read-ProjectXml -Path $moduleFile.FullName -RootName 'module'
        $manager = $module.DocumentElement.SelectSingleNode("component[@name='NewModuleRootManager']")
        if (-not $manager) {
            $manager = $module.CreateElement('component')
            $manager.SetAttribute('name', 'NewModuleRootManager')
            $module.DocumentElement.AppendChild($manager) | Out-Null
        }
        $content = $manager.SelectSingleNode('content')
        foreach ($sourceRoot in @(
            @{ Directory = 'src\main\java'; Url = 'file://$MODULE_DIR$/src/main/java'; Type = $null },
            @{ Directory = 'src\main\resources'; Url = 'file://$MODULE_DIR$/src/main/resources'; Type = 'java-resource' }
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $sourceRoot.Directory) -PathType Container)) {
                continue
            }
            if (-not $content) {
                $content = $module.CreateElement('content')
                $content.SetAttribute('url', 'file://$MODULE_DIR$')
                $manager.AppendChild($content) | Out-Null
            }

            $sourceFolder = @($content.SelectNodes('sourceFolder') | Where-Object {
                $_.GetAttribute('url') -eq $sourceRoot.Url
            }) | Select-Object -First 1
            if (-not $sourceFolder) {
                $sourceFolder = $module.CreateElement('sourceFolder')
                $sourceFolder.SetAttribute('url', $sourceRoot.Url)
                $content.AppendChild($sourceFolder) | Out-Null
            }
            if ($sourceRoot.Type) {
                $sourceFolder.SetAttribute('type', $sourceRoot.Type)
            } elseif (-not $sourceFolder.HasAttribute('isTestSource')) {
                $sourceFolder.SetAttribute('isTestSource', 'false')
            }
        }
        foreach ($orderEntry in @($manager.SelectNodes('orderEntry'))) {
            $library = $orderEntry.SelectSingleNode('library')
            if (($orderEntry.GetAttribute('type') -eq 'library' -and
                    $orderEntry.GetAttribute('name') -eq 'JavaFX Hotspot') -or
                ($orderEntry.GetAttribute('type') -eq 'module-library' -and
                    $library -and $library.GetAttribute('name') -eq 'JavaFX Hotspot')) {
                $manager.RemoveChild($orderEntry) | Out-Null
            }
        }
        $orderEntry = $module.CreateElement('orderEntry')
        $orderEntry.SetAttribute('type', 'module-library')
        $moduleLibrary = $module.CreateElement('library')
        $moduleLibrary.SetAttribute('name', 'JavaFX Hotspot')
        $classes = $module.CreateElement('CLASSES')
        foreach ($jar in $Jars) {
            $jarRootElement = $module.CreateElement('root')
            $jarRootElement.SetAttribute('url', 'jar://' + $jar.FullName.Replace('\', '/') + '!/')
            $classes.AppendChild($jarRootElement) | Out-Null
        }
        $moduleLibrary.AppendChild($classes) | Out-Null
        $moduleLibrary.AppendChild($module.CreateElement('JAVADOC')) | Out-Null
        $moduleLibrary.AppendChild($module.CreateElement('SOURCES')) | Out-Null
        $orderEntry.AppendChild($moduleLibrary) | Out-Null
        $manager.AppendChild($orderEntry) | Out-Null
        Write-ProjectXml -Document $module -Path $moduleFile.FullName
    }

    foreach ($moduleFile in $modules) {
        $relative = $moduleFile.FullName.Substring($projectPrefix.Length).Replace('\', '/')
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

function Invoke-IdeSetup {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Action,

        [Parameter(Mandatory = $true)]
        [scriptblock] $Validate,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]] $Configured,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]] $Failures
    )

    try {
        & $Action
        & $Validate
        $Configured.Add($Name)
        Write-Host "[PASS] ${Name}: setup files written and verified." -ForegroundColor Green
    } catch {
        $reason = $_.Exception.Message
        $Failures.Add("${Name}: $reason")
        Write-Host "[FAIL] ${Name}: $reason" -ForegroundColor Red
    }
}

$sdkCandidates = @(
    $env:PATH_TO_FX,
    [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    $candidateDescription = if ($sdkCandidates.Count -gt 0) {
        $sdkCandidates -join '; '
    } else {
        '(PATH_TO_FX is not set)'
    }
    $message = "JavaFX SDK was not found. Checked PATH_TO_FX location(s): $candidateDescription. Each SDK folder must contain javafx.controls.jar. Run install.ps1, then open a new terminal."
    Write-Host "[FAIL] JavaFX SDK: $message" -ForegroundColor Red
    throw $message
}

try {
    $projectPath = [System.IO.Path]::GetFullPath($ProjectDirectory)
} catch {
    $message = "Could not resolve project folder '$ProjectDirectory': $($_.Exception.Message)"
    Write-Host "[FAIL] Project folder: $message" -ForegroundColor Red
    throw $message
}
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    $message = "Project folder does not exist: $projectPath"
    Write-Host "[FAIL] Project folder: $message" -ForegroundColor Red
    throw $message
}

$sourceDirectories = @(
    'src\main\java',
    'src\test\java',
    'src',
    'java'
)
$hasSourceDirectory = @($sourceDirectories | Where-Object {
    Test-Path -LiteralPath (Join-Path $projectPath $_) -PathType Container
}).Count -gt 0
$hasProjectFile = @(
    'pom.xml',
    'build.gradle',
    'build.gradle.kts',
    'settings.gradle',
    'settings.gradle.kts',
    '.project',
    '.classpath'
    ) | Where-Object { Test-Path -LiteralPath (Join-Path $projectPath $_) -PathType Leaf }
$hasJavaSource = @(Get-ChildItem -LiteralPath $projectPath -Filter '*.java' -File -ErrorAction SilentlyContinue).Count -gt 0
if (-not $hasSourceDirectory -and -not $hasProjectFile -and -not $hasJavaSource) {
    Write-Warning "No Java source folder or project file was found in '$projectPath'. javafxsetup configures this folder only; run it from your application's project root."
}

$requiredJars = @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')
$missingJars = @($requiredJars | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $sdk $_) -PathType Leaf)
})
if ($missingJars.Count -gt 0) {
    $message = "The JavaFX SDK folder '$sdk' is incomplete. Missing required JAR(s): $($missingJars -join ', '). Reinstall JavaFX Hotspot to repair the SDK."
    Write-Host "[FAIL] JavaFX SDK: $message" -ForegroundColor Red
    throw $message
}
$jars = @(Get-ChildItem -LiteralPath $sdk -Filter 'javafx*.jar' -File | Sort-Object Name)
try {
    $modules = Get-JavaFxModules
} catch {
    $message = "Invalid JavaFX module configuration: $($_.Exception.Message)"
    Write-Host "[FAIL] JavaFX modules: $message" -ForegroundColor Red
    throw $message
}
$configured = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

$runVsCode = $IDE -in @('all', 'vscode', 'antigravity') -or
    ($IDE -eq 'auto' -and (Test-Path -LiteralPath (Join-Path $projectPath '.vscode') -PathType Container))
if ($runVsCode) {
    $name = if ($IDE -eq 'antigravity') { 'Antigravity (VS Code workspace settings)' } else { 'VS Code' }
    Invoke-IdeSetup -Name $name -Action {
        Set-VsCodeClassPath -Root $projectPath -Sdk $sdk
    } -Validate {
        $settingsPath = Join-Path $projectPath '.vscode\settings.json'
        try {
            $hadJsoncSyntax = $false
            $settings = ConvertFrom-JsonWithComments -JsonText (Get-Content -LiteralPath $settingsPath -Raw) `
                -HadJsoncSyntax ([ref]$hadJsoncSyntax)
        } catch {
            throw "Could not validate '$settingsPath' after writing it: $($_.Exception.Message)"
        }
        $libraries = @($settings.'java.project.referencedLibraries')
        $expectedLibraryPath = ($sdk.TrimEnd('\', '/') + '/*.jar').Replace('\', '/')
        if ($libraries -notcontains $expectedLibraryPath) {
            throw "The JavaFX SDK reference '$expectedLibraryPath' is missing from java.project.referencedLibraries in '$settingsPath'."
        }
        if ((Test-Path -LiteralPath (Join-Path $projectPath 'src\main\java') -PathType Container) -and
            @($settings.'java.project.sourcePaths') -notcontains 'src/main/java') {
            throw "The Java source root src/main/java is missing from '$settingsPath'."
        }
    } -Configured $configured -Failures $failures
}

$runEclipse = $IDE -in @('all', 'eclipse', 'zed') -or
    ($IDE -eq 'auto' -and ((Test-Path (Join-Path $projectPath '.project')) -or
        (Test-Path (Join-Path $projectPath '.classpath')) -or
        (Test-Path (Join-Path $projectPath '.zed') -PathType Container)))
if ($runEclipse) {
    $name = if ($IDE -eq 'zed') { 'Zed (JDTLS project classpath)' } else { 'Eclipse' }
    Invoke-IdeSetup -Name $name -Action {
        Set-EclipseClassPath -Root $projectPath -Jars $jars
    } -Validate {
        $classpathPath = Join-Path $projectPath '.classpath'
        $projectFilePath = Join-Path $projectPath '.project'
        $classpath = Read-ProjectXml -Path $classpathPath -RootName 'classpath'
        $projectFile = Read-ProjectXml -Path $projectFilePath -RootName 'projectDescription'
        foreach ($jar in $jars) {
            $expectedPath = $jar.FullName.Replace('\', '/')
            if (@($classpath.DocumentElement.SelectNodes("classpathentry[@kind='lib']") | Where-Object {
                $_.GetAttribute('path') -eq $expectedPath
            }).Count -ne 1) {
                throw "JavaFX JAR '$expectedPath' is missing from '$classpathPath'."
            }
        }
        if (-not $projectFile.DocumentElement.SelectSingleNode("natures/nature[.='org.eclipse.jdt.core.javanature']")) {
            throw "The Eclipse Java nature is missing from '$projectFilePath'."
        }
    } -Configured $configured -Failures $failures
    if ($IDE -eq 'all' -or ($IDE -eq 'auto' -and
        (Test-Path -LiteralPath (Join-Path $projectPath '.zed') -PathType Container))) {
        $configured.Add('Zed (JDTLS project classpath)')
        Write-Host '[PASS] Zed (JDTLS project classpath): uses the verified Eclipse .project and .classpath files.' -ForegroundColor Green
    }
}

$runIntelliJ = $IDE -in @('all', 'intellij') -or
    ($IDE -eq 'auto' -and ((Test-Path (Join-Path $projectPath '.idea')) -or
        @(Get-ChildItem -LiteralPath $projectPath -Filter '*.iml' -File).Count -gt 0))
if ($runIntelliJ) {
    Invoke-IdeSetup -Name 'IntelliJ IDEA' -Action {
        Set-IntelliJClassPath -Root $projectPath -Jars $jars
    } -Validate {
        $modulesPath = Join-Path $projectPath '.idea\modules.xml'
        $moduleDocument = Read-ProjectXml -Path $modulesPath -RootName 'project'
        $entries = @($moduleDocument.DocumentElement.SelectNodes("component[@name='ProjectModuleManager']/modules/module"))
        $localModuleFiles = @(Get-ChildItem -LiteralPath $projectPath -Filter '*.iml' -File)
        $modulePrefix = $projectPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ($localModuleFiles.Count -eq 0) {
            throw "No IntelliJ .iml module file exists in '$projectPath'."
        }
        foreach ($moduleFile in $localModuleFiles) {
            $relative = $moduleFile.FullName.Substring($modulePrefix.Length).Replace('\', '/')
            $moduleUrl = 'file://$PROJECT_DIR$/' + $relative
            $moduleFilePath = '$PROJECT_DIR$/' + $relative
            if (@($entries | Where-Object {
                $_.GetAttribute('fileurl') -eq $moduleUrl -and
                $_.GetAttribute('filepath') -eq $moduleFilePath
            }).Count -ne 1) {
                throw "IntelliJ module '$($moduleFile.Name)' is not correctly registered by both filepath and fileurl in '$modulesPath'."
            }
            $moduleDocument = Read-ProjectXml -Path $moduleFile.FullName -RootName 'module'
            $libraryEntry = @($moduleDocument.DocumentElement.SelectNodes(
                "component[@name='NewModuleRootManager']/orderEntry[@type='module-library']/library[@name='JavaFX Hotspot']"))
            if ($libraryEntry.Count -ne 1) {
                throw "Module '$($moduleFile.Name)' does not contain the embedded JavaFX Hotspot module library. IntelliJ may be using a different module file."
            }
            foreach ($jar in $jars) {
                $expectedUrl = 'jar://' + $jar.FullName.Replace('\', '/') + '!/'
                if (@($libraryEntry[0].SelectNodes("CLASSES/root[@url='$expectedUrl']")).Count -ne 1) {
                    throw "Module '$($moduleFile.Name)' does not reference JavaFX JAR '$expectedUrl'."
                }
            }
        }
    } -Configured $configured -Failures $failures
    if ((Test-Path -LiteralPath (Join-Path $projectPath 'pom.xml') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $projectPath 'build.gradle') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $projectPath 'build.gradle.kts') -PathType Leaf)) {
        Write-Warning "This project has a Maven or Gradle build file. IntelliJ imports its dependencies from that build file and may ignore .iml changes; add JavaFX to the build file and reload the Maven/Gradle project if imports remain unresolved."
    }
}

$netBeansProperties = Join-Path $projectPath 'nbproject\project.properties'
$runNetBeans = $IDE -in @('all', 'netbeans') -or
    ($IDE -eq 'auto' -and (Test-Path -LiteralPath $netBeansProperties -PathType Leaf))
if ($runNetBeans -and (Test-Path -LiteralPath $netBeansProperties -PathType Leaf)) {
    Invoke-IdeSetup -Name 'Apache NetBeans' -Action {
        $result = Set-NetBeansClassPath -Root $projectPath -Jars $jars -Sdk $sdk -Modules $modules
        if (-not $result) {
            throw "NetBeans setup did not update '$netBeansProperties'."
        }
    } -Validate {
        $properties = Get-Content -LiteralPath $netBeansProperties -Raw
        foreach ($jar in $jars) {
            $reference = 'file.reference.' + $jar.Name + '=' + $jar.FullName.Replace('\', '/')
            if ($properties -notmatch [regex]::Escape($reference)) {
                throw "JavaFX reference '$reference' is missing from '$netBeansProperties'."
            }
        }
        if ($properties -notmatch '(?m)^javac\.classpath=.*\$\{file\.reference\.javafx\.controls\.jar\}') {
            throw "JavaFX controls is missing from the javac.classpath in '$netBeansProperties'."
        }
        if ($properties -notmatch '(?m)^run\.jvmargs=.*--module-path') {
            throw "JavaFX module-path arguments are missing from run.jvmargs in '$netBeansProperties'."
        }
        if ($properties -notmatch ('(?m)^run\.jvmargs=.*--add-modules\s+' + [regex]::Escape($modules))) {
            throw "JavaFX module list '$modules' is missing from run.jvmargs in '$netBeansProperties'."
        }
    } -Configured $configured -Failures $failures
} elseif ($IDE -eq 'netbeans') {
    $reason = "No NetBeans Ant project file was found at '$netBeansProperties'. Open or create a Java with Ant project first."
    $failures.Add("Apache NetBeans: $reason")
    Write-Host "[FAIL] Apache NetBeans: $reason" -ForegroundColor Red
} elseif ($IDE -eq 'all') {
    $message = "no '$netBeansProperties' file"
    $skipped.Add("Apache NetBeans (not an Ant project: $message)")
}

if ($IDE -eq 'all' -and -not $runIntelliJ) {
    $skipped.Add('IntelliJ IDEA (no .idea folder or .iml module found)')
}
if ($IDE -eq 'auto') {
    if (-not $runVsCode) { $skipped.Add('VS Code (no .vscode folder found)') }
    if (-not $runEclipse) { $skipped.Add('Eclipse (no .project, .classpath, or .zed configuration found)') }
    if (-not $runIntelliJ) { $skipped.Add('IntelliJ IDEA (no .idea folder or .iml module found)') }
    if (-not $runNetBeans) { $skipped.Add('Apache NetBeans (no nbproject\project.properties found)') }
}

Write-Host "JavaFX setup target: $projectPath"
if ($configured.Count -gt 0) {
    Write-Host "Verified: $($configured -join ', ')"
}
foreach ($message in $skipped) {
    Write-Host "[SKIP] $message" -ForegroundColor Yellow
}
if ($failures.Count -gt 0) {
    $failureList = ($failures | ForEach-Object { " - $_" }) -join [Environment]::NewLine
    throw "JavaFX IDE setup FAILED for $($failures.Count) target(s):$([Environment]::NewLine)$failureList"
}
if ($configured.Count -eq 0) {
    $message = "No IDE was configured for '$projectPath'. Select an IDE with -IDE or create the corresponding project files and use -IDE auto."
    Write-Host "[FAIL] IDE selection: $message" -ForegroundColor Red
    throw $message
}
Write-Host 'IDE configuration files were verified. If an IDE still shows unresolved imports, check the project/module folder open in that IDE and refresh its build or project model.'
