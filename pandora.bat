@echo off
rem === This script runs (or installs) Pandora (and Ruby) on Windows
rem === (c) Michael Galyuk, Pandora, GNU GPLv2, free software

rem === Changing the current dir to bat-file place
cd /d %~dp0

rem === Set constants
set RUBY=.\ruby193\bin\rubyw.exe
set PANDORA_DIR=%CD%
set SETUP_URL=http://cznic.dl.sourceforge.net/project/pandora-net/pandora_setup.exe
set SETUP_FILE=.\pandora_setup.exe

rem === Check ruby interpreter, if exists run Pandora
if exist %RUBY% goto :RUN_PANDORA
rem --- else check setup:

rem === Check setup file, if exists run setup
if exist %SETUP_FILE% goto :SETUP_PANDORA
rem --- else download setup:


rem === Create Pandora dir if not exists
mkdir "%PANDORA_DIR%"

rem === Compose VBScript in Temp directory for http-downloading
> "%TEMP%\pandnl.vbs" echo sUrl = "%SETUP_URL%"
>> "%TEMP%\pandnl.vbs" echo sFolder = "%PANDORA_DIR%"
>> "%TEMP%\pandnl.vbs" (findstr "'--VBS" "%0" | findstr /v "findstr")
                                                           
rem === Run VBScript for download setup file, then delete it
echo Download Pandora setup from internet...
echo from: "%SETUP_URL%"
echo to: "%PANDORA_DIR%"
echo Wait a few minute, please.
cscript //nologo "%TEMP%\pandnl.vbs"
del /q "%TEMP%\pandnl.vbs"


:SETUP_PANDORA
rem === Run setup file, then run Pandora
%SETUP_FILE%

goto :RUN_PANDORA


HTTPDownload sURL, sFolder '--VBS

Sub HTTPDownload( myURL, myPath )  '--VBS
  Dim i, objFile, objFSO, objHTTP, strFile, strMsg  '--VBS
  Const ForReading = 1, ForWriting = 2, ForAppending = 8  '--VBS
  Set objFSO = CreateObject( "Scripting.FileSystemObject" )  '--VBS
  If objFSO.FolderExists( myPath ) Then  '--VBS
    strFile = objFSO.BuildPath( myPath, Mid( myURL, InStrRev( myURL, "/" ) + 1 ) )  '--VBS
  ElseIf objFSO.FolderExists( Left( myPath, InStrRev( myPath, "\" ) - 1 ) ) Then  '--VBS
    strFile = myPath  '--VBS
  Else  '--VBS
    WScript.Echo "ERROR: Target folder not found."  '--VBS
    Exit Sub  '--VBS
  End If  '--VBS
  Set objFile = objFSO.OpenTextFile( strFile, ForWriting, True )  '--VBS
  Set objHTTP = CreateObject( "WinHttp.WinHttpRequest.5.1" )  '--VBS
  objHTTP.Open "GET", myURL, False  '--VBS
  objHTTP.Send  '--VBS
  For i = 1 To LenB( objHTTP.ResponseBody )  '--VBS
    objFile.Write Chr( AscB( MidB( objHTTP.ResponseBody, i, 1 ) ) )  '--VBS
  Next  '--VBS
  objFile.Close( )  '--VBS
End Sub  '--VBS


rem === Run Pandora with Ruby
:RUN_PANDORA
"%RUBY%" .\pandora.rb %*

