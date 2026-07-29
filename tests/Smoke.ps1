$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'src\SteepAwake.ahk'
$generatorPath = Join-Path $projectRoot 'tools\GenerateIcons.ps1'
$installerPath = Join-Path $projectRoot 'installer\SteepAwake.iss'
$autoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

Assert-True (Test-Path -LiteralPath $sourcePath) 'Missing AutoHotkey source.'
Assert-True (Test-Path -LiteralPath $generatorPath) 'Missing icon generator.'
Assert-True (Test-Path -LiteralPath $installerPath) 'Missing installer definition.'

& $generatorPath

Add-Type -AssemblyName System.Drawing
$iconNames = foreach ($theme in 'dark','light') {
    foreach ($state in 'normal','timed','indefinite') {
        "$state-$theme.ico"
    }
}
foreach ($iconName in $iconNames) {
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

$source = Get-Content -LiteralPath $sourcePath -Raw
Assert-True ($source -match 'StartSession\(360,\s*"6 hours"\)') 'The 6-hour session is missing.'
Assert-True ($source -match 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run') 'Per-user startup support is missing.'
Assert-True ($source -match 'PowerWriteACValueIndex') 'AC power-policy write is missing.'
Assert-True ($source -match 'PowerWriteDCValueIndex') 'DC power-policy write is missing.'
Assert-True ($source -notmatch 'A_ComSpec|RunWait|\.Exec\(') 'The app must not launch command shells.'

$installer = Get-Content -LiteralPath $installerPath -Raw
Assert-True ($installer -match 'PrivilegesRequired=lowest') 'Installer must not require elevation.'
Assert-True ($installer -match 'Start SteepAwake automatically with Windows') 'Installer startup checkbox is missing.'
Assert-True ($installer -match 'Parameters: "exit"') 'Uninstaller must stop SteepAwake cleanly.'

if (Test-Path -LiteralPath $autoHotkeyPath) {
    $syntaxArguments = '/ErrorStdOut "' + $sourcePath + '" exit'
    $syntaxProcess = Start-Process -FilePath $autoHotkeyPath `
        -ArgumentList $syntaxArguments -WindowStyle Hidden -Wait -PassThru
    Assert-True ($syntaxProcess.ExitCode -eq 0) `
        "AutoHotkey syntax check failed with exit code $($syntaxProcess.ExitCode)."
} else {
    Write-Warning 'AutoHotkey is not installed; skipped executable syntax validation.'
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

"Smoke checks passed: $($iconNames.Count) icons, source syntax, startup, installer, and power-policy wiring."
