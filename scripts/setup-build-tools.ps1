[CmdletBinding()]
param(
    [string]$ToolRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $ToolRoot) {
    $ToolRoot = Join-Path $projectRoot '.tools'
}
$ToolRoot = [IO.Path]::GetFullPath($ToolRoot)
$downloadDirectory = Join-Path $ToolRoot 'downloads'
$autoHotkeyDirectory = Join-Path $ToolRoot 'AutoHotkey'
$compilerDirectory = Join-Path $autoHotkeyDirectory 'Compiler'
$innoDirectory = Join-Path $ToolRoot 'InnoSetup'

$autoHotkeyUrl = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.26/AutoHotkey_2.0.26.zip'
$autoHotkeyHash = '43522AA3122A57784AC5DB30ABF85C2244475C36ACD7796E2C993355F9E926AE'
$compilerUrl = 'https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe1.1.37.01c/Ahk2Exe1.1.37.01c.zip'
$compilerHash = '9F2C7F990C554BA286616DD08E59AC32D543E80EEF335F5C65762C020234BC1B'
$innoPackageUrl = 'https://community.chocolatey.org/api/v2/package/InnoSetup/6.7.1'
$innoPackageHash = 'A0DAD33DB33099D9CD2B89AC2D08B5D70C589B15118CED3B95F469F044F99950'
$innoInstallerHash = '4D11E8050B6185E0D49BD9E8CC661A7A59F44959A621D31D11033124C4E8A7B0'

function Get-VerifiedFile {
    param(
        [string]$Uri,
        [string]$Path,
        [string]$ExpectedHash
    )

    if (Test-Path -LiteralPath $Path) {
        $existingHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($existingHash -eq $ExpectedHash) {
            return
        }
        Remove-Item -LiteralPath $Path -Force
    }

    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Path
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash) {
        Remove-Item -LiteralPath $Path -Force
        throw "Checksum mismatch for $Uri. Expected $ExpectedHash; received $actualHash."
    }
}

New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $autoHotkeyDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $compilerDirectory -Force | Out-Null

$autoHotkeyArchive = Join-Path $downloadDirectory 'AutoHotkey_2.0.26.zip'
$compilerArchive = Join-Path $downloadDirectory 'Ahk2Exe1.1.37.01c.zip'
$innoPackage = Join-Path $downloadDirectory 'innosetup.6.7.1.nupkg'

Get-VerifiedFile -Uri $autoHotkeyUrl -Path $autoHotkeyArchive -ExpectedHash $autoHotkeyHash
Get-VerifiedFile -Uri $compilerUrl -Path $compilerArchive -ExpectedHash $compilerHash
Get-VerifiedFile -Uri $innoPackageUrl -Path $innoPackage -ExpectedHash $innoPackageHash

Expand-Archive -LiteralPath $autoHotkeyArchive -DestinationPath $autoHotkeyDirectory -Force
Expand-Archive -LiteralPath $compilerArchive -DestinationPath $compilerDirectory -Force

$innoPackageDirectory = Join-Path $ToolRoot 'InnoPackage'
New-Item -ItemType Directory -Path $innoPackageDirectory -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory(
    $innoPackage, $innoPackageDirectory, $true)
$innoInstaller = Join-Path $innoPackageDirectory 'tools\innosetup-6.7.1.exe'
$actualInnoHash = (Get-FileHash -LiteralPath $innoInstaller -Algorithm SHA256).Hash
if ($actualInnoHash -ne $innoInstallerHash) {
    throw "Embedded Inno Setup checksum mismatch. Expected $innoInstallerHash; received $actualInnoHash."
}

$innoCompiler = Join-Path $innoDirectory 'ISCC.exe'
if (-not (Test-Path -LiteralPath $innoCompiler)) {
    $arguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /CURRENTUSER /DIR="' +
        $innoDirectory + '"'
    $process = Start-Process -FilePath $innoInstaller -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Inno Setup installation failed with exit code $($process.ExitCode)."
    }
}

$tools = [pscustomobject]@{
    AutoHotkey = Join-Path $autoHotkeyDirectory 'AutoHotkey64.exe'
    Ahk2Exe = Join-Path $compilerDirectory 'Ahk2Exe.exe'
    InnoSetup = $innoCompiler
}
foreach ($path in $tools.PSObject.Properties.Value) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Expected build tool was not created: $path"
    }
}
$tools
