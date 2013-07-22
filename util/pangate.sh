#!/bin/sh

# The script for running Pangate (Pandora gate) on external host at internet
# RU: Скрипт для запуска Pangate (шлюз Пандоры) на внешнем хосте в интернете
# 2012 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2
# RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО


DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

cd "$CURDIR"

screen -x "pangate"
if [ "$?" != "0" ]; then
  screen -S "pangate" /usr/bin/python ./pangate.py
fi

