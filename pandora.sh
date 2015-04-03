#!/bin/sh

#This is a script for running Pandora, installing Ruby, and setting environment on Linux
#(c) Michael Galyuk, Pandora, free software

# Advice: uncomment a line if Pandora cannot define your language correctly
#export LANG="de_DE.UTF-8"
#export LANG="es_ES.UTF-8"
#export LANG="fr_FR.UTF-8"
#export LANG="it_IT.UTF-8"
#export LANG="pl_PL.UTF-8"
#export LANG="ru_RU.UTF-8"
#export LANG="tr_TR.UTF-8"
#export LANG="en_US.UTF-8"
#export LANG="en_AU.UTF-8"
#export LANG="ua_UA.UTF-8"

DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

# Searching a path to ruby
PARAMS="$1"
RUBY=`which ruby2.0`
if [ "$RUBY" = "" ]; then
  RUBY=`which ruby1.9.3`
  if [ "$RUBY" = "" ]; then
    RUBY=`which ruby1.9.1`
    if [ "$RUBY" = "" ]; then
      RUBY=`which ruby`
    fi
  fi
fi
if [ "$RUBY" = "" ]; then
  if [ ! -f "$RUBY" ]; then
    RUBY="/usr/bin/ruby"
    if [ ! -f "$RUBY" ]; then
      RUBY="/usr/local/bin/ruby"
      if [ ! -f "$RUBY" ]; then
        echo "Ruby is not found. Trying to install by \"$CURFILE init\""
        RUBY="ruby"
        PARAMS="init"
      fi
    fi
  fi
fi

# Make an action according to command line arguments
case "$PARAMS" in
  help|h|--help|?|/?)
    echo "Script Pandora params:"
    echo "  $CURFILE --help     - show this help"
    echo "  $CURFILE --init     - install necessary packets with apt-get (recommended)"
    echo "  $CURFILE --gem-init - install minimum packets, install ruby packet with rubygem"
    echo "  $CURFILE [params]   - run Pandora with original params"
    if [ -f "$RUBY" ]; then
      $RUBY ./pandora.rb --shell
    fi
    ;;
  full|full-init|--full|--full-init|-fi)
    PANDORA_DIR="/opt/pandora"
    # 1. Make Pandora application directory
    sudo mkdir $PANDORA_DIR
    # 2. Give rights to Pandora to all users
    sudo chmod -R a+rw $PANDORA_DIR
    # 3. Go to Pandora directory
    cd $PANDORA_DIR
    # 4. Download archive with last Pandora version
    wget -t 0 -c -T 15 --retry-connrefused=on https://github.com/Novator/Pandora/archive/master.zip
    # 5. Extract archive [to subdirectory "Pandora-master"]
    unzip -o ./master.zip
    # 6. Move files to application directory
    mv -f ./Pandora-master/* ./
    # 7. Delete empty "Pandora-master"
    rm -R ./Pandora-master
    # 8. Delete unnecessary archive
    rm ./master.zip
    # 9. Make main script executable
    chmod a+x ./pandora.sh
    # 10. Copy shortcut to Menu
    sudo cp -f ./view/pandora.desktop /usr/share/applications/
    # 11. Install additional packets (ruby, openssl, sqlite, gstreamer)
    ./pandora.sh --init
    # 12. Give rights to all users again
    sudo chmod -R a+rw $PANDORA_DIR
    # 13. Run Pandora
    $RUBY ./pandora.rb $@
    ;;
  init|install|--init|--install|-i)
    case "$OSTYPE" in
      darwin*)  #Macosx
        xcode-select --install
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
        brew install gtk+
        brew install sqlite3
        brew install xquartz
        brew install Caskroom/cask/xquartz
        DISPTH=`find /private/tmp -path /private/tmp/com.apple.launchd.*/org.macosforge.xquartz -print`
        export DISPLAY=$DISPTH\:0
        sudo gem install sqlite3
        sudo gem install gtk2
        echo "It is recommended to reboot your computer."
        ;;
      linux*)
        echo "Installing Ruby and necessary packages with apt-get.."
        sudo apt-get -y install ruby ruby-sqlite3 ruby-gtk2 ruby-gstreamer \
          gstreamer0.10-ffmpeg gstreamer0.10-x openssl libopenssl-ruby
        ;;
      *)
        echo "You should install ruby, sqlite3 and gtk2 manually for: $OSTYPE"
        ;;
    esac
    ;;
  gem-init|gem-install|--gem-init|--gem-install|-gi|--gem|gem)
    echo "Installing Ruby and necessary packages with apt-get and rubygem.."
    sudo apt-get -y install ruby gstreamer0.10-ffmpeg gstreamer0.10-x openssl rubygems
    sudo gem install sqlite3 gtk2 gstreamer openssl
    ;;
  *)
    cd "$CURDIR"
    $RUBY ./pandora.rb $@
    ;;
esac

