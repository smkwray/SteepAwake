#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [switch]$NoStartup,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceLauncher = Join-Path $projectRoot 'dist\SteepAwake.exe'
$sourceTray = Join-Path $projectRoot 'dist\SteepAwake.Tray.exe'
$installDirectory = Join-Path ${env:ProgramFiles} 'SteepAwake'
$installedLauncher = Join-Path $installDirectory 'SteepAwake.exe'
$installedTray = Join-Path $installDirectory 'SteepAwake.Tray.exe'
$registerScript = Join-Path $projectRoot 'scripts\register-tasks.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

foreach ($required in @($sourceLauncher, $sourceTray, $registerScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required installation input is missing: $required"
    }
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Copy-Item -LiteralPath $sourceLauncher -Destination $installedLauncher -Force
Copy-Item -LiteralPath $sourceTray -Destination $installedTray -Force

& $registerScript -TrayExecutablePath $installedTray

if ($NoStartup) {
    Remove-ItemProperty -LiteralPath $runKey -Name SteepAwake `
        -ErrorAction SilentlyContinue
} else {
    New-ItemProperty -LiteralPath $runKey -Name SteepAwake `
        -PropertyType String -Value ('"' + $installedLauncher + '"') -Force |
        Out-Null
}

if (-not $NoLaunch) {
    Start-Process -FilePath $installedLauncher -WindowStyle Hidden
}

[pscustomobject]@{
    InstalledLauncher = $installedLauncher
    InstalledTray = $installedTray
    StartWithWindows = -not $NoStartup
    Launched = -not $NoLaunch
}
