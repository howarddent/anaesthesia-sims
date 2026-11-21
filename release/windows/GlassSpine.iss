; This file is part of anaesthesia-sims.
; Copyright (C) 2026 Howard Dent
; SPDX-License-Identifier: GPL-3.0-or-later
;
; Inno Setup script for the GlassSpine Windows installer. Build the program
; first with release/build-release.sh (under Git Bash), then:
;
;   iscc /DAppVersion=1.0 release\windows\GlassSpine.iss
;
; which writes release\out\GlassSpine-<version>-windows-x64-setup.exe. The
; GitHub workflow .github/workflows/windows-installers.yml does both.
;
; GlassSpine is one executable: the OpenCL kernels are compiled in, and it
; links no Intel libraries. OpenGL comes with Windows and OpenCL with the
; graphics driver, so nothing else is installed. It installs per user by
; default (no administrator rights needed); the first page offers an
; install for all users instead.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "GlassSpine"
#define AppExe "GlassSpine.exe"

[Setup]
AppId={{8D19829A-8123-470D-A3B2-846BCA8A6301}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Howard Dent
AppPublisherURL=https://github.com/howarddent/anaesthesia-sims
AppSupportURL=https://github.com/howarddent/anaesthesia-sims/issues
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
LicenseFile=..\..\LICENSE
OutputDir=..\out
OutputBaseFilename={#AppName}-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\{#AppExe}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\out\windows-x86_64\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
