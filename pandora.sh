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
#export LANG="ua_UA.UTF-8"

DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

# Searching a path to ruby
PARAMS="$1"
RUBY=`which ruby1.8`
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
  init|install|--init|--install|-i)
    echo "Installing Ruby and necessary packages with apt-get.."
    sudo apt-get -y install ruby1.8 ruby-sqlite3 ruby-gtk2 ruby-gstreamer \
      gstreamer0.10-ffmpeg gstreamer0.10-x openssl
    ;;
  gem-init|gem-install|--gem-init|--gem-install|-gi|--gem|gem)
    echo "Installing Ruby and necessary packages with apt-get and rubygem.."
    sudo apt-get -y install ruby1.8 gstreamer0.10-ffmpeg gstreamer0.10-x openssl rubygems
    sudo gem install sqlite3 gtk2 gstreamer openssl
    ;;
  *)
    cd $CURDIR
    $RUBY ./pandora.rb $@
    ;;
esac
