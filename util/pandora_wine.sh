#!/bin/sh

#(c) Michael Galyuk, Pandora, GNU GPLv2, free software

CURDIR=`dirname "$DIRFILE"`
cd "$CURDIR"

wine ./ruby193/bin/rubyw.exe pandora.rb &


