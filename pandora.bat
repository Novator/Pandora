@echo off
rem This is a script for running Pandora[, installing Ruby, and settuping] on Windows
rem (c) Michael Galyuk, Pandora, free software
rem p.s. It's need to add functionality for download and install ruby and necessary packages
rem when ruby is not found.

rem Changing the current path to Pandora place
for /f %%i in ("%0") do set curpath=%%~dpi
cd /d %curpath%

rem Advice: uncomment lines if your want to reinitialize GTK for new path when it doesn't work
rem set PATH=.\ruby\lib\GTK\bin;%PATH%
rem set MSGMERGE_PATH=".\ruby\lib\GTK\bin\msgmerge.exe"
rem .\ruby\lib\GTK\bin\gdk-pixbuf-query-loaders.exe > .\ruby\lib\GTK\etc\gtk-2.0\gdk-pixbuf.loaders
rem .\ruby\lib\GTK\bin\gtk-query-immodules-2.0.exe > .\ruby\lib\GTK\etc\gtk-2.0\gtk.immodules
rem .\ruby\lib\GTK\bin\pango-querymodules.exe > .\ruby\lib\GTK\etc\pango\pango.modules

.\ruby\bin\rubyw.exe .\pandora.rb
