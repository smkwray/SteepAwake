$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$trayPath = Join-Path $projectRoot 'src\SteepAwake.Tray.ahk'
$launcherPath = Join-Path $projectRoot 'src\SteepAwake.Launcher.ahk'
$generatorPath = Join-Path $projectRoot 'tools\GenerateIcons.ps1'
$installerPath = Join-Path $projectRoot 'installer\SteepAwake.iss'
$registerPath = Join-Path $projectRoot 'scripts\register-tasks.ps1'
$autoHotkeyPath = if ($env:AUTOHOTKEY_PATH) {
    $env:AUTOHOTKEY_PATH
} elseif (Test-Path -LiteralPath (Join-Path $projectRoot '.tools\AutoHotkey\AutoHotkey64.exe')) {
    Join-Path $projectRoot '.tools\AutoHotkey\AutoHotkey64.exe'
} else {
    'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
}
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { $script:failures.Add($Message) }
}

foreach ($path in @($trayPath, $launcherPath, $generatorPath, $installerPath, $registerPath)) {
    Assert-True (Test-Path -LiteralPath $path) "Missing required file: $path"
}

& $generatorPath
Add-Type -AssemblyName System.Drawing
foreach ($theme in 'dark','light') {
    foreach ($state in 'normal','timed','indefinite') {
        $iconName = "$state-$theme.ico"
        $iconPath = Join-Path $projectRoot "assets\$iconName"
        Assert-True (Test-Path -LiteralPath $iconPath) "Missing icon: $iconName"
        if (Test-Path -LiteralPath $iconPath) {
            try {
                $icon = [Drawing.Icon]::new($iconPath)
                Assert-True ($icon.Width -gt 0 -and $icon.Height -gt 0) "Invalid icon: $iconName"
                $icon.Dispose()
            } catch {
                $failures.Add("Invalid icon $iconName`: $($_.Exception.Message)")
            }
        }
    }
}

$tray = Get-Content -LiteralPath $trayPath -Raw
$launcher = Get-Content -LiteralPath $launcherPath -Raw
$installer = Get-Content -LiteralPath $installerPath -Raw
$register = Get-Content -LiteralPath $registerPath -Raw

Assert-True ($tray -match 'StartSession\(360,\s*"6 hours"\)') 'The 6-hour session is missing.'
Assert-True ($tray -match 'Pause ASUSOptimization during awake sessions') 'ASUSOptimization option is missing.'
Assert-True ($tray -match 'WaitForAsusOptimizationState') 'Stable service polling is missing.'
Assert-True ($tray -match 'QueryServiceStatusEx') 'Service status polling is missing.'
Assert-True ($tray -match 'PowerCreateRequest') 'Scoped awake power request is missing.'
Assert-True ($tray -match 'PowerRequestSystemActive') 'System-required power request tracking is missing.'
Assert-True ($tray -match 'PowerRequestDisplayActive') 'Display-required power request tracking is missing.'
Assert-True ($tray -match 'RegisterPowerSettingNotification') 'Power-state notifications are missing.'
Assert-True ($tray -match 'GetSystemPowerStatus') 'AC power guard is missing.'
Assert-True ($tray -match 'PowerClearRequest') 'Power request cleanup is missing.'
Assert-True ($tray -match 'SetNodeDisplayRequest') 'Live display-request toggling is missing.'
# winnt.h POWER_REQUEST_TYPE: 0 is display-required, 1 is system-required.
# Swapping them leaves only a display request, which does not hold the system.
Assert-True ($tray -match 'PowerRequestDisplayRequired := 0\b') 'Display-required request must be POWER_REQUEST_TYPE 0.'
Assert-True ($tray -match 'PowerRequestSystemRequired := 1\b') 'System-required request must be POWER_REQUEST_TYPE 1.'
Assert-True ($tray -notmatch 'PowerSetRequest"[^)]*"Int", \d') 'Power requests must use the named POWER_REQUEST_TYPE values.'
# A charger blip with the lid closed applies the DC lid action immediately, so
# the lid override must cover battery as well as AC.
Assert-True ($tray -notmatch 'SetLidValues\(SessionPlan, 0, NormalLidDC') 'Lid override must also set the battery lid action to Do nothing.'
Assert-True (([regex]::Matches($tray, 'SetLidValues\(SessionPlan, 0, 0')).Count -ge 2) 'Session start and live toggle must both override AC and battery lid actions.'
# GUID_ACDC_POWER_SOURCE is 0 for AC; act only after AC stays absent.
Assert-True ($tray -match 'powerSource != 0') 'AC/DC notification must treat 0 as AC.'
Assert-True ($tray -match 'SetTimer\(EndSessionAfterACRemoval, -ACRemovalGraceMs\)') 'AC removal must wait out transient charger dropouts.'
Assert-True ($tray -match '(?s)EndSessionAfterACRemoval\(\*\) \{.*?IsAcPowerAvailable\(\).*?RestoreNormal') 'AC removal must recheck AC before ending the session.'
Assert-True ($tray -match 'A_TrayMenu\.Enable\("Keep display active on AC while awake"\)') 'Display option must remain usable.'
Assert-True ($tray -notmatch 'A_TrayMenu\.Disable\("Keep display active on AC while awake"\)') 'Display option must not be greyed out.'
Assert-True ($tray -match 'StartServiceW') 'Direct service start is missing.'
Assert-True ($tray -match 'ControlService') 'Direct service stop is missing.'
Assert-True ($tray -match 'AcquireTrayMutex') 'Tray mutex is missing.'
Assert-True ($tray -match 'SteepAwake\.Tray\.Ready') 'Tray ready event is missing.'
Assert-True ($tray -match 'SteepAwake\.Tray\.Shutdown') 'Tray shutdown event is missing.'
Assert-True ($tray -match 'A_IsAdmin') 'Tray elevation guard is missing.'
Assert-True ($tray -match '--task-entry') 'Tray task-entry guard is missing.'
Assert-True ($tray -match '#SingleInstance Off') 'Tray must not rely on cross-integrity single-instance handling.'
Assert-True ($tray -notmatch 'ShellExecute|schtasks|\brunas\b') 'Tray must not use UAC or service broker tasks.'
Assert-True ($tray -match 'RemoveLegacyScheduledTasks') 'Tray must remove obsolete broker tasks during migration.'

