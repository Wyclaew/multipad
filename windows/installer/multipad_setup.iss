; =====================================================================
; MultiPad Inno Setup Installer Script
; Target: Windows x64 (AMD64 / ARM64 x64-emulation)
; Produces: MultiPad-Windows-Setup.exe
; Author: Wyclaew
; =====================================================================

#define MyAppName "MultiPad"
#ifndef AppVersion
  #define AppVersion "1.4.1"
#endif
#define MyAppPublisher "Wyclaew"
#define MyAppURL "https://github.com/Wyclaew/multipad"
#define MyAppExeName "multipad.exe"
#define MyAppBuildDir "..\..\build\windows\x64\runner\Release"
#define MyAppId "{{E680E1C6-9D11-4FA3-8DE8-9B948AC60CE3}}"

[Setup]
; Unique application identifier for Windows Add/Remove Programs registry
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppVerName={#MyAppName} {#AppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases

; Default install location & dual-mode privileges:
; When run by standard user: {autopf} resolves to {localappdata}\Programs (e.g. C:\Users\<user>\AppData\Local\Programs\MultiPad)
; When run by administrator: {autopf} resolves to Program Files (e.g. C:\Program Files\MultiPad)
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline

; Seamless in-place updates & overwriting:
; Re-uses previous install directory and skips directory selection page if already installed
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousSetupType=yes
UsePreviousTasks=yes
DisableDirPage=auto

; Process management & application closing during update/setup:
CloseApplications=yes
CloseApplicationsFilter=multipad.exe,*.exe,*.dll
RestartApplications=yes

; Output binary settings:
OutputDir=..\..
OutputBaseFilename=MultiPad-Windows-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

; Compression and visual styling:
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no

; 64-bit architecture constraints:
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter application executable
Source: "{#MyAppBuildDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; All bundled Flutter dependencies, flutter_windows.dll, icudtl.dat, and flutter_assets
Source: "{#MyAppBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "{#MyAppExeName}"

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"

[Registry]
; Register application in App Paths so 'multipad' or 'multipad.exe' can be launched via Win+R or Command Prompt
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: "Path"; ValueData: "{app}"; Flags: uninsdeletekey

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\*.log"

[Code]
// Helper function to cleanly terminate running multipad.exe instance before extraction
// to prevent ERROR 5 (Access Denied) when updating locked binaries in-place.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ErrorCode: Integer;
begin
  Result := '';
  // Forcefully and silently kill running multipad.exe process tree if active
  ShellExec('open', 'taskkill.exe', '/F /IM multipad.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ErrorCode);
  // Brief pause for Windows file system locks to release
  Sleep(300);
end;

// Helper function to terminate running multipad.exe before uninstallation
function InitializeUninstall(): Boolean;
var
  ErrorCode: Integer;
begin
  Result := True;
  // Terminate running multipad.exe process tree if active during uninstallation
  ShellExec('open', 'taskkill.exe', '/F /IM multipad.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ErrorCode);
  Sleep(300);
end;
