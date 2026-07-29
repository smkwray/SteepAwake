[CmdletBinding()]
param(
    [string]$Ahk2ExePath,
    [string]$InnoSetupPath,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'src\SteepAwake.ahk'
$distDirectory = Join-Path $projectRoot 'dist'
$portablePath = Join-Path $distDirectory 'SteepAwake.exe'
$hashPath = Join-Path $distDirectory 'SHA256SUMS.txt'

& (Join-Path $projectRoot 'tools\GenerateIcons.ps1')
New-Item -ItemType Directory -Path $distDirectory -Force | Out-Null

if (-not $Ahk2ExePath) {
    $Ahk2ExePath = @(
        $env:AHK2EXE_PATH
        'C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe'
        (Join-Path $projectRoot '.tools\Ahk2Exe\Ahk2Exe.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}
if (-not $Ahk2ExePath -or -not (Test-Path -LiteralPath $Ahk2ExePath)) {
    throw 'Ahk2Exe was not found. Install the official AutoHotkey compiler or pass -Ahk2ExePath.'
}

$basePath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'
if (-not (Test-Path -LiteralPath $basePath)) {
    throw "AutoHotkey v2 x64 was not found at $basePath"
}

& $Ahk2ExePath /in $sourcePath /out $portablePath /base $basePath /silent verbose
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $portablePath)) {
    throw "Ahk2Exe failed with exit code $LASTEXITCODE."
}

if (-not $SkipInstaller) {
    if (-not $InnoSetupPath) {
        $InnoSetupPath = @(
            $env:INNO_SETUP_PATH
            'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
            'C:\Program Files\Inno Setup 6\ISCC.exe'
            (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
            Select-Object -First 1
    }
    if ($InnoSetupPath -and (Test-Path -LiteralPath $InnoSetupPath)) {
        & $InnoSetupPath (Join-Path $projectRoot 'installer\SteepAwake.iss')
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup failed with exit code $LASTEXITCODE."
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
