
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

Pandora is a free peer-to-peer (P2P) desktop (not web) application,
designed for ordinary people, has a graphical user interface (GUI)
and works "out of the box".

It affords functions of instant messenger, audio and video chat,
encyclopedia article and file exchange, trading platform, payment
system, distributed development system and vote system. Pandora
has its own binary protocol, uses a cryptography and trust network.

The concept of Pandora is described in the article:
https://github.com/Novator/Pandora/wiki/P2P-social-network-Pandora

See the user manual with pictures in wiki to quick start:
https://github.com/Novator/Pandora/wiki/Install-and-first-run

Pandora is distributed with GNU GPLv2 license.


2. SYSTEM REQUIREMENTS

Mandatory:
- GNU/Linux, Windows or Mac OS
- Ruby1.9 or higher script engine (Ruby License)
- GTK2 graphical library (LGPLv2.1+)
- SQLite3 database library (Public domain)
- OpenSSL crypto library (Apache 2.0)
Optional:
- GStreamer0.1 media library (LGPLv2.1+)
- NCurses library (LGPLv2.1)


3. INSTALLATION IN UBUNTU

Do commands in terminal:

  sudo apt-add-repository -y ppa:pandora-net/ppa
  sudo apt-get update
  sudo apt-get install -y pandora-net


4. INSTALLATION IN WINDOWS

Download the installer and run it with administrator:

  https://github.com/Novator/Pandora/releases/download/0.7-alpha/pandora_setup.exe

Check sums pandora_setup.exe (size 20 427 683 byte):
MD5 bfbc13b2bbacd0af0d545964434f130c
SHA1 dc4b75ad7ebedcad0b09a3406b46ec9a040773f8

Use utility HashCheck to check sums in Windows:
  http://code.kliu.org/hashcheck/
or build-in Windows commands:
  certutil -hashfile .\pandora_setup.exe MD5
  certutil -hashfile .\pandora_setup.exe SHA1


5. INSTALLATION IN DEBIAN

Download a package and install it with root:

  https://github.com/Novator/Pandora/releases/download/0.7-alpha/pandora-net_0.7-ubuntu.deb
  dpkg -i pandora-net_0.7-ubuntu.deb
  apt-get -f -y install

Check sums pandora-net_0.7-ubuntu.deb (size 2 014 126 byte):
MD5 315c0275a95c3b25de80803d0d8026d5
SHA1 7e426db674df18adf132a1d99e16056184626b97

Use commands to check:
  md5sum ./pandora-net_0.7-ubuntu.deb
  sha1sum ./pandora-net_0.7-ubuntu.deb


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
  brew install adwaita-icon-theme
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

  ruby, ruby-sqlite3, ruby-gtk2, openssl, unzip, ruby-curses (or ruby-ncurses), screen,
  ruby-gstreamer, gstreamer0.10-x, gstreamer0.10-ffmpeg, gstreamer0.10-plugins-good,
  gstreamer0.10-plugins-bad

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
  telegram: robuxbiz
  tox: D7A2E3FAFA7F001B80EC0676B2F6E57A9E89FA9424A1B5F9C10347418F174D387825CF48196F
  Michael Galyuk