Assert-True ($launcher -match '#NoTrayIcon') 'Launcher must not create a tray icon.'
Assert-True ($launcher -match 'GetFolder\("\\SteepAwake"\)') 'Launcher task-folder lookup is missing.'
Assert-True ($launcher -match 'GetTask\("Tray"\)') 'Launcher task lookup is missing.'
Assert-True ($launcher -match 'task\.Run\(0\)') 'Launcher must demand-run the protected task.'
Assert-True ($launcher -match 'SteepAwake\.Tray\.Ready') 'Launcher ready handshake is missing.'
Assert-True ($launcher -match '--shutdown') 'Launcher shutdown control is missing.'
Assert-True ($launcher -notmatch 'runas|ShellExecute|sc\.exe') 'Launcher must not request elevation or control services.'

Assert-True ($installer -match 'DefaultDirName=\{autopf\}') 'Installer must use Program Files.'
Assert-True ($installer -match 'PrivilegesRequired=admin') 'Installer must request one setup elevation.'
Assert-True ($installer -match 'SteepAwake\.Tray\.exe') 'Installer must install the elevated tray binary.'
Assert-True ($installer -match 'register-tasks\.ps1') 'Installer task registration is missing.'
Assert-True ($installer -notmatch 'elevatedstartup|Verb: "runas"') 'Installer must not retain the old optional UAC path.'

Assert-True ($register -match '\\SteepAwake\\') 'Task folder is missing.'
Assert-True ($register -match 'ExecutionTimeLimit \(\[TimeSpan\]::Zero\)') 'Task execution limit must be indefinite.'
Assert-True ($register -match 'SetSecurityDescriptor') 'Task ACL hardening is missing.'
Assert-True ($register -match 'TASK_DONT_ADD_PRINCIPAL_ACE|0x10') 'Task principal ACE hardening is missing.'
Assert-True ($register -match 'ASUSOptimization Start|ASUSOptimization Stop') 'Legacy broker-task cleanup is missing.'
Assert-True ($register -notmatch 'Register-ScheduledTask[^\r\n]*ASUSOptimization') 'Legacy broker tasks must not be registered.'

if (Test-Path -LiteralPath $autoHotkeyPath) {
    foreach ($source in @($launcherPath, $trayPath)) {
        $syntaxArguments = '/ErrorStdOut "' + $source + '" --syntax-check'
        $syntaxProcess = Start-Process -FilePath $autoHotkeyPath `
            -ArgumentList $syntaxArguments -WindowStyle Hidden -Wait -PassThru
        Assert-True ($syntaxProcess.ExitCode -eq 0) `
            "AutoHotkey syntax check failed for $source with exit code $($syntaxProcess.ExitCode)."
    }
} else {
    Write-Warning 'AutoHotkey is not installed; skipped executable syntax validation.'
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

'Smoke checks passed: icons, launcher/tray syntax, protected task wiring, direct service control, and installer layout.'
