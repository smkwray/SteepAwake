#define MyAppName "SteepAwake"
#ifndef MyAppVersion
  #define MyAppVersion "0.2.1"
#endif
#define MyAppPublisher "smkwray"
#define MyAppExeName "SteepAwake.exe"
#define MyAppTrayExeName "SteepAwake.Tray.exe"

[Setup]
AppId={{D6704288-B2B3-448F-A221-ED1F33174BAE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\dist
OutputBaseFilename=SteepAwake-Setup
SetupIconFile=..\assets\indefinite-dark.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
CloseApplications=yes
CloseApplicationsFilter=SteepAwake*.exe
RestartApplications=no

[Tasks]
Name: startup; Description: "Start SteepAwake automatically with Windows"; GroupDescription: "Additional options:"; Flags: checkedonce

[Files]
Source: "..\dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\{#MyAppTrayExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\scripts\register-tasks.ps1"; DestDir: "{app}"
Source: "..\scripts\uninstall.ps1"; DestDir: "{app}"

[InstallDelete]
Type: filesandordirs; Name: "{localappdata}\Programs\SteepAwake"

[Icons]
Name: "{userprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"

[INI]
Filename: "{localappdata}\SteepAwake\device.ini"; Section: "Device"; Key: "EnableAsusOptimizationToggle"; String: "1"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\register-tasks.ps1"" -TrayExecutablePath ""{app}\{#MyAppTrayExeName}"""; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--shutdown --wait"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopSteepAwake"
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveSteepAwake"