Support development:

  YooMoney (ex-Yandex money): 410016271392944
  TRX (Tron): TJq7HiueYNEyP596JehQg7vmvJTcuWknys
  DGB (DigiByte): DLnsoa86zc7KFDErY1P21zYGbXQuJ1dHTE
  DASH (Dash, ex-Darkcoin): XsysKkyLLYbtm2BrWMTU5L4hqThpGDejCg
  LTC (Litecoin): LR1eq5fzeQrW1jnJxcEadUJGvXgvEqHryV
  DOGE (Dogecoin): DUMULXsyZzM6aGnNC5cmY6mLuhcCPUV9Aa
  XNO (Nano): nano_3ngx166fdfhdt1az4oxiorugqm3usa4ksmks1xcpeefa8ehxyhi1upxtpznx
  XRP (Ripple): rGPc9sUvrv2gJVswv5eamWUxKQqfhFXzdY
  XMR (Monero): 4BA5qxx9Tc7FKR9veEJNUfhcajFMMYSQVKdV9TE8AB3vQAhKPYhwsciVb3X91tBhFTDsCwi4eGHHJXXHJuRjrc9mEzDUMNv
  ETH (Ethereum): 0xd58c62d18aB1f365C41DF4F86C20227b1849a204
  ETC (Ethereum Classic): 0x7dd24500f5702284fbca343fb6dc495f262730ec
  USDT-TRX (Tether TRC-20): TJq7HiueYNEyP596JehQg7vmvJTcuWknys
  USDT-ETH (Tether ERC-20): 0xd58c62d18aB1f365C41DF4F86C20227b1849a204
  BTC (BitCoin): 1CxfmmVURuHTLPMV6ykRuXqourMdTCKUEz
  BTG (Bitcoin Gold): GL9eBLsxts97rdfCUZyxaxyxMnGHUbPzf9
  BCH (Bitcoin Cash): 1CAaWL3m9AM8diTEZww17nuMiynGDwwjn4 (bitcoincash:qpa8jx9dvau9n8mjk348x6mc7kuk0dl6quqejf4rv9)
  RVN (Ravencoin): RF2b5J9qDkmWoNrfYb9N8bTjP2k8R2zWGH
  FIRO (Firo, ex-Zcoin): aNrMVXy5ZYxuKbV5QPuY8Gdo3tHCxPT7PJ
  FLX (Flux, ex-ZelCash): 0x7dd24500f5702284fbca343fb6dc495f262730ec
  BNB (Binance Chain Native): bnb152w7qrf5r7spkrvkhffq24dq7778rep9wj39g8
  BSC (Binance Smart Contract): 0x27AC8EF3365d7Eb2A6509788153C05D7F95D1C1f
  CLO (Callisto): 0xC16cF4141046717Face14855cb2942426313F625
  BEAM (Beam): 14b100f6b6a5af7e54b5dd76f09f614afdcb4860fb6f9388665728bdd299772f7c3
  GRIN (Grin): grin1hk62pv92xt6j07ffghpxdnk8m7x8x9t36d723uc4safhjkvmvc7sdwj4j5
  ERG (Ergo): 9eyWumj6UWUXkVz7u73xPgayaCh5V1hLtrr94hwy7MYmnsGVkvk
  ZEN (Horizen): znXzV9m7iiByAtskYJwdw9D143KhQf8Bv68
  ZEC (Zcash): t1dciKXmAWmDkNNLFWCczrw47m5Uj4cK2gg
  DOT (Polkadot): 13B2ynTUuhp1Hn2SPZK99ZFETqhebtoauG8FdhMzdWewcFQ1
  LETA (Letheum): iz535uH7euvXqqRhw97xsqJJkdicji2KXH63ANTRRmgz9bKBj1MQJjN1Fv75fWk2iqZB2JWq7DHHZX5ukQ2vXTx61Q7ck5NaS
  MSR (Masari): 5qHAAK99UpsLREESYZr8RKeQSf81rKNSJi6Qyf4nES48GKgwo3VDtSKDE8zGmzNyoDMg36mE9REkTL93kWUofY55DgUpLMR
  CTXC (Cortex): 0xd58c62d18aB1f365C41DF4F86C20227b1849a204
  AE (Aeternity): 0xd58c62d18aB1f365C41DF4F86C20227b1849a204
  EXP (Expanse): 0x1961aFcdaaB241266Aded2d036584082BF29c0ca
  KMD (Komodo): RB6GCiBNiT31K3vArMhP6jxB3HRrZKyb6h

  Verify requisites here:
  https://robux.perm.ru/pandora.html

