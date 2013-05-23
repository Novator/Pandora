
=== The Pandora. P2P Social Network

Contents

1) overview
2) system requirements
3) installation in Ubuntu/Debian
4) installation in other Linux
5) installation in Windows
6) update to last version
7) recommendation to developers


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


3. INSTALLATION IN UBUNTU/DEBIAN

Download a package:

  wget http://sourceforge.net/projects/pandora-net/files/pandora-net_0.1-1precise2_all.deb/download

Install it:

  sudo dpkg -i pandora-net_0.1-1precise2_all.deb


4. INSTALLATION IN OTHER LINUX

4.1. Download Pandora shell file, make executable and run with "--full-init":

  wget https://raw.github.com/Novator/Pandora/master/pandora.rb
  chmod +x ./pandora.sh
  ./pandora.sh --full-init

4.2. Install packets with Packet Manager if they didn't installed automatically:

  ruby, ruby-sqlite3, ruby-gtk2, ruby-gstreamer, openssl, gstreamer0.10-x,
  gstreamer0.10-ffmpeg, gstreamer0.10-plugins-good, gstreamer0.10-plugins-bad

4.3. Run Pandora from menu "Start-Network-Pandora" or use shell:

  ./pandora.sh


5. INSTALLATION IN WINDOWS

5.1. Download full installation from here:

  http://sourceforge.net/projects/pandora-net/files/pandora_setup.exe/download

5.2. Run Pandora from menu:

  "Start" - "Programs" - "Pandora"

5.3. Also you can run Pandora with bat-file:

  .\pandora.bat


6. UPDATE TO LAST VERSION

Pandora is updating itself automatically, but partly.
6.1. For full update just do it in Linux:

  ./pandora.sh --full-init

6.2. Or download and extract archive:

  https://github.com/Novator/Pandora/archive/master.zip

6.3. Overwrite old files by new. The default directory for Linux is:

  /opt/pandora/

For Windows:

  C:\Program Files\Pandora\


7. RECOMMENDATION TO DEVELOPERS

Use git if you want to change a code of Pandora and send a patch.

7.1. Install git

in Ubuntu:

  sudo apt-get install git

in Windows:

  open with browser "http://code.google.com/p/msysgit/downloads/list"
  download and install last version "Git-N.N.N-previewYYYYMMDD.exe"

7.2. Create empty directory "Pandora.dev", stay there, download Pandora with command:

  git clone --depth=1 https://github.com/Novator/Pandora.git

Now you can change the code and make patches.
See more useful git commands in the file "git.sh".

