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
Assert-True ($tray -notmatch 'SetLidValues\(plan, 0, normal\.LidDC') 'Lid override must also set the battery lid action to Do nothing.'
Assert-True (([regex]::Matches($tray, 'SetLidValues\(plan, 0, 0\)')).Count -ge 2) 'Session start and live toggle must both override AC and battery lid actions.'
# Armoury Crate switches to another plan the moment AC drops out, and Windows
# applies that plan's lid action at once, so every plan must carry the override.
Assert-True ($tray -match '(?s)for plan in PowerSchemes\(\)\s+SessionPlans\[plan\] := ReadPowerValues\(plan\)') 'Session start must save the values of every power plan.'
Assert-True ($tray -match '(?s)ApplySessionPolicy\(\) \{.*?for plan, normal in SessionPlans.*?SetLidValues\(plan, 0, 0\)') 'The session policy must override every saved plan.'
Assert-True ($tray -match '(?s)RestoreNormal\(showNotice := false\) \{.*?for plan, normal in SessionPlans.*?SetLidValues\(plan, normal\.LidAC, normal\.LidDC\)') 'Ending the session must restore every saved plan.'
Assert-True ($tray -match '(?s)CheckExpiration\(\) \{.*?CoverActivePlan\(\)') 'A plan created during the session must be covered when it becomes active.'
# Reactivating a remembered plan would undo the mode Armoury Crate selected.
Assert-True (([regex]::Matches($tray, 'PowerSetActiveScheme')).Count -eq 1) 'Only ReapplyActiveScheme may activate a power plan.'
Assert-True ($tray -match '(?s)ReapplyActiveScheme\(\) \{\s+schemeGuid := GuidBuffer\(GetActiveScheme\(\)\)') 'Policy changes must reapply the plan that is active now.'
# The unelevated launcher can start a session only if the tray grants the user the event.
Assert-True ($tray -match 'SteepAwake\.Tray\.Awake\." TraySid,\s+"D:[^"]*\(A;;0x100002;;;" TraySid') 'The awake event must grant the user signal access.'
Assert-True ($launcher -match '(?s)HasArgument\("--awake"\).*?SignalTrayAwake') 'Launcher --awake must signal the tray.'
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
# The elevated task must never point at a user-writable location, and a failed
# registration must fail setup: [Run] entries and AfterInstall exceptions do not.
Assert-True ($installer -match '(?s)function PrepareToInstall.*?commonpf64.*?commonpf32.*?RunRegisterTasks\(AddBackslash\(WizardDirValue\)[^;]*, True\)') 'Setup must check the destination and its ACLs before writing files.'
# A script in the destination could be swapped between copy and execution, and
# a command shell would run AutoRun commands and expand %variables% in paths.
Assert-True ($installer -match 'EncodedCommand \{#RegisterTasksCommand\}') 'Setup must run task registration from the embedded command.'
Assert-True ($installer -match 'ExecAndLogOutput\(ExpandConstant\(''\{sys\}\\WindowsPowerShell') 'Setup must start PowerShell directly.'
Assert-True ($installer -notmatch '\{cmd\}|cmd\.exe') 'Setup must not run task registration through a command shell.'
Assert-True ($installer -notmatch '(?s)\[Code\].*\{app\}\\register-tasks\.ps1') 'Setup must not execute the registration script from the destination folder.'
Assert-True ($installer -match 'AfterInstall: RegisterTrayTask') 'Task registration must run from setup code that can record failure.'
Assert-True ($installer -match '(?s)procedure RegisterTrayTask.*?if ResultCode <> 0 then.*?TaskRegistrationFailed := True') 'A failed task registration must be recorded.'
Assert-True ($installer -match '(?s)function GetCustomSetupExitCode.*?TaskRegistrationFailed') 'A failed task registration must give setup a nonzero exit code.'
Assert-True ($installer -notmatch '(?m)^\[Run\][^\[]*register-tasks') 'Task registration must not run from [Run], which ignores failures.'
# Setup creates {app} itself, so uninstall must remove it explicitly.
Assert-True ($installer -match 'Type: dirifempty; Name: "\{app\}"') 'Uninstall must remove the install directory setup created.'
# The ASUS option is device opt-in; setup must not enable it everywhere.
Assert-True ($installer -notmatch 'EnableAsusOptimizationToggle') 'Installer must not force-enable the ASUSOptimization option.'

