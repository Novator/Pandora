#!/bin/sh

python ./redirect1.py 222.222.222.222 5577 127.0.0.1 5577

#ssh -4 -g -f -N -R 127.0.0.1:5577:127.0.0.1:5577 user@robux.perm.ru

