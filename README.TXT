
=== The Pandora. P2P Social Network

Contents

1) overview
2) system requirements
3) installation in Linux
4) installation in Windows
5) recommendation to developers


1. OVERVIEW

Pandora is a free multiplatform distributed (p2p) information system.
Pandora includes functions of social network, instant messanger, audio and
video chatting system, commercial system, distributed development system,
file exchange system and vote system.
Read more in the guide at /doc/guide.ru.odt (Russian version yet only)


2. SYSTEM REQUIREMENTS

Mandatory:
- Linux or Windows (another also possible)
- SQLite database (MySQL, Postgree, Firebird or another)
- Ruby script engine
- GTK2 graphical library
Optional:
- GStreamer media library


3. INSTALLATION IN LINUX

3.1. Create empty directory "Pandora", download archive and extract it:

  https://github.com/Novator/Pandora/archive/master.zip

3.2. Make the script "pandora.sh" executable:

  chmod +x ./pandora.sh

3.3. Install additional packets.

3.3.1) in Ubuntu just do it:

  sudo ./pandora.sh --init

3.3.2) in other Linux install packets via your Packet Manager:

  ruby ruby-sqlite3 ruby-gtk2 ruby-gstreamer gstreamer0.10-ffmpeg gstreamer0.10-x openssl

3.4. Run Pandora by shell-file:

  ./pandora.sh


4. INSTALLATION IN WINDOWS

4.1. Download full installation from here:

  https://github.com/Novator/PandoraSetup/raw/master/pandora_setup.exe

4.2. Run Pandora from menu:

  "Start" - "Programs" - "Pandora"

4.3. Also you can run Pandora by bat-file:

  .\pandora.bat


5. RECOMMENDATION TO DEVELOPERS

Use git if you want to change a code of Pandora and send patch.

5.1. Install git in Ubuntu:

  sudo apt-get install git

5.2. Install git in Windows:

  open with browser "http://code.google.com/p/msysgit/downloads/list"
  download and install last version "Git-N.N.N-previewYYYYMMDD.exe"

5.3. Create empty directory "Pandora.dev", stay there, download Pandora with command:

  git clone --depth=1 https://github.com/Novator/Pandora.git

Now you can change the code and make patches.
See more useful git commands in the file "git.sh".

