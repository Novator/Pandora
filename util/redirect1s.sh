#!/bin/sh

# The script for running TcpRedirector on external host at internet
# Maybe usefull when you have a channel made with ssh:
# ssh -4 -g -f -N -R 127.0.0.1:5577:127.0.0.1:5577 user@222.222.222.222


DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

cd "$CURDIR"

screen -x "redirect1"
if [ "$?" != "0" ]; then
  screen -S "redirect1" `which python` ./redirect1.py 222.222.222.222 5577 127.0.0.1 5577
fi

