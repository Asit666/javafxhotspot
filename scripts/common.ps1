Set-StrictMode -Version Latest

function Publish-EnvironmentChange {
    if (-not ('JavaFxHotspotEnvironment' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class JavaFxHotspotEnvironment
{
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint message, UIntPtr wParam, string lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@ -ErrorAction Stop
    }

    $result = [UIntPtr]::Zero
    $status = [JavaFxHotspotEnvironment]::SendMessageTimeout(
        [IntPtr] 65535,
        0x001A,
        [UIntPtr]::Zero,
        'Environment',
        0x0002,
        5000,
        [ref] $result)
    $status -ne [IntPtr]::Zero
}

function ConvertTo-NormalizedEnvironmentPath {
    param(
        [AllowEmptyString()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"')).Replace('/', '\')
    try {
        [System.IO.Path]::GetFullPath($expandedPath).TrimEnd('\', '/')
    } catch {
        $expandedPath.TrimEnd('\', '/')
    }
}

function Test-PathEntryEquals {
    param(
        [AllowEmptyString()]
        [string] $PathEntry,

        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    $normalizedEntry = ConvertTo-NormalizedEnvironmentPath -Path $PathEntry
    $normalizedDirectory = ConvertTo-NormalizedEnvironmentPath -Path $Directory
    $normalizedEntry -and $normalizedEntry.Equals(
        $normalizedDirectory,
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathWithinDirectory {
    param(
        [AllowEmptyString()]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    $normalizedPath = ConvertTo-NormalizedEnvironmentPath -Path $Path
    $normalizedDirectory = ConvertTo-NormalizedEnvironmentPath -Path $Directory
    if (-not $normalizedPath -or -not $normalizedDirectory) {
        return $false
    }

    $normalizedPath.Equals($normalizedDirectory, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith(
            $normalizedDirectory + [System.IO.Path]::DirectorySeparatorChar,
            [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-PathEntriesForDirectory {
    param(
        [AllowEmptyString()]
        [string] $PathValue,

        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    @($PathValue -split ';' | Where-Object {
        $_ -and -not (Test-PathEntryEquals -PathEntry $_ -Directory $Directory)
    }) -join ';'
}

function Get-JavaToolInfo {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('java', 'javac')]
        [string] $Name
    )

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $command) {
        throw "Could not find '$Name' on PATH. Install a JDK and ensure its bin folder is on PATH."
    }

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $command.Source -version 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    } catch {
        throw "Could not query '$Name' at '$($command.Source)': $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($exitCode -ne 0) {
        throw "Could not query '$Name' at '$($command.Source)'."
    }

    $versionOutput = $output -join "`n"
    $match = [regex]::Match(
        $versionOutput,
        '(?m)^\s*(?:java|openjdk)\s+version\s+"(?<version>[^"]+)"|^\s*javac\s+(?<version>[\w.+-]+)')
    if (-not $match.Success) {
        throw "Could not determine the version of '$Name' at '$($command.Source)'. Output: $versionOutput"
    }
    $versionText = $match.Groups['version'].Value
    $majorMatch = [regex]::Match($versionText, '^(?:1\.)?(?<major>\d+)')
    if (-not $majorMatch.Success) {
        throw "Could not determine the version of '$Name' at '$($command.Source)'. Output: $versionOutput"
    }

    [pscustomobject]@{
        Name        = $Name
        Path        = $command.Source
        Major       = [int] $majorMatch.Groups['major'].Value
        VersionText = $versionText
    }
}

function Get-CompatibleJavaFxRelease {
    param(
        [Parameter(Mandatory = $true)]
        [int] $JdkMajor,

        [string] $VersionFile = (Join-Path $PSScriptRoot '..\javafx-versions.json')
    )

    if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
        throw "JavaFX compatibility table not found: $VersionFile"
    }

    $table = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json
    if ($null -eq $table -or $table.releases -isnot [array]) {
        throw "Invalid JavaFX compatibility table: $VersionFile"
    }
    foreach ($releaseEntry in $table.releases) {
        $minimumJdk = 0
        $minimumJdkValid = [int]::TryParse([string] $releaseEntry.minimumJdk, [ref] $minimumJdk)
        if (-not ($releaseEntry.version -match '^\d+(?:\.\d+)+$') -or
            -not $minimumJdkValid -or $minimumJdk -lt 1) {
            throw "Invalid JavaFX compatibility table entry in: $VersionFile"
        }
    }
    $release = $table.releases |
        Where-Object { [int] $_.minimumJdk -le $JdkMajor } |
        Sort-Object -Property @{ Expression = { [version] $_.version }; Descending = $true } |
        Select-Object -First 1

    if (-not $release) {
        throw "JDK $JdkMajor is not supported. Install JDK 11 or newer, then run the installer again."
    }

    $release
}

function Get-CurrentJdk {
    $java = Get-JavaToolInfo -Name java
    $javac = Get-JavaToolInfo -Name javac
    if ($java.Major -ne $javac.Major) {
        throw "The active java command is JDK $($java.Major), but javac is JDK $($javac.Major). Fix PATH so both commands come from the same JDK, then retry."
    }

    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $properties = @(& $java.Path -XshowSettings:properties -version 2>&1 | ForEach-Object { "$_" })
        $settingsExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    if ($settingsExitCode -ne 0) {
        throw "Could not read architecture information from '$($java.Path)'."
    }

    $archMatch = [regex]::Match(($properties -join "`n"), '(?m)^\s*os\.arch\s*=\s*(\S+)\s*$')
    if (-not $archMatch.Success) {
        throw "Could not determine the JDK architecture from '$($java.Path)'."
    }

    $architecture = $archMatch.Groups[1].Value.ToLowerInvariant()
    if ($architecture -notin @('amd64', 'x86_64')) {
        throw "This release supports Windows x64 only. The active JDK reports architecture '$architecture'."
    }

    [pscustomobject]@{
        Major        = $javac.Major
        Java         = $java
        Javac        = $javac
        Architecture = 'x64'
    }
}

function Get-InstalledJavaFxPath {
    $processCandidate = $env:PATH_TO_FX
    $requiredJars = @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')
    $candidates = @(
        $processCandidate,
        [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        $candidateComplete = Test-Path -LiteralPath $candidate -PathType Container
        if ($candidateComplete) {
            foreach ($jarName in $requiredJars) {
                $jar = Get-Item -LiteralPath (Join-Path $candidate $jarName) -ErrorAction SilentlyContinue
                if (-not $jar -or $jar.Length -le 0) {
                    $candidateComplete = $false
                    break
                }
            }
        }
        if ($candidateComplete) {
            return $candidate
        }
    }

    $null
}

function Get-RequiredJavaFxPath {
    $sdkPath = Get-InstalledJavaFxPath
    if ($sdkPath) {
        return $sdkPath
    }

    $candidates = @(
        $env:PATH_TO_FX,
        [Environment]::GetEnvironmentVariable('PATH_TO_FX', 'User')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            try {
                Get-JavaFxSdkJars -SdkPath $candidate -ValidateNativeLibraries
            } catch {
                throw
            }
        }
    }
    $checkedPaths = if ($candidates.Count -gt 0) { $candidates -join '; ' } else { '(PATH_TO_FX is not set)' }
    throw "JavaFX SDK was not found. Checked PATH_TO_FX location(s): $checkedPaths. Each SDK folder must contain javafx.controls.jar. Run install.ps1, then open a new terminal."
}

function Get-JavaFxSdkJars {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SdkPath,

        [switch] $ValidateNativeLibraries
    )

    if (-not (Test-Path -LiteralPath $SdkPath -PathType Container)) {
        throw "JavaFX SDK folder does not exist: '$SdkPath'. Run the JavaFX Hotspot installer again."
    }

    $requiredJars = @('javafx.base.jar', 'javafx.graphics.jar', 'javafx.controls.jar', 'javafx.fxml.jar')
    $invalidJars = @()
    foreach ($jarName in $requiredJars) {
        $jarPath = Join-Path $SdkPath $jarName
        $jar = Get-Item -LiteralPath $jarPath -ErrorAction SilentlyContinue
        if (-not $jar -or $jar.Length -le 0) {
            $invalidJars += $jarName
        }
    }
    if ($invalidJars.Count -gt 0) {
        throw "JavaFX SDK folder '$SdkPath' is incomplete or damaged. Missing or empty required JAR(s): $($invalidJars -join ', '). Reinstall JavaFX Hotspot to repair it."
    }
    if ($ValidateNativeLibraries) {
        $requiredNativeLibraries = @(
            'glass.dll',
            'javafx_font.dll',
            'javafx_iio.dll',
            'prism_d3d.dll',
            'prism_sw.dll'
        )
        $invalidNativeLibraries = @()
        $nativeDirectory = Join-Path (Split-Path -Parent $SdkPath) 'bin'
        foreach ($libraryName in $requiredNativeLibraries) {
            $library = Get-Item -LiteralPath (Join-Path $nativeDirectory $libraryName) -ErrorAction SilentlyContinue
            if (-not $library -or $library.Length -le 0) {
                $invalidNativeLibraries += $libraryName
            }
        }
        if ($invalidNativeLibraries.Count -gt 0) {
            throw "JavaFX SDK folder '$SdkPath' is incomplete or damaged. Missing or empty required Windows native library/libraries: $($invalidNativeLibraries -join ', '). Reinstall JavaFX Hotspot to repair it."
        }
    }

    @(Get-ChildItem -LiteralPath $SdkPath -Filter 'javafx*.jar' -File | Sort-Object Name)
}

function Get-JavaFxModules {
    param(
        [string] $SdkPath
    )

    $moduleSetting = if ([string]::IsNullOrWhiteSpace($env:JAVAFX_MODULES)) { 'javafx.controls,javafx.fxml' } else { $env:JAVAFX_MODULES }

    $requestedModules = @($moduleSetting -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($requestedModules.Count -eq 0 -or @($requestedModules | Where-Object {
        $_ -cnotmatch '^javafx\.[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)*$'
    }).Count -gt 0) {
        throw "Invalid JAVAFX_MODULES value '$moduleSetting'. Use comma-separated module names such as javafx.controls,javafx.fxml,javafx.media."
    }

    $modules = [System.Collections.Generic.List[string]]::new()
    foreach ($module in $requestedModules) {
        if ($modules -contains $module) {
            continue
        }
        if ($SdkPath) {
            $moduleJar = Get-Item -LiteralPath (Join-Path $SdkPath ($module + '.jar')) -ErrorAction SilentlyContinue
            if (-not $moduleJar -or $moduleJar.Length -le 0) {
                throw "JavaFX module '$module' was requested in JAVAFX_MODULES, but '$module.jar' is missing or empty in SDK folder '$SdkPath'. Check the module name or reinstall the SDK."
            }
        }
        $modules.Add($module)
    }

    $modules -join ','
}

function Assert-JavaFxMatchesJdk {
    param(
        [Parameter(Mandatory = $true)]
        [int] $JdkMajor,

        [Parameter(Mandatory = $true)]
        [string] $SdkPath
    )

    $sdkRoot = Split-Path -Parent $SdkPath
    $versionFile = Join-Path $sdkRoot 'javafx-version.txt'
    $version = $null
    if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
        $metadataVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim()
        if ($metadataVersion -match '^\d+(?:\.\d+)+$') {
            $version = $metadataVersion
        } else {
            throw "Invalid JavaFX SDK version metadata '$versionFile': '$metadataVersion'."
        }
    } else {
        $versionMatch = [regex]::Match($SdkPath, '(?i)javafx-(?:sdk-)?(\d+(?:\.\d+)+)')
        if ($versionMatch.Success) {
            $version = $versionMatch.Groups[1].Value
        }
    }
    if (-not $version) {
        Write-Warning "Could not determine the JavaFX SDK version from '$SdkPath'. Compatibility with JDK $JdkMajor was not verified; run the JavaFX Hotspot installer for a managed SDK."
        return
    }

    $versionsFile = Join-Path $PSScriptRoot '..\javafx-versions.json'
    if (-not (Test-Path -LiteralPath $versionsFile -PathType Leaf)) {
        return
    }

    $table = Get-Content -LiteralPath $versionsFile -Raw | ConvertFrom-Json
    $release = $table.releases | Where-Object { $_.version -eq $version } | Select-Object -First 1
    if (-not $release) {
        throw "Unknown JavaFX SDK version '$version'. Update javafx-versions.json or reinstall a supported JavaFX SDK."
    }
    if ($release -and $JdkMajor -lt [int] $release.minimumJdk) {
        throw "JavaFX $version requires JDK $($release.minimumJdk) or newer, but the active JDK is $JdkMajor. Run the JavaFX Hotspot installer again after selecting a compatible JDK."
    }
}

function Resolve-JavaSource {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Source
    )

    $candidate = if ([System.IO.Path]::IsPathRooted($Source)) {
        [System.IO.Path]::GetFullPath($Source)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Source))
    }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Get-Item -LiteralPath $candidate).FullName
    }
    if ([System.IO.Path]::IsPathRooted($Source) -or
        $Source.Contains('\') -or $Source.Contains('/')) {
        throw "Could not find explicit Java source path '$Source'."
    }
    if ([System.IO.Path]::IsPathRooted($Source) -or
        $Source.Contains('\') -or $Source.Contains('/')) {
        throw "Could not find explicit Java source path '$Source'."
    }

    $fileName = [System.IO.Path]::GetFileName($Source)
    if (-not $fileName.EndsWith('.java', [System.StringComparison]::OrdinalIgnoreCase)) {
        $fileName += '.java'
    }

    $projectRoot = (Get-Location).Path
    $excludedDirectoryNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($directoryName in @('.git', '.gradle', '.idea', '.vscode', 'build', 'target', 'node_modules', 'out', 'dist')) {
        $excludedDirectoryNames.Add($directoryName) | Out-Null
    }
    $directories = [System.Collections.Generic.Queue[string]]::new()
    $directories.Enqueue($projectRoot)
    $matches = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    while ($directories.Count -gt 0) {
        $directory = $directories.Dequeue()
        foreach ($file in Get-ChildItem -LiteralPath $directory -File -ErrorAction SilentlyContinue) {
            if ($file.Name.Equals($fileName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matches.Add($file)
            }
        }
        foreach ($childDirectory in Get-ChildItem -LiteralPath $directory -Directory -Force -ErrorAction SilentlyContinue) {
            if ($excludedDirectoryNames.Contains($childDirectory.Name)) {
                continue
            }
            if ($childDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                continue
            }
            $directories.Enqueue($childDirectory.FullName)
        }
    }

    if ($matches.Count -eq 0) {
        throw "Could not find '$fileName' in the current folder or its project subfolders."
    }

    if ($matches.Count -gt 1) {
        $preferred = @($matches | Where-Object { $_.FullName -match '[\\/]src[\\/]main[\\/]java[\\/]' })
        if ($preferred.Count -eq 1) {
            return $preferred[0].FullName
        }
        throw "Found multiple files named '$fileName'. Pass a relative or full source path."
    }

    $matches[0].FullName
}

function Get-JavaPackageName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath
    )

    $text = Get-Content -LiteralPath $SourcePath -Raw
    $cleanText = New-Object System.Text.StringBuilder
    $inString = $false
    $inChar = $false
    $inLineComment = $false
    $inBlockComment = $false
    $escaped = $false
    for ($index = 0; $index -lt $text.Length; $index++) {
        $character = $text[$index]
        $nextCharacter = if ($index + 1 -lt $text.Length) { $text[$index + 1] } else { [char] 0 }
        if ($inLineComment) {
            if ($character -eq "`r" -or $character -eq "`n") {
                [void] $cleanText.Append($character)
                $inLineComment = $false
            }
            continue
        }
        if ($inBlockComment) {
            if ($character -eq '*' -and $nextCharacter -eq '/') {
                $inBlockComment = $false
                $index++
            } elseif ($character -eq "`r" -or $character -eq "`n") {
                [void] $cleanText.Append($character)
            }
            continue
        }
        if ($inString -or $inChar) {
            if ($escaped) {
                $escaped = $false
            } elseif ($character -eq '\') {
                $escaped = $true
            } elseif (($inString -and $character -eq '"') -or ($inChar -and $character -eq "'")) {
                $inString = $false
                $inChar = $false
            }
            [void] $cleanText.Append(' ')
            continue
        }
        if ($character -eq '/' -and $nextCharacter -eq '/') {
            $inLineComment = $true
            $index++
        } elseif ($character -eq '/' -and $nextCharacter -eq '*') {
            $inBlockComment = $true
            $index++
        } elseif ($character -eq '"') {
            $inString = $true
            [void] $cleanText.Append(' ')
        } elseif ($character -eq "'") {
            $inChar = $true
            [void] $cleanText.Append(' ')
        } else {
            [void] $cleanText.Append($character)
        }
    }
    $text = $cleanText.ToString()
    $match = [regex]::Match($text, '(?m)^\s*package\s+([\w.]+)\s*;')
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    ''
}

function Copy-JavaResources {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ProjectDirectory,

        [Parameter(Mandatory = $true)]
        [string] $OutputDirectory
    )

    $resourceDirectories = @(
        (Join-Path $ProjectDirectory 'src\main\resources'),
        (Join-Path $ProjectDirectory 'resources')
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

    $filesByRelativePath = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($resourceDirectory in $resourceDirectories) {
        $root = (Get-Item -LiteralPath $resourceDirectory).FullName
        $rootItem = Get-Item -LiteralPath $resourceDirectory -Force
        if ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            continue
        }
        $rootPrefix = $root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
            $parent = $file.Directory
            $hasLinkedParent = $false
            while ($parent -and $parent.FullName.StartsWith($rootPrefix.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($parent.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                    $hasLinkedParent = $true
                    break
                }
                if ($parent.FullName.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    break
                }
                $parent = $parent.Parent
            }
            if ($hasLinkedParent -or ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                continue
            }
            $relativePath = $file.FullName.Substring($rootPrefix.Length)
            if ($filesByRelativePath.ContainsKey($relativePath)) {
                throw "Resource '$relativePath' exists in more than one resource folder. Keep one copy under src\main\resources or resources."
            }
            $filesByRelativePath.Add($relativePath, $file.FullName)
        }
    }

    foreach ($relativePath in $filesByRelativePath.Keys) {
        $destination = Join-Path $OutputDirectory $relativePath
        $destinationDirectory = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $filesByRelativePath[$relativePath] -Destination $destination -Force
    }
}
