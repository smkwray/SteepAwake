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
Source: "..\scripts\uninstall.ps1"; DestDir: "{app}"; AfterInstall: RegisterTrayTask

[InstallDelete]
Type: filesandordirs; Name: "{localappdata}\Programs\SteepAwake"

[Icons]
Name: "{userprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Setup creates {app} itself with a protected DACL, so Inno does not log it.
Type: dirifempty; Name: "{app}"

[UninstallRun]
Filename: "{app}\{#MyAppExeName}"; Parameters: "--shutdown --wait"; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "StopSteepAwake"
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\uninstall.ps1"""; Flags: runhidden waituntilterminated skipifdoesntexist; RunOnceId: "RemoveSteepAwake"

[Code]
// build.ps1 embeds scripts\register-tasks.ps1 as an encoded PowerShell command,
// so setup never runs a script from the destination folder.
#include "..\build\RegisterTasks.iss"

var
  TaskRegistrationFailed: Boolean;

function SetEnvironmentVariable(Name, Value: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

// Strictly inside Folder: installing into Program Files itself would replace
// that shared folder's DACL.
function IsUnderFolder(Path, Folder: String): Boolean;
begin
  Folder := AddBackslash(Folder);
  Path := AddBackslash(Path);
  Result := (Folder <> '\') and (Length(Path) > Length(Folder)) and
    (CompareText(Copy(Path, 1, Length(Folder)), Folder) = 0);
end;

// Runs register-tasks.ps1 directly (no command shell) with its arguments in the
// environment, logging its output to the setup log.
function RunRegisterTasks(TrayExecutablePath: String; PrepareDestination: Boolean): Integer;
var
  ResultCode: Integer;
begin
  SetEnvironmentVariable('STEEPAWAKE_TRAY_EXE', TrayExecutablePath);
  if PrepareDestination then
    SetEnvironmentVariable('STEEPAWAKE_PREPARE', '1')
  else
    SetEnvironmentVariable('STEEPAWAKE_PREPARE', '0');
  if not ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand {#RegisterTasksCommand}',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode, nil) then
    ResultCode := -1;
  Result := ResultCode;
end;

// The protected task starts the tray elevated, so a location a
// non-administrator could modify would let them run code as administrator.
// Check the destination's ancestry and create the install folder with an
// admin-only, non-inheriting DACL before any file is written.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not IsUnderFolder(WizardDirValue, ExpandConstant('{commonpf64}')) and
     not IsUnderFolder(WizardDirValue, ExpandConstant('{commonpf32}')) then
    Result := 'SteepAwake must be installed under Program Files because its tray runs elevated.'
  else if RunRegisterTasks(AddBackslash(WizardDirValue) + '{#MyAppTrayExeName}', True) <> 0 then
    Result := 'SteepAwake must be installed in a Program Files folder that only administrators can modify.';
end;

procedure RegisterTrayTask;
var
  ResultCode: Integer;
begin
  ResultCode := RunRegisterTasks(ExpandConstant('{app}\{#MyAppTrayExeName}'), False);
  if ResultCode <> 0 then
  begin
    TaskRegistrationFailed := True;
    Log('Protected tray task registration failed with exit code ' + IntToStr(ResultCode) + '.');
    SuppressibleMsgBox('SteepAwake could not register its protected tray task (exit code ' +
      IntToStr(ResultCode) + '). The tray will not start until setup succeeds.',
      mbError, MB_OK, IDOK);
  end;
end;

// [Run] entries and AfterInstall exceptions do not fail a silent setup, so
// report a failed registration through the exit code.
function GetCustomSetupExitCode: Integer;
begin
  if TaskRegistrationFailed then
    Result := 9
  else
    Result := 0;
end;
