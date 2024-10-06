#!/bin/sh

# The script for running redirector external port 5577 to internal port made by ssh
# RU: Скрипт для перенаправления внешнего порта 5577 на внутренний, созданный ssh
# Maybe usefull when you have a channel made with ssh -R command:
# ssh -4 -g [-f] -N -R 127.0.0.1:5577:127.0.0.1:5577 user@222.222.222.222
# 2012 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2+
# RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО



DIRFILE=`readlink -e "$0"`
CURFILE=`basename "$DIRFILE"`
CURDIR=`dirname "$DIRFILE"`

cd "$CURDIR"

screen -x "redirect1"
if [ "$?" != "0" ]; then
  screen -S "redirect1" `which python` ./redirect1.py 222.222.222.222 5577 127.0.0.1 5577
fi

