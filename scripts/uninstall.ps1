[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\SteepAwake'
$installedExe = Join-Path $installDirectory 'SteepAwake.exe'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (Test-Path -LiteralPath $installedExe) {
    $exitProcess = Start-Process -FilePath $installedExe -ArgumentList 'exit' `
        -WindowStyle Hidden -PassThru
    $exitProcess.WaitForExit(5000) | Out-Null
}

Remove-ItemProperty -LiteralPath $runKey -Name SteepAwake `
    -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $installedExe) {
    Remove-Item -LiteralPath $installedExe -Force
}
if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Force
}

'SteepAwake was removed. User preferences remain in %LOCALAPPDATA%\SteepAwake.'
