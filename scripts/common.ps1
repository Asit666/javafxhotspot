Set-StrictMode -Version Latest

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

    $output = @(& $command.Source --version 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        throw "Could not query '$Name' at '$($command.Source)'."
    }

    $match = [regex]::Match(($output -join "`n"), '(?m)\b(?:javac\s+)?(?:openjdk\s+)?(\d+)(?:\.\d+)*')
    if (-not $match.Success) {
        throw "Could not determine the version of '$Name' at '$($command.Source)'. Output: $($output -join ' ')"
    }

    [pscustomobject]@{
        Name       = $Name
        Path       = $command.Source
        Major      = [int] $match.Groups[1].Value
        VersionText = $output -join ' '
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
    if (-not $env:PATH_TO_FX) {
        return $null
    }

    if (Test-Path -LiteralPath (Join-Path $env:PATH_TO_FX 'javafx.controls.jar') -PathType Leaf) {
        return $env:PATH_TO_FX
    }

    $null
}

function Assert-JavaFxMatchesJdk {
    param(
        [Parameter(Mandatory = $true)]
        [int] $JdkMajor,

        [Parameter(Mandatory = $true)]
        [string] $SdkPath
    )

    $versionMatch = [regex]::Match($SdkPath, '(?i)javafx-(?:sdk-)?(\d+\.\d+\.\d+)')
    if (-not $versionMatch.Success) {
        return
    }

    $versionsFile = Join-Path $PSScriptRoot '..\javafx-versions.json'
    if (-not (Test-Path -LiteralPath $versionsFile -PathType Leaf)) {
        return
    }

    $version = $versionMatch.Groups[1].Value
    $table = Get-Content -LiteralPath $versionsFile -Raw | ConvertFrom-Json
    $release = $table.releases | Where-Object { $_.version -eq $version } | Select-Object -First 1
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

    $fileName = [System.IO.Path]::GetFileName($Source)
    if (-not $fileName.EndsWith('.java', [System.StringComparison]::OrdinalIgnoreCase)) {
        $fileName += '.java'
    }

    $matches = @(Get-ChildItem -LiteralPath (Get-Location).Path -Filter $fileName -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|build|target|node_modules)[\\/]' })

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
    $match = [regex]::Match($text, '(?m)^\s*package\s+([\w.]+)\s*;')
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    ''
}
