#!/bin/sh

# The script creates Panreg database table 'active_nodes'
# RU: Скрипт создаёт таблицу базы данных Panreg 'active_nodes'
# 2012 (c) Michael Galyuk, P2P social network Pandora, free software, GNU GPLv2+
# RU: 2012 (c) Михаил Галюк, P2P социальная сеть Пандора, свободное ПО

mysql -u ivan -p12345 -h mysql.local.host.ru -f database < ./panreg.sql > panreg.sh.log

