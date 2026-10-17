#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$TrayExecutablePath,
    [switch]$Delete,
    # Check the destination and create it admin-only before setup copies files.
    [switch]$PrepareDestination
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

if (-not $TrayExecutablePath) {
    throw 'The elevated tray executable path is required.'
}
$TrayExecutablePath = [IO.Path]::GetFullPath($TrayExecutablePath)
if (-not $PrepareDestination -and -not [IO.File]::Exists($TrayExecutablePath)) {
    throw "The elevated tray executable was not found: $TrayExecutablePath"
}

# The task runs the tray elevated on demand, so no non-administrator may be
# able to replace its executable or any directory on the way to it.
$trustedSids = @(
    'S-1-5-18'      # SYSTEM
    'S-1-5-32-544'  # Administrators
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'  # TrustedInstaller
)
# Inside Program Files: WriteData, AppendData, DeleteChild, Delete, WRITE_DAC,
# WRITE_OWNER, GENERIC_ALL, GENERIC_WRITE.
$writeMask = 0x2 -bor 0x4 -bor 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 `
    -bor 0x10000000 -bor 0x40000000
# Program Files and its ancestors may allow creating siblings (the drive root
# does), but nothing that renames, deletes, or re-permissions the path.
$replaceMask = 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000

# Inheritable ACEs on a directory decide what its future children allow, so
# directories inside Program Files are checked with them included.
function Assert-AdminOnlyPath([string]$Path, [int]$Mask, [bool]$IncludeInheritable) {
    # Use .NET rather than Get-Item/Get-Acl, which can fail to autoload when
    # setup inherits a PowerShell 7 module path.
    $attributes = [IO.File]::GetAttributes($Path)
    if ($attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to register the elevated task through a reparse point: $Path"
    }
    $sidType = [Security.Principal.SecurityIdentifier]
    $sections = [Security.AccessControl.AccessControlSections]'Owner, Access'
    $acl = if ($attributes -band [IO.FileAttributes]::Directory) {
        New-Object Security.AccessControl.DirectorySecurity($Path, $sections)
    } else {
        New-Object Security.AccessControl.FileSecurity($Path, $sections)
    }
    $owner = $acl.GetOwner($sidType).Value
    if ($owner -notin $trustedSids) {
        throw "Refusing to register the elevated task: $Path is not owned by an administrator."
    }
    foreach ($rule in $acl.GetAccessRules($true, $true, $sidType)) {
        if ($rule.AccessControlType -ne 'Allow') { continue }
        $inheritOnly = $rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly
        if ($inheritOnly -and -not $IncludeInheritable) { continue }
        if (([int]$rule.FileSystemRights -band $Mask) -eq 0) { continue }
        # CREATOR OWNER resolves to the creator, which is elevated setup here.
        if ($inheritOnly -and $rule.IdentityReference.Value -eq 'S-1-3-0') { continue }
        if ($rule.IdentityReference.Value -notin $trustedSids) {
            throw "Refusing to register the elevated task: $Path is writable by $($rule.IdentityReference.Value)."
        }
    }
}

# Setup runs 32-bit PowerShell, so read the Program Files locations from the
# 64-bit registry view rather than from inheritable environment variables.
$hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
    [Microsoft.Win32.RegistryHive]::LocalMachine,
    [Microsoft.Win32.RegistryView]::Registry64)
$currentVersion = $hklm.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion')
$programRoots = @('ProgramFilesDir', 'ProgramFilesDir (x86)') |
    ForEach-Object { $currentVersion.GetValue($_) } | Where-Object { $_ } |
    ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') }
$programRoot = $programRoots | Where-Object {
    $TrayExecutablePath.StartsWith($_ + '\', [StringComparison]::OrdinalIgnoreCase) } |
    Select-Object -First 1
$installDirectory = [IO.Path]::GetDirectoryName($TrayExecutablePath)
# The install directory gets its own DACL, so it must be strictly inside
# Program Files and never Program Files itself.
if (-not $programRoot -or $installDirectory.TrimEnd('\').Length -le $programRoot.Length) {
    throw "Refusing to register the elevated task outside Program Files: $TrayExecutablePath"
}

# Walk from the executable to the drive root. Only the install directory may
# be missing, and only while preparing it.
$checkedPath = $TrayExecutablePath
while ($checkedPath) {
    $insideRoot = $checkedPath.Length -gt $programRoot.Length
    $isDirectory = [IO.Directory]::Exists($checkedPath)
    if ($isDirectory -or [IO.File]::Exists($checkedPath)) {
        Assert-AdminOnlyPath $checkedPath `
            ($(if ($insideRoot) { $writeMask } else { $replaceMask })) `
            ($insideRoot -and $isDirectory)
    } elseif (-not ($PrepareDestination -and
        ($checkedPath -eq $TrayExecutablePath -or $checkedPath -eq $installDirectory))) {
        throw "The parent folder must already exist: $checkedPath"
    }
    $checkedPath = [IO.Path]::GetDirectoryName($checkedPath)
}

if ($PrepareDestination) {
    # Give the install directory a protected admin-only DACL so the files setup
    # copies inherit nothing from the parent. A new directory is created with
    # this descriptor atomically.
    $security = New-Object Security.AccessControl.DirectorySecurity
    $security.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($grant in @(
            @('S-1-5-18', 'FullControl'),
            @('S-1-5-32-544', 'FullControl'),
            @('S-1-5-32-545', 'ReadAndExecute'))) {
        $security.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($grant[0])),
            [Security.AccessControl.FileSystemRights]$grant[1], $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)))
    }
    $directory = New-Object IO.DirectoryInfo($installDirectory)
    $desktop = $PSVersionTable.PSEdition -eq 'Desktop'
    if (-not $directory.Exists) {
        $security.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        if ($desktop) {
            [IO.Directory]::CreateDirectory($installDirectory, $security) | Out-Null
        } else {
            [IO.FileSystemAclExtensions]::Create($directory, $security)
        }
    } elseif ($desktop) {
        $directory.SetAccessControl($security)
    } else {
        [IO.FileSystemAclExtensions]::SetAccessControl($directory, $security)
    }
    Assert-AdminOnlyPath $installDirectory $writeMask $true
    exit 0
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
    -or $registered.Definition.Settings.ExecutionTimeLimit -ne 'PT0S') {
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
