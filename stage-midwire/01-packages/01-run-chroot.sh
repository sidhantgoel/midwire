#!/bin/bash -e
# Runs inside the image: install the two Midwire packages. apt resolves
# their dependencies (Lua, jsoncpp, FastAPI, polkit, ...) from the archives.

apt-get -o Acquire::Retries=3 install -y \
	/var/tmp/midwire-debs/usb-proxy_*.deb \
	/var/tmp/midwire-debs/midwire-web-ui_*.deb

rm -rf /var/tmp/midwire-debs

# usb-proxy.service stays off: the web UI starts it on demand.
systemctl enable midwire-web-ui.service
systemctl enable avahi-daemon.service
