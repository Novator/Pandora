=== The Pandora. P2P Social Network

Contents

1) overview
2) system requirements
3) installation for users
4) installation for programmers


OVERVIEW

Pandora is a free multiplatform distributed (p2p) information system.
Pandora includes functions of social network, instant messanger, audio and
video chatting system, commercial system, distributed development system,
file exchange system and vote system.
Read more in the guide at /doc/guide.ru.odt (Russian version yet only)


SYSTEM REQUIREMENTS

Mandatory:
- Ubuntu or Windows (another also possible)
- SQLite database (MySQL, Postgree, Firebird or another)
- Ruby script engine
- GTK2 graphical library
Optional:
- GStreamer media library


INSTALLATION FOR USERS

1. Create empty directory "Pandora", download archive with Pandora and extract it:

  https://github.com/Novator/Pandora/archive/master.zip

2. Make script Pandora.sh executable if you use Linux:

  chmod +x ./pandora.sh

3. Also it's necessary to install additional packets.

3.1) in Ubuntu you can do this:

  sudo ./pandora.sh --init

3.2) in other Linux install packets:

  ruby1.8 ruby-sqlite3 ruby-gtk2 ruby-gstreamer gstreamer0.10-ffmpeg gstreamer0.10-x openssl

3.3) in Windows you can unpack archive from here:

  https://github.com/Novator/RubyFull/raw/master/rubyfull.exe

4. Run Pandora

4.1) in Linux run script:

  ./pandora.sh

4.2) in Windows run batch file:

  .\pandora.bat


INSTALLATION FOR PROGRAMMERS

Use git if you want to change a code of Pandora and send patch.

1. Install git in Ubuntu:

  sudo apt-get install git

(in Windows install "Git-x.x.x...exe" from here:
http://code.google.com/p/msysgit/downloads/list)

2. Create empty directory "Pandora.dev", stay there, download Pandora with git:

  git clone --depth=1 https://github.com/Novator/Pandora.git

Now you can change the code and make patches.
