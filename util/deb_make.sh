#!/bin/sh

#cp -f ./GitHub/Pandora/* ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/base ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/doc ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/lang ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/model ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/view ./deb/opt/pandora
#cp -rf ./GitHub/Pandora/util ./deb/opt/pandora
chmod -R a+rw ./deb/opt/pandora
fakeroot dpkg-deb --build -v ./deb pandora-net_0.7-ubuntu.deb


#fakeroot dpkg-deb --build -v ./deb pandora-net_0.1-1precise2_all.deb

