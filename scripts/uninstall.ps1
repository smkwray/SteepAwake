#Requires -RunAsAdministrator
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$installDirectory = Join-Path ${env:ProgramFiles} 'SteepAwake'
$launcher = Join-Path $installDirectory 'SteepAwake.exe'
$registerScript = Join-Path $PSScriptRoot 'register-tasks.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (Test-Path -LiteralPath $launcher) {
    $shutdown = Start-Process -FilePath $launcher `
        -ArgumentList '--shutdown --wait' -WindowStyle Hidden -Wait -PassThru
    if ($shutdown.ExitCode -ne 0) {
        throw "SteepAwake did not confirm clean shutdown (exit code $($shutdown.ExitCode))."
    }
}

if (Test-Path -LiteralPath $registerScript) {
    & $registerScript -Delete
}

Remove-ItemProperty -LiteralPath $runKey -Name SteepAwake `
    -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}

[pscustomobject]@{ Removed = $installDirectory }
