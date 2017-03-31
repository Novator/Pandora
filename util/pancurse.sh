#!/bin/sh

# The script for running Pandora in console (ncurses) mode
# RU: Скрипт для запуска Пандоры в консольном (ncurse) режиме
# 2017 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2
# RU: 2017 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО


DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

#Detect the ruby interpreter location
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
        echo "Ruby is not found. Install the ruby."
        RUBY="ruby"
      fi
    fi
  fi
fi

#Move to pandora main directory from this "/util" subdirectory
cd "$CURDIR/.."

#Resume or run screen session
screen -x "pancurse"
if [ "$?" != "0" ]; then
  screen -S "pancurse" $RUBY ./pandora.rb --cui
fi

