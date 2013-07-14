#!/bin/sh

#This is a script for running Pandora, installing Ruby, and setting environment on Linux
#(c) Michael Galyuk, Pandora, free software

DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

cd "$CURDIR"

screen -d -m  /usr/bin/python ./pangate.py

#screen -r
#screen -x
#screen -ls
#ctrl+a+d - detach, ctrl+a+k - kill


