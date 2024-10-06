rem (c) Michael Galyuk, Pandora, GNU GPLv2+, free software
rem .\pandora.bat --version >> .\doc\versions.txt
rem .\pandora.bat --md5 >> .\doc\versions.txt
rem date /T >> .\doc\versions.txt
rem time /T >> .\doc\versions.txt

rem git pull

git commit -a -m "version 0.69 alpha"
git push -u github master
git push -u bitbuc master

