#!/bin/bash -e
# Runs inside the image: install the Midwire packages. apt resolves their
# dependencies (Lua, jsoncpp, FastAPI, polkit, ...) from the archives.
#
# midwire-base brings the updater, the apt source for later updates and the
# udev rule for network interfaces on USB devices. It depends on the other
# two and on raw-gadget-dkms, which 00-raw-gadget has installed.

apt-get -o Acquire::Retries=3 install -y \
	/var/tmp/midwire-debs/usb-proxy_*.deb \
	/var/tmp/midwire-debs/midwire-web-ui_*.deb \
	/var/tmp/midwire-debs/midwire-base_*.deb

rm -rf /var/tmp/midwire-debs

# usb-proxy.service stays off: the web UI starts it on demand.
systemctl enable midwire-web-ui.service
systemctl enable avahi-daemon.service
