
=== The Pandora. P2P Social Network

Contents

1) overview
2) system requirements
3) installation in Ubuntu
4) installation in Windows
5) installation in Debian
6) manual installation or update
7) join as developer
8) getting help


1. OVERVIEW

Pandora is a free peer-to-peer (P2P) social network application.
It affords functions of instant messenger, audio and video chat, trading
platform, commercial system, payment system, distributed development
system, file exchange and vote system. Pandora has its own binary protocol,
uses a cryptography and a web of trust.

Pandora is not yet another "geek thing". It is designed for ordinary people,
has a graphical user interface (GUI) and works "out of the box".

See user manual with pictures in wiki to quick start:
https://github.com/Novator/Pandora/wiki/Install-and-first-run


2. SYSTEM REQUIREMENTS

Mandatory:
- Linux or Windows OS (another also possible)
- SQLite database (MySQL, Postgree, Firebird or another)
- Ruby script engine
- GTK2 graphical library
- OpenSSL crypto library
Optional:
- GStreamer media library


3. INSTALLATION IN UBUNTU

Do commands in terminal:

  sudo apt-add-repository -y ppa:pandora-net/ppa
  sudo apt-get update
  sudo apt-get install -y pandora-net


4. INSTALLATION IN WINDOWS

Download an installation and run it with administrator:

  http://sourceforge.net/projects/pandora-net/files/pandora_setup.exe/download


5. INSTALLATION IN DEBIAN

Download a package and install it with root:

  http://sourceforge.net/projects/pandora-net/files/pandora-net_0.1-1ubuntu_all.deb/download
  dpkg -i pandora-net_0.1-1ubuntu_all.deb


6. MANUAL INSTALLATION OR UPDATE

6.1. Download the archive and unpack it:

  https://github.com/Novator/Pandora/archive/master.zip

6.2. Install packets:

  ruby, ruby-sqlite3, ruby-gtk2, ruby-gstreamer, openssl, gstreamer0.10-x,
  gstreamer0.10-ffmpeg, gstreamer0.10-plugins-good, gstreamer0.10-plugins-bad

6.3. Set executable rights:

  chmod +x ./pandora.sh

6.4. Copy shortcut to desktop with root and edit paths inside:

  cp ./view/pandora.desktop /usr/share/applications/
  nano /usr/share/applications/pandora.desktop

Pandora updates itself automatically, but partly (only main working files).
Full update, including documentation and language files, can require manual downloads.

6.5. Also you can run shell for semi-automatic update:

  ./pandora.sh --full-init


7. JOIN AS DEVELOPER

7.1. See current technical tasks at file:

  https://github.com/Novator/Pandora/blob/master/doc/todo.ru.txt

7.2. Registrate on GitHub:

  https://github.com/

For example, your login is "YourNick".

7.3. Push "Fork" button on top of Pandora github page:

  https://github.com/Novator/Pandora/fork

7.4. Install git in Ubuntu:

  sudo apt-get -y install git

in Windows install last "Git-N.N.N-previewYYYYMMDD.exe" from:

  http://code.google.com/p/msysgit/downloads/list

7.5. Download Pandora to your hard disk via git command:

  git clone --depth=1 https://github.com/YourNick/Pandora.git

Warning: change "YourNick" to your login!

7.6. Correct a code with any text editor, for example Geany:

  http://www.geany.org/Download/Releases

7.7. Update your github repository:

  git commit -a -m "your comment" && git push

(see more useful git commands in the file "git.sh")

7.8. Push "Pull Request" at your Pandora github page:

  https://github.com/YourNick/Pandora/pull/new/master

If your contribution will be rated as useful it will be added to next release.
When you show yourself like active developer you will be added as collaborator.


8. GETTING HELP

Help to Pandora project like a programmer, translator, journalist or donator:

  http://robux.biz/pandora.html

Communicate together in facebook or vkontakte:

  https://www.facebook.com/p2pandora
  https://vk.com/pandoranet

Ask author for help:

  http://facebook.com/robux
  http://vk.com/robux
  robux@mail.ru
  Michael Galyuk

