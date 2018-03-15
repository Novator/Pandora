
=== The Pandora. P2P Social Network

Contents

1) overview
2) system requirements
3) installation in Ubuntu
4) installation in Windows
5) installation in Debian
6) preparation of Macosx
7) manual installation or update
8) console user interface
9) getting help


1. OVERVIEW

Pandora is a free peer-to-peer (P2P) social network application.
It affords functions of instant messenger, audio and video chat,
encyclopedia article and file exchange, trading platform, payment
system, distributed development system and vote system. Pandora
has its own binary protocol, uses a cryptography and a web of trust.

Pandora is not yet another "geek thing". It is designed for ordinary people,
has a graphical user interface (GUI) and works "out of the box".

The concept of Pandora is described in the article:
https://github.com/Novator/Pandora/wiki/P2P-social-network-Pandora

See the user manual with pictures in wiki to quick start:
https://github.com/Novator/Pandora/wiki/Install-and-first-run


2. SYSTEM REQUIREMENTS

Mandatory:
- Linux, Windows or Mac OS
- Ruby1.9 or higher script engine
- GTK2 graphical library
- SQLite3 database library
- OpenSSL crypto library
Optional:
- GStreamer0.1 media library


3. INSTALLATION IN UBUNTU

Do commands in terminal:

  sudo apt-add-repository -y ppa:pandora-net/ppa
  sudo apt-get update
  sudo apt-get install -y --fix-missing pandora-net


4. INSTALLATION IN WINDOWS

Download an installation and run it with administrator:

  http://sourceforge.net/projects/pandora-net/files/pandora_setup.exe
  https://github.com/Novator/Pandora/releases/download/0.3-alpha/pandora_setup.exe


5. INSTALLATION IN DEBIAN

Download a package and install it with root:

  http://sourceforge.net/projects/pandora-net/files/pandora-net_0.6-1ubuntu_all.deb
  https://github.com/Novator/Pandora/releases/download/0.3-alpha/pandora-net_0.2-1ubuntu_all.deb
  dpkg -i pandora-net_0.6-1ubuntu_all.deb
  apt-get -f -y install


6. PREPARATION OF MACOSX

Run these commands in terminal:

  xcode-select --install
  ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
  brew update
  brew doctor
  brew install ruby
  brew install rbenv
  brew install ruby-build
  brew install openssl
  echo 'if which rbenv > /dev/null; then eval "$(rbenv init -)"; fi' >> ~/.bash_profile
  source ~/.bash_profile
  rbenv install -l
  RUBY_CONFIGURE_OPTS=--with-openssl-dir=`brew --prefix openssl` rbenv install 2.2.2
  brew install gtk+
  brew install sqlite3
  brew install Caskroom/cask/xquartz
  sudo gem update --system
  rvm implode
  \curl -sSL https://get.rvm.io | bash -s stable --ruby --autolibs=enable
  rvm reload

Restart your computer. Run also:

  rvm install 2.2.2
  rvm use 2.2.2 --default
  sudo gem install sqlite3
  sudo gem install gtk2

Download and unpack master.zip (see the next chapter), run pandora.sh.


7. MANUAL INSTALLATION OR UPDATE

7.1. Download the archive and unpack it:

  https://github.com/Novator/Pandora/archive/master.zip

or download the code with a git:

  git clone --depth=1 https://github.com/Novator/Pandora.git

7.2. Install needed packages if they still are not installed:

  ruby, ruby-sqlite3, ruby-gtk2, openssl, unzip, ruby-ncurses, ruby-gstreamer,
  gstreamer0.10-x, gstreamer0.10-ffmpeg, gstreamer0.10-plugins-good, gstreamer0.10-plugins-bad

7.3. Set executable rights:

  chmod +x ./pandora.sh

7.4. Copy shortcut to desktop with root and edit paths inside:

  cp ./view/pandora.desktop /usr/share/applications/
  nano /usr/share/applications/pandora.desktop

Pandora can update itself by user click to button on status bar.


8. CONSOLE USER INTERFACE

By default Pandora launches Gtk2 graphical user interface,
but you can force it to launch Ncurses console user interface:

  ./pandora.sh -c   -- this is Curses/Ncurses mode
  ./pandora.sh -s   -- run via screen or return to session
  ./util/pancurse.sh      -- run or return screen session
  ./util/pancurse.sh -d   -- run via screen like a daemon

Console interface is useful on Raspberri Pi, dedicated or
virtual servers, when you need to have day-and-night node.

Attention: CUI has pared-down functionality in comparison with GUI.
It is recommended to setup all preferences in GUI mode on desktop
computer, then move ./base/pandora.sqlite to remote computer.


9. GETTING HELP

Communicate together in facebook or vkontakte:

  https://www.facebook.com/p2pandora
  https://vk.com/pandoranet

Ask author for help:

  http://facebook.com/robux
  http://vk.com/robux
  robux@mail.ru
  tox: D7A2E3FAFA7F001B80EC0676B2F6E57A9E89FA9424A1B5F9C10347418F174D387825CF48196F
  Michael Galyuk

Support development:

  BitCoin: 1PanDR1Q6TL3qE1TSs2Zagt2ihhEiCBHZB

