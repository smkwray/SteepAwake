[CmdletBinding()]
param(
    [string]$PortablePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\SteepAwake.exe'),
    [string]$InstallerPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\SteepAwake-Setup.exe')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sleepGroup = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$sleepSetting = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$displayGroup = '7516b95f-f776-4464-8c53-06167f40cc99'
$displaySetting = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$lidGroup = '4f971e89-eebd-4455-a8de-9e59040e7347'
$lidSetting = '5ca83367-6e45-459f-a27b-476b1d01c936'
$stateDirectory = Join-Path $env:LOCALAPPDATA 'SteepAwake'
$statePath = Join-Path $stateDirectory 'state.ini'

function Get-ActiveScheme {
    $text = (powercfg /getactivescheme) -join "`n"
    if ($LASTEXITCODE -ne 0 -or
        $text -notmatch '(?i)([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})') {
        throw 'Could not read the active power scheme.'
    }
    return $Matches[1]
}

function Get-PowerSetting {
    param(
        [string]$Group,
        [string]$Setting,
        [switch]$Optional
    )

    $text = (powercfg /qh SCHEME_CURRENT $Group $Setting) -join "`n"
    $matches = [regex]::Matches(
        $text, '(?im)Current (?:AC|DC) Power Setting Index:\s*0x([0-9a-f]+)')
    if ($LASTEXITCODE -ne 0 -or $matches.Count -ne 2) {
        if ($Optional) {
            return $null
        }
        throw "Could not read power setting $Setting."
    }
    return [pscustomobject]@{
        AC = [Convert]::ToUInt32($matches[0].Groups[1].Value, 16)
        DC = [Convert]::ToUInt32($matches[1].Groups[1].Value, 16)
    }
}

function Get-PowerPolicy {
    $sleep = Get-PowerSetting $sleepGroup $sleepSetting
    $display = Get-PowerSetting $displayGroup $displaySetting
    $lid = Get-PowerSetting $lidGroup $lidSetting -Optional
    return [pscustomobject]@{
        Plan = Get-ActiveScheme
        SleepAC = $sleep.AC
        SleepDC = $sleep.DC
        DisplayAC = $display.AC
        DisplayDC = $display.DC
        LidAC = if ($null -eq $lid) { -1 } else { $lid.AC }
        LidDC = if ($null -eq $lid) { -1 } else { $lid.DC }
    }
}

function Assert-PowerPolicyEqual {
    param(
        [pscustomobject]$Expected,
        [pscustomobject]$Actual,
        [string]$Context
    )
    foreach ($name in 'Plan','SleepAC','SleepDC','DisplayAC','DisplayDC','LidAC','LidDC') {
        if ($Expected.$name -ne $Actual.$name) {
            throw "$Context changed $name from $($Expected.$name) to $($Actual.$name)."
        }
    }
}

function Write-TestState {
    param(
        [bool]$Active,
        [pscustomobject]$Policy,
        [bool]$KeepDisplayOn = $false,
        [bool]$KeepAwakeWithLidClosed = $false
    )
    New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
    $content = @(
        '[Session]'
        "Active=$([int]$Active)"
        "Plan=$($Policy.Plan)"
        "NormalAC=$($Policy.SleepAC)"
        "NormalDC=$($Policy.SleepDC)"
        "NormalDisplayAC=$($Policy.DisplayAC)"
        "NormalDisplayDC=$($Policy.DisplayDC)"
        "NormalLidAC=$($Policy.LidAC)"
        "NormalLidDC=$($Policy.LidDC)"
        'Expiry='
        "Label=$(if ($Active) { 'Indefinitely' } else { 'Normal sleep' })"
        '[Preferences]'
        "KeepDisplayOn=$([int]$KeepDisplayOn)"
        "KeepAwakeWithLidClosed=$([int]$KeepAwakeWithLidClosed)"
    ) -join "`r`n"
    [IO.File]::WriteAllText($statePath, $content + "`r`n")
}

function Test-AppLifecycle {
    param([string]$Executable)

    $before = Get-PowerPolicy
    Write-TestState -Active $false -Policy $before
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

    $after = Get-PowerPolicy
    Assert-PowerPolicyEqual $before $after `
        "$Executable while in Normal sleep mode"
}

function Test-OptionalPolicies {
    param([string]$Executable)

    $before = Get-PowerPolicy
    $testLid = $before.LidAC -ge 0 -and $before.LidDC -ge 0
    Write-TestState -Active $true -Policy $before `
        -KeepDisplayOn $true -KeepAwakeWithLidClosed $testLid
    $app = Start-Process -FilePath $Executable -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Milliseconds 1500
        if ($app.HasExited) {
            throw "$Executable exited while applying optional policies."
        }
        $active = Get-PowerPolicy
        foreach ($name in 'SleepAC','SleepDC','DisplayAC','DisplayDC') {
            if ($active.$name -ne 0) {
                throw "$Executable did not set $name to Never."
            }
        }
        if ($testLid -and ($active.LidAC -ne 0 -or $active.LidDC -ne 0)) {
            throw "$Executable did not set the lid-close action to Do nothing."
        }
    } finally {
        $stop = Start-Process -FilePath $Executable -ArgumentList 'exit' `
            -WindowStyle Hidden -Wait -PassThru
        if (-not $app.HasExited) {
            $null = $app.WaitForExit(5000)
        }
        $after = Get-PowerPolicy
        Assert-PowerPolicyEqual $before $after `
            "$Executable after its optional-policy session"
    }
}

foreach ($path in @($PortablePath, $InstallerPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing release artifact: $path"
    }
}

$stateExisted = Test-Path -LiteralPath $statePath
$stateBytes = if ($stateExisted) {
    [IO.File]::ReadAllBytes($statePath)
} else {
    $null
}

if (Get-Process -Name SteepAwake -ErrorAction SilentlyContinue) {
    throw 'Close the running SteepAwake release before running release smoke tests.'
}

try {
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
Test-OptionalPolicies -Executable $PortablePath

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

'Release smoke checks passed: metadata, icon, sleep/display/lid policy restoration, portable lifecycle, installer, and uninstaller.'
} finally {
    if ($stateExisted) {
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        [IO.File]::WriteAllBytes($statePath, $stateBytes)
    } else {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $stateDirectory) {
            $remaining = @(Get-ChildItem -LiteralPath $stateDirectory -Force)
            if ($remaining.Count -eq 0) {
                Remove-Item -LiteralPath $stateDirectory -Force
            }
        }
    }
}
