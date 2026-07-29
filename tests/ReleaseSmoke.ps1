[CmdletBinding()]
param(
    [string]$PortablePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\SteepAwake.exe'),
    [string]$InstallerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\SteepAwake-Setup.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-SleepPolicy {
    $lines = powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE
    return (($lines | Select-String 'Current AC|Current DC').Line -join "`n")
}

function Test-AppLifecycle {
    param([string]$Executable)

    $before = Get-SleepPolicy
    $app = Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 1500
    if ($app.HasExited) {
        throw "$Executable exited unexpectedly with code $($app.ExitCode)."
    }

    $stop = Start-Process -FilePath $Executable -ArgumentList 'exit' `
        -WindowStyle Hidden -Wait -PassThru
    if ($stop.ExitCode -ne 0) {
        throw "$Executable exit command failed with code $($stop.ExitCode)."
    }
    if (-not $app.WaitForExit(5000)) {
        throw "$Executable did not exit cleanly."
    }

    $after = Get-SleepPolicy
    if ($after -ne $before) {
        throw "$Executable changed the sleep policy while in Normal sleep mode."
    }
}

foreach ($path in @($PortablePath, $InstallerPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing release artifact: $path"
    }
}

$version = (Get-Content -LiteralPath (
    Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION') -Raw).Trim()
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($PortablePath)
if ($versionInfo.ProductName -ne 'SteepAwake') {
    throw "Unexpected product name: $($versionInfo.ProductName)"
}
if (-not $versionInfo.ProductVersion.StartsWith($version)) {
    throw "Unexpected product version: $($versionInfo.ProductVersion)"
}

Add-Type -AssemblyName System.Drawing
$associatedIcon = [Drawing.Icon]::ExtractAssociatedIcon($PortablePath)
if (-not $associatedIcon) {
    throw 'The portable executable has no associated icon.'
}
$associatedIcon.Dispose()

Test-AppLifecycle -Executable $PortablePath

$testRoot = Join-Path $env:TEMP "SteepAwake.ReleaseSmoke.$PID"
$installedExe = Join-Path $testRoot 'SteepAwake.exe'
$uninstaller = Join-Path $testRoot 'unins000.exe'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupExisted = $false
$startupValue = $null
try {
    try {
        $startupValue = Get-ItemPropertyValue -LiteralPath $runKey -Name SteepAwake
        $startupExisted = $true
    } catch {}

    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /TASKS="" /DIR="' +
        $testRoot + '"'
    $install = Start-Process -FilePath $InstallerPath -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    if ($install.ExitCode -ne 0) {
        throw "Installer failed with code $($install.ExitCode)."
    }
    if (-not (Test-Path -LiteralPath $installedExe)) {
        throw 'Installer did not create SteepAwake.exe.'
    }

    Test-AppLifecycle -Executable $installedExe

    $uninstall = Start-Process -FilePath $uninstaller `
        -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' `
        -WindowStyle Hidden -Wait -PassThru
    if ($uninstall.ExitCode -ne 0) {
        throw "Uninstaller failed with code $($uninstall.ExitCode)."
    }
} finally {
    if ($startupExisted) {
        New-ItemProperty -LiteralPath $runKey -Name SteepAwake `
            -PropertyType String -Value $startupValue -Force | Out-Null
    } else {
        Remove-ItemProperty -LiteralPath $runKey -Name SteepAwake `
            -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $testRoot) {
        $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
        $resolvedTemp = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
        if (-not $resolvedTestRoot.StartsWith(
            $resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected test path: $resolvedTestRoot"
        }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

'Release smoke checks passed: metadata, embedded icon, portable lifecycle, installer, and uninstaller.'
