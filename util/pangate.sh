#!/bin/sh

#This is a script for running Pandora, installing Ruby, and setting environment on Linux
#(c) Michael Galyuk, Pandora, free software

DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

cd "$CURDIR"

screen -x "pangate"
if [ "$?" != "0" ]; then
  screen -S "pangate" /usr/bin/python ./pangate.py
fi

