#############################################
 The Pandora. Distributed Social Network
#############################################

Contents

1) overview
2) system require
3) installation


OVERVIEW

Pandora is a free multiplatform distributed (p2p) information system.
Pandora includes functions of social network, instant messanger, audio and
video chatting system, commercial system, distributed development system
and vote system.
Read more in the guide at /doc/guide.ru.odt (Russian version yet only)


SYSTEM REQUIRE

Mandatory:
- Ubuntu or Windows (another also possible)
- SQLite database (MySQL, Postgree, Firebird or another)
- Ruby script engine
- GTK2 graphical library
Optional:
- GStreamer media library


INSTALLATION

1. Install git in Ubuntu:

  sudo apt-get install git

(in Windows install "Git-x.x.x...exe" from here:
http://code.google.com/p/msysgit/downloads/list)

2. Create empty directory "Pandora", stay there, download Pandora with git:

  mkdir /home/user/Pandora
  cd /home/user/Pandora
  git clone https://github.com/Novator/Pandora.git

3. Make script Pandora.sh executable:

  chmod +x ./pandora.sh

4. Install additional utils and packets in Ubuntu:

  sudo ./pandora.sh --init

(in Windows you can unpack archive from here:
https://github.com/Novator/RubyFull/raw/master/rubyfull.exe)

5. Run Pandora in Ubuntu:

  ./pandora.sh

(in Windows run batch file pandora.bat)
