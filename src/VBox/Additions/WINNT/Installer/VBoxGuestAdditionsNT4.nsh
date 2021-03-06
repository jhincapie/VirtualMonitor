; $Id$
; @file
; VBoxGuestAdditionsNT4.nsh - Guest Additions installation for NT4.
;

;
; Copyright (C) 2006-2012 Oracle Corporation
;
; This file is part of VirtualBox Open Source Edition (OSE), as
; available from http://www.virtualbox.org. This file is free software;
; you can redistribute it and/or modify it under the terms of the GNU
; General Public License (GPL) as published by the Free Software
; Foundation, in version 2 as it comes in the "COPYING" file of the
; VirtualBox OSE distribution. VirtualBox OSE is distributed in the
; hope that it will be useful, but WITHOUT ANY WARRANTY of any kind.
;

Function NT4_SetVideoResolution

  ; Check for all required parameters
  StrCmp $g_iScreenX "0" missingParms
  StrCmp $g_iScreenY "0" missingParms
  StrCmp $g_iScreenBpp "0" missingParms
  Goto haveParms

missingParms:

  DetailPrint "Missing display parameters for NT4, setting default (640x480, 8 BPP) ..."

  StrCpy $g_iScreenX '640'   ; Default value
  StrCpy $g_iScreenY '480'   ; Default value
  StrCpy $g_iScreenBpp '8'   ; Default value

  ; Write setting into registry to show the desktop applet on next boot
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Control\GraphicsDrivers\NewDisplay" "" ""

haveParms:

  DetailPrint "Setting display parameters for NT4 ($g_iScreenXx$g_iScreenY, $g_iScreenBpp BPP) ..."

  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.BitsPerPel" $g_iScreenBpp
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.Flags" 0x00000000
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.VRefresh" 0x00000001
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.XPanning" 0x00000000
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.XResolution" $g_iScreenX
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.YPanning" 0x00000000
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Hardware Profiles\Current\System\CurrentControlSet\Services\vboxvideo\Device0" "DefaultSettings.YResolution" $g_iScreenY

FunctionEnd

Function NT4_SaveMouseDriverInfo

  Push $0

  ; !!! NOTE !!!
  ; Due to some re-branding (see functions Uninstall_Sun, Uninstall_Innotek and
  ; Uninstall_SunXVM) the installer *has* to transport the very first saved i8042prt
  ; value to the current installer's "uninstall" directory in both mentioned
  ; functions above, otherwise NT4 will be screwed because it then would store
  ; "VBoxMouseNT.sys" as the original i8042prt driver which obviously isn't there
  ; after uninstallation anymore
  ; !!! NOTE !!!

  ; Save current mouse driver info so we may restore it on uninstallation
  ; But first check if we already installed the additions otherwise we will
  ; overwrite it with the VBoxMouseNT.sys
  ReadRegStr $0 HKLM "${PRODUCT_UNINST_KEY}" ${ORG_MOUSE_PATH}
  StrCmp $0 "" 0 exists

  DetailPrint "Saving mouse driver info ..."
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Services\i8042prt" "ImagePath"
  WriteRegStr HKLM "${PRODUCT_UNINST_KEY}" ${ORG_MOUSE_PATH} $0
  Goto exit

exists:

  DetailPrint "Mouse driver info already saved."
  Goto exit

exit:

!ifdef _DEBUG
  DetailPrint "Mouse driver info: $0"
!endif

  Pop $0

FunctionEnd

Function NT4_Prepare

  ${If} $g_bNoVBoxServiceExit == "false"
    ; Stop / kill VBoxService
    Call StopVBoxService
  ${EndIf}

  ${If} $g_bNoVBoxTrayExit == "false"
    ; Stop / kill VBoxTray
    Call StopVBoxTray
  ${EndIf}

  ; Delete VBoxService from registry
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "VBoxService"

  ; Delete old VBoxService.exe from install directory (replaced by VBoxTray.exe)
  Delete /REBOOTOK "$INSTDIR\VBoxService.exe"

FunctionEnd

Function NT4_CopyFiles

  DetailPrint "Copying files for NT4 ..."

  SetOutPath "$INSTDIR"
  FILE "$%PATH_OUT%\bin\additions\VBoxGuestDrvInst.exe"
  FILE "$%PATH_OUT%\bin\additions\RegCleanup.exe"

  ; The files to install for NT 4, they go into the system directories
  SetOutPath "$SYSDIR"
  FILE "$%PATH_OUT%\bin\additions\VBoxDisp.dll"
  FILE "$%PATH_OUT%\bin\additions\VBoxTray.exe"
  FILE "$%PATH_OUT%\bin\additions\VBoxHook.dll"
  FILE "$%PATH_OUT%\bin\additions\VBoxControl.exe"

  ; VBoxService
  FILE "$%PATH_OUT%\bin\additions\VBoxServiceNT.exe"

  ; The drivers into the "drivers" directory
  SetOutPath "$SYSDIR\drivers"
  FILE "$%PATH_OUT%\bin\additions\VBoxVideo.sys"
  FILE "$%PATH_OUT%\bin\additions\VBoxMouseNT.sys"
  FILE "$%PATH_OUT%\bin\additions\VBoxGuestNT.sys"
  ;FILE "$%PATH_OUT%\bin\additions\VBoxSFNT.sys" ; Shared Folders not available on NT4!

FunctionEnd

