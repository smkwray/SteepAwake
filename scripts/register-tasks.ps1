#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TrayExecutablePath,
    [switch]$Delete
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskPath = '\SteepAwake\'
$taskName = 'Tray'
$legacyTasks = @(
    'SteepAwake (Elevated)',
    'SteepAwake (ASUSOptimization Start)',
    'SteepAwake (ASUSOptimization Stop)'
)

function Connect-Scheduler {
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    return $service
}

function Remove-RegisteredTasks {
    $service = Connect-Scheduler
    $root = $service.GetFolder('\')
    foreach ($legacyName in $legacyTasks) {
        try {
            $root.DeleteTask($legacyName, 0)
        } catch {
            # The legacy task is already absent.
        }
        try {
            $root.GetTask($legacyName) | Out-Null
            & schtasks.exe /Delete /TN "\$legacyName" /F 2>&1 | Out-Null
        } catch {
            # The legacy task is absent or was removed by the COM call.
        }
    }
    try {
        $folder = $root.GetFolder('\SteepAwake')
        try { $folder.DeleteTask($taskName, 0) } catch {}
        $root.DeleteFolder('SteepAwake', 0)
    } catch {
        # The task folder is already absent.
    }

    foreach ($legacyName in $legacyTasks) {
        try {
            $root.GetTask($legacyName)
            throw "The obsolete scheduled task was not removed: $legacyName"
        } catch [System.Runtime.InteropServices.COMException] {
            # Expected: the task no longer exists.
        }
    }
}

if ($Delete) {
    Remove-RegisteredTasks
    exit 0
}

if (-not $TrayExecutablePath -or -not (Test-Path -LiteralPath $TrayExecutablePath)) {
    throw "The elevated tray executable was not found: $TrayExecutablePath"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userSid = $identity.User.Value
$userName = $identity.Name
$programDirectory = Split-Path -Parent $TrayExecutablePath

$service = Connect-Scheduler
$root = $service.GetFolder('\')
try {
    $folder = $root.GetFolder('\SteepAwake')
} catch {
    $folder = $root.CreateFolder('SteepAwake', $null)
}

$principal = New-ScheduledTaskPrincipal `
    -UserId $userName -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$action = New-ScheduledTaskAction `
    -Execute $TrayExecutablePath -Argument '--task-entry' `
    -WorkingDirectory $programDirectory

Register-ScheduledTask -TaskPath $taskPath -TaskName $taskName `
    -Action $action -Principal $principal -Settings $settings -Force | Out-Null

# Do not let the interactive user redefine the high-integrity action.
$protectedSddl = "O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;$userSid)"
$folder.SetSecurityDescriptor($protectedSddl, 0)
$registered = $folder.GetTask($taskName)
$registered.SetSecurityDescriptor($protectedSddl, 0x10)

foreach ($legacyName in $legacyTasks) {
    try { $root.DeleteTask($legacyName, 0) } catch {}
    try {
        $root.GetTask($legacyName) | Out-Null
        & schtasks.exe /Delete /TN "\$legacyName" /F 2>&1 | Out-Null
    } catch {}
}

$registered = $folder.GetTask($taskName)
$registeredAction = $registered.Definition.Actions.Item(1)
if (-not $registered.Enabled `
    -or $registered.Definition.Principal.RunLevel -ne 1 `
    -or $registered.Definition.Principal.LogonType -ne 3 `
    -or $registeredAction.Path -ne $TrayExecutablePath `
    -or $registeredAction.Arguments -ne '--task-entry' `
    -or $registered.Settings.ExecutionTimeLimit -ne 'PT0S') {
    throw 'The protected SteepAwake tray task did not validate after registration.'
}

[pscustomobject]@{
    TaskPath = $taskPath
    TaskName = $taskName
    Principal = $userName
    Action = $TrayExecutablePath
    Arguments = '--task-entry'
    RunLevel = 'Highest'
    ExecutionTimeLimit = 'PT0S'
}
