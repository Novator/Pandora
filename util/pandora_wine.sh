#!/bin/sh

CURDIR=`dirname "$DIRFILE"`
cd "$CURDIR"

wine ./ruby193/bin/rubyw.exe pandora.rb &


