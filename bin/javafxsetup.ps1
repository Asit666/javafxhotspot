[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $ProjectDirectory = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\common.ps1')

$sdk = Get-InstalledJavaFxPath
if (-not $sdk) {
    throw 'JavaFX SDK is not configured. Run install.ps1 from the JavaFX Hotspot repository.'
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectDirectory)
if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
    throw "Project folder does not exist: $projectPath"
}

$vscodeDirectory = Join-Path $projectPath '.vscode'
$settingsPath = Join-Path $vscodeDirectory 'settings.json'
$settings = [pscustomobject]@{}
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $settingsContent = Get-Content -LiteralPath $settingsPath -Raw
    try {
        $settings = ConvertFrom-Json -InputObject $settingsContent
    } catch {
        throw "Could not read '$settingsPath' as JSON. Fix its JSON syntax before running javafxsetup."
    }
    if ($null -eq $settings -or $settings -is [array] -or $settings -is [string] -or $settings -is [ValueType]) {
        throw "Expected '$settingsPath' to contain a JSON object."
    }
}

$referencedProperty = $settings.PSObject.Properties['java.project.referencedLibraries']
$libraries = @()
if ($referencedProperty) {
    if ($referencedProperty.Value -is [string]) {
        $libraries = @($referencedProperty.Value)
    } elseif ($null -ne $referencedProperty.Value) {
        $libraries = @($referencedProperty.Value)
    }
}

$libraries = @($libraries | Where-Object {
    $_ -and $_ -notmatch '(?i)javafx-sdk-[^/\\]+[/\\]lib[/\\].*\.jar'
})
$javaFxLibrary = $sdk.TrimEnd('\', '/') + '/*.jar'
$javaFxLibrary = $javaFxLibrary.Replace('\', '/')
if ($libraries -notcontains $javaFxLibrary) {
    $libraries += $javaFxLibrary
}

if ($referencedProperty) {
    $referencedProperty.Value = @($libraries)
} else {
    $settings | Add-Member -MemberType NoteProperty -Name 'java.project.referencedLibraries' -Value @($libraries)
}

New-Item -ItemType Directory -Path $vscodeDirectory -Force | Out-Null
$json = ConvertTo-Json -InputObject $settings -Depth 100
$encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($settingsPath, $json + [Environment]::NewLine, $encoding)

Write-Host "VS Code Java classpath configured for JavaFX:"
Write-Host "  $javaFxLibrary"
Write-Host 'If VS Code still shows stale import errors, run "Java: Clean Java Language Server Workspace" once.'
