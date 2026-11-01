; BillBox for Windows: installer (Inno Setup 6). Built by desktop/build.sh windows <version>.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
[Setup]
AppId={{6B3F3C1E-8E7A-4C61-9B8E-0B111B0C0001}
AppName=BillBox
AppVersion={#AppVersion}
AppPublisher=AK Enterprises
AppPublisherURL=https://billbox-app.pages.dev
DefaultDirName={autopf}\BillBox
DefaultGroupName=BillBox
UninstallDisplayIcon={app}\BillBox.exe
OutputDir={#OutDir}
OutputBaseFilename=BillBox-windows-{#AppVersion}-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#AppDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BillBox"; Filename: "{app}\BillBox.exe"
Name: "{autodesktop}\BillBox"; Filename: "{app}\BillBox.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\BillBox.exe"; Description: "Open BillBox"; Flags: nowait postinstall skipifsilent
