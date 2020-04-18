Name "Pandora"
OutFile "pandora_setup.exe"
InstallDir "$PROGRAMFILES\Pandora"
RequestExecutionLevel admin

;Pages
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "Pandora with Ruby"
  SectionIn RO
  SetOutPath $INSTDIR\lib
  File "..\lib\*.rb"
  SetOutPath $INSTDIR\base
  File "..\base\create-ssl.sh"
  CreateDirectory "$INSTDIR\files"
  SetOutPath $INSTDIR\doc
  File "..\doc\changelog.txt"
  File "..\doc\diagram.ru.odg"
  File "..\doc\guide.en.odt"
  File "..\doc\guide.ru.odt"
  File "..\doc\guide.ru.pdf"
  File "..\doc\ip6.txt"
  File "..\doc\todo.ru.txt"
  File "..\doc\versions.txt"
  SetOutPath $INSTDIR\util
  File "..\util\dynv6.net.sh"
  File "..\util\dynv6.net.user.sh"
  File "..\util\git-win.bat"
  File "..\util\pancurse.sh"
  File "..\util\pandora1.sh"
  File "..\util\pandora2.sh"
  File "..\util\pandora3.sh"
  File "..\util\pandora_setup.nsi"
  File "..\util\pandora_setup.sh"
  File "..\util\pangate.ini"
  File "..\util\pangate.py"
  File "..\util\pangate.sh"
  File "..\util\panreg.ini"
  File "..\util\panreg.php"
  File "..\util\panreg.sh"
  File "..\util\panreg.sql"
  File "..\util\redirect1.py"
  File "..\util\redirect1.sh"
  File "..\util\redirect1s.sh"
  File "..\util\restart.rb"
  SetOutPath $INSTDIR\view
  File "..\view\*"
  SetOutPath $INSTDIR
  File /r "..\lang"
  File /r "..\model"
  File /r "..\web"
  File /r "..\ruby193"
  File "..\git.sh"
  File "..\LICENSE.TXT"
  File "..\pandora.bat"
  File "..\pandora.rb"
  File "..\pandora.sh"
  File "..\README.TXT"
  File "..\util\pandora_wine.sh"

  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora" "DisplayName" "Pandora"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora" "DisplayIcon" '"$INSTDIR\view\pandora.ico"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora" "NoRepair" 1

  CreateShortCut "$DESKTOP\Pandora.lnk" "$INSTDIR\ruby193\bin\rubyw.exe" "pandora.rb" "$INSTDIR\view\pandora.ico"
  CreateShortCut "$QUICKLAUNCH\Pandora.lnk" "$INSTDIR\ruby193\bin\rubyw.exe" "pandora.rb" "$INSTDIR\view\pandora.ico"
  CreateDirectory "$SMPROGRAMS\Pandora"
  CreateShortCut "$SMPROGRAMS\Pandora\Pandora.lnk" "$INSTDIR\ruby193\bin\rubyw.exe" "pandora.rb" "$INSTDIR\view\pandora.ico"
  CreateShortCut "$SMPROGRAMS\Pandora\Uninstall.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pandora"
  RMDir /r "$INSTDIR"
  RMDir /r "$SMPROGRAMS\Pandora"
  Delete "$DESKTOP\Pandora.lnk"
  Delete "$QUICKLAUNCH\Pandora.lnk"
SectionEnd
