[CmdletBinding()]
param(
    [switch]$NoStartup,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceExe = Join-Path $projectRoot 'dist\SteepAwake.exe'
$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\SteepAwake'
$installedExe = Join-Path $installDirectory 'SteepAwake.exe'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw 'Build dist\SteepAwake.exe before installing.'
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $installedExe -Force

if (-not $NoStartup) {
    New-ItemProperty -LiteralPath $runKey -Name SteepAwake `
        -PropertyType String -Value ('"' + $installedExe + '"') -Force |
        Out-Null
}

if (-not $NoLaunch) {
    Start-Process -FilePath $installedExe -WindowStyle Hidden
}

[pscustomobject]@{
    Installed = $installedExe
    StartWithWindows = -not $NoStartup
    Launched = -not $NoLaunch
}
