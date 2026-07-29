[CmdletBinding()]
param(
    [string]$Ahk2ExePath,
    [string]$AutoHotkeyPath,
    [string]$InnoSetupPath,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'src\SteepAwake.ahk'
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$buildDirectory = Join-Path $projectRoot 'build'
$buildSourcePath = Join-Path $buildDirectory 'SteepAwake.ahk'
$distDirectory = Join-Path $projectRoot 'dist'
$portablePath = Join-Path $distDirectory 'SteepAwake.exe'
$hashPath = Join-Path $distDirectory 'SHA256SUMS.txt'

& (Join-Path $projectRoot 'tools\GenerateIcons.ps1')
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

$buildSource = Get-Content -LiteralPath $sourcePath -Raw
$buildSource = $buildSource -replace (
    '(?m)^;@Ahk2Exe-SetFileVersion .+$'),
    ";@Ahk2Exe-SetFileVersion $version"
$buildSource = $buildSource -replace (
    '(?m)^;@Ahk2Exe-SetProductVersion .+$'),
    ";@Ahk2Exe-SetProductVersion $version"
Set-Content -LiteralPath $buildSourcePath -Value $buildSource -Encoding utf8NoBOM

if (-not $Ahk2ExePath) {
    $Ahk2ExePath = @(
        $env:AHK2EXE_PATH
        'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
        (Join-Path $projectRoot '.tools\AutoHotkey\Compiler\Ahk2Exe.exe')
        (Join-Path $projectRoot '.tools\Ahk2Exe\Ahk2Exe.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}
if (-not $Ahk2ExePath -or -not (Test-Path -LiteralPath $Ahk2ExePath)) {
    throw 'Ahk2Exe was not found. Install the official AutoHotkey compiler or pass -Ahk2ExePath.'
}

if (-not $AutoHotkeyPath) {
    $AutoHotkeyPath = @(
        $env:AUTOHOTKEY_PATH
        (Join-Path $projectRoot '.tools\AutoHotkey\AutoHotkey64.exe')
        'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}
if (-not $AutoHotkeyPath -or -not (Test-Path -LiteralPath $AutoHotkeyPath)) {
    throw 'AutoHotkey v2 x64 was not found. Run scripts\setup-build-tools.ps1 or pass -AutoHotkeyPath.'
}

$compilerArguments = '/in "' + $buildSourcePath + '" /out "' + $portablePath +
    '" /base "' + $AutoHotkeyPath + '" /silent verbose'
$compilerProcess = Start-Process -FilePath $Ahk2ExePath `
    -ArgumentList $compilerArguments -WindowStyle Hidden -Wait -PassThru
if ($compilerProcess.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $portablePath)) {
    throw "Ahk2Exe failed with exit code $($compilerProcess.ExitCode)."
}

if (-not $SkipInstaller) {
    if (-not $InnoSetupPath) {
        $InnoSetupPath = @(
            $env:INNO_SETUP_PATH
            (Join-Path $projectRoot '.tools\InnoSetup\ISCC.exe')
            'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
            'C:\Program Files\Inno Setup 6\ISCC.exe'
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
            Select-Object -First 1
    }
    if ($InnoSetupPath -and (Test-Path -LiteralPath $InnoSetupPath)) {
        $innoScript = Join-Path $projectRoot 'installer\SteepAwake.iss'
        $innoArguments = '/DMyAppVersion="' + $version + '" "' + $innoScript + '"'
        $innoProcess = Start-Process -FilePath $InnoSetupPath `
            -ArgumentList $innoArguments -WindowStyle Hidden -Wait -PassThru
        if ($innoProcess.ExitCode -ne 0) {
            throw "Inno Setup failed with exit code $($innoProcess.ExitCode)."
        }
    } else {
        Write-Warning 'Inno Setup was not found; the portable EXE was built without the installer.'
    }
}

$artifacts = Get-ChildItem -LiteralPath $distDirectory -File |
    Where-Object { $_.Extension -eq '.exe' } |
    Sort-Object Name
$hashLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($artifact.Name)"
}
Set-Content -LiteralPath $hashPath -Value $hashLines -Encoding utf8NoBOM

$artifacts | Select-Object Name, Length, @{
    Name = 'SHA256'
    Expression = { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