Assert-True ($register -match '\\SteepAwake\\') 'Task folder is missing.'
Assert-True ($register -match 'ExecutionTimeLimit \(\[TimeSpan\]::Zero\)') 'Task execution limit must be indefinite.'
Assert-True ($register -match 'SetSecurityDescriptor') 'Task ACL hardening is missing.'
Assert-True ($register -match 'TASK_DONT_ADD_PRINCIPAL_ACE|0x10') 'Task principal ACE hardening is missing.'
# Interactive elevated setup is denied the task descriptor once the folder is protected.
Assert-True ($register -match '(?s)\$registered\.SetSecurityDescriptor\(\$protectedSddl, 0x10\)\s*\r?\n\s*\$folder\.SetSecurityDescriptor\(\$protectedSddl, 0\)') 'The task descriptor must be set before the folder descriptor.'
Assert-True ($register -match 'ASUSOptimization Start|ASUSOptimization Stop') 'Legacy broker-task cleanup is missing.'
Assert-True ($register -notmatch 'Register-ScheduledTask[^\r\n]*ASUSOptimization') 'Legacy broker tasks must not be registered.'
# The task runs the tray elevated on demand, so a writable install location
# would let any user process replace the tray and run as administrator.
Assert-True ($register -match 'Refusing to register the elevated task outside Program Files') 'Task registration must require a Program Files location.'
Assert-True ($register -match '(?s)Assert-AdminOnlyPath.*?ReparsePoint.*?writable by') 'Task registration must reject reparse points and non-admin write access.'
Assert-True ($register -match '(?s)Assert-AdminOnlyPath \$checkedPath.*?Register-ScheduledTask') 'Path checks must run before the task is registered.'
# Program Files must come from the 64-bit registry view, not inheritable
# environment variables, and the whole ancestry must be checked.
Assert-True ($register -match '(?s)RegistryView\]::Registry64.*?ProgramFilesDir') 'Program Files locations must come from the 64-bit registry view.'
Assert-True ($register -notmatch 'env:ProgramFiles|ProgramW6432') 'Program Files locations must not come from environment variables.'
Assert-True ($register -match '(?s)while \(\$checkedPath\).*?replaceMask.*?GetDirectoryName') 'The check must walk to the drive root, including Program Files itself.'
# Files setup copies must not inherit write access from the parent folder.
Assert-True ($register -match '(?s)if \(\$PrepareDestination\) \{.*?SetAccessRuleProtection\(\$true, \$false\).*?exit 0') 'Preparing the destination must give it a protected DACL and stop before registering.'
# Program Files itself must never receive SteepAwake's DACL.
Assert-True ($register -match 'installDirectory\.TrimEnd\(''\\''\)\.Length -le \$programRoot\.Length') 'The install directory must be strictly inside Program Files.'
Assert-True ($installer -match 'Length\(Path\) > Length\(Folder\)') 'Setup must reject Program Files itself as the install directory.'
Assert-True ($register -match 'CreateDirectory\(\$installDirectory, \$security\)') 'A new install directory must be created with its protected DACL atomically.'
Assert-True ($register -match '\(\$insideRoot -and \$isDirectory\)') 'Directories inside Program Files must be checked including inheritable ACEs.'
# Setup can inherit a PowerShell 7 module path that breaks Get-Acl autoloading.
Assert-True ($register -notmatch 'Get-Acl\s+-') 'Task registration must read ACLs without the Get-Acl module.'
Assert-True ($register -match 'Definition\.Settings\.ExecutionTimeLimit') 'Post-registration validation must read Definition.Settings.'
Assert-True ($register -notmatch '\$registered\.Settings') 'RegisteredTask has no Settings property; validation would throw.'

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