Function NT4_InstallFiles

  DetailPrint "Installing drivers for NT4 ..."

  ; Install guest driver
  nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" service create "VBoxGuest" "VBoxGuest Support Driver" 1 1 "$SYSDIR\drivers\VBoxGuestNT.sys" "Base"'

  ; Bugfix: Set "Start" to 1, otherwise, VBoxGuest won't start on boot-up!
  ; Bugfix: Correct invalid "ImagePath" (\??\C:\WINNT\...)
  WriteRegDWORD HKLM "SYSTEM\CurrentControlSet\Services\VBoxGuest" "Start" 1
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\VBoxGuest" "ImagePath" "System32\Drivers\VBoxGuestNT.sys"

  ; Run VBoxTray when Windows NT starts
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "VBoxTray" '"$SYSDIR\VBoxTray.exe"'

  ; Video driver
  nsExec::ExecToLog '"$INSTDIR\VBoxGuestDrvInst.exe" /i'
  Pop $0                      ; Ret value
  IntCmp $0 0 +1 error error  ; Check ret value (0=OK, 1=Error)

  DetailPrint "Installing VirtualBox service ..."

  ; Create the VBoxService service
  ; No need to stop/remove the service here! Do this only on uninstallation!
  nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" service create "VBoxService" "VirtualBox Guest Additions Service" 16 2 "system32\VBoxServiceNT.exe" "Base"'

   ; Create the Shared Folders service ...
  ;nsSCM::Install /NOUNLOAD "VBoxSF" "VirtualBox Shared Folders" 1 1 "$SYSDIR\drivers\VBoxSFNT.sys" "Network" "" "" ""
  ;Pop $0                      ; Ret value

!ifdef _DEBUG
  ;DetailPrint "SCM::Install VBoxSFNT.sys: $0"
!endif

  ;IntCmp $0 0 +1 error error  ; Check ret value (0=OK, 1=Error)

  ; ... and the link to the network provider
  ;WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\VBoxSF\NetworkProvider" "DeviceName" "\Device\VBoxMiniRdr"
  ;WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\VBoxSF\NetworkProvider" "Name" "VirtualBox Shared Folders"
  ;WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\VBoxSF\NetworkProvider" "ProviderPath" "$SYSDIR\VBoxMRXNP.dll"

  ; Add the shared folders network provider
  ;nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" netprovider add VBoxSF'
  ;Pop $0                      ; Ret value
  ;IntCmp $0 0 +1 error error  ; Check ret value (0=OK, 1=Error)

  Goto done

error:
  Abort "ERROR: Could not install files for Windows NT4! Installation aborted."

done:

FunctionEnd

Function NT4_Main

  SetOutPath "$INSTDIR"

  Call NT4_Prepare
  Call NT4_CopyFiles

  ; This removes the flag "new display driver installed on the next bootup
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\RunOnce" "VBoxGuestInst" '"$INSTDIR\RegCleanup.exe"'

  Call NT4_SaveMouseDriverInfo
  Call NT4_InstallFiles
  Call NT4_SetVideoResolution

  ; Write mouse driver name to registry overwriting the default name
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\i8042prt" "ImagePath" "System32\DRIVERS\VBoxMouseNT.sys"

FunctionEnd

!macro NT4_UninstallInstDir un
Function ${un}NT4_UninstallInstDir

  ; Delete remaining files
  Delete /REBOOTOK "$INSTDIR\VBoxGuestDrvInst.exe"
  Delete /REBOOTOK "$INSTDIR\RegCleanup.exe"

FunctionEnd
!macroend
!insertmacro NT4_UninstallInstDir ""
!insertmacro NT4_UninstallInstDir "un."

!macro NT4_Uninstall un
Function ${un}NT4_Uninstall

  Push $0

  ; Remove the guest driver service
  nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" service delete VBoxGuest'
  Delete /REBOOTOK "$SYSDIR\drivers\VBoxGuestNT.sys"

  ; Delete the VBoxService service
  Call ${un}StopVBoxService
  nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" service delete VBoxService'
  Pop $0    ; Ret value
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "VBoxService"
  Delete /REBOOTOK "$SYSDIR\VBoxServiceNT.exe"

  ; Delete the VBoxTray app
  Call ${un}StopVBoxTray
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "VBoxTray"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\RunOnce" "VBoxTrayDel" "$SYSDIR\cmd.exe /c del /F /Q $SYSDIR\VBoxTray.exe"
  Delete /REBOOTOK "$SYSDIR\VBoxTray.exe" ; If it can't be removed cause it's running, try next boot with "RunOnce" key above!
  Delete /REBOOTOK "$SYSDIR\VBoxHook.dll"

  ; Delete the VBoxControl utility
  Delete /REBOOTOK "$SYSDIR\VBoxControl.exe"

  ; Delete the VBoxVideo service
  nsExec::ExecToLog '"$INSTDIR\VBoxDrvInst.exe" service delete VBoxVideo'

  ; Delete the VBox video driver files
  Delete /REBOOTOK "$SYSDIR\drivers\VBoxVideo.sys"
  Delete /REBOOTOK "$SYSDIR\VBoxDisp.dll"

  ; Get original mouse driver info and restore it
  ReadRegStr $0 ${PRODUCT_UNINST_ROOT_KEY} "${PRODUCT_UNINST_KEY}" ${ORG_MOUSE_PATH}
  ; If we still got our driver stored in $0 then this will *never* work, so
  ; warn the user and set it to the default driver to not screw up NT4 here
  ${If} $0 == "System32\DRIVERS\VBoxMouseNT.sys"
    WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\i8042prt" "ImagePath" "System32\DRIVERS\i8042prt.sys"
    DetailPrint "Old mouse driver is set to VBoxMouseNT.sys, defaulting to i8042prt.sys ..."
  ${Else}
    WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\i8042prt" "ImagePath" $0
  ${EndIf}
  Delete /REBOOTOK "$SYSDIR\drivers\VBoxMouseNT.sys"

  Pop $0

FunctionEnd
!macroend
!insertmacro NT4_Uninstall ""
!insertmacro NT4_Uninstall "un."
