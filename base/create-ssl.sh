#!/bin/sh

openssl req -new -x509 -sha256 -newkey rsa:2048 -days 3650 -subj '/CN=localhost' -nodes -keyout ssl.key -out ssl.crt

