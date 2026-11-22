#!/bin/bash -e

# Put the USB-C port in device (gadget) mode. usb-proxy presents the proxied
# device to the target computer through it.
CONFIG="${ROOTFS_DIR}/boot/firmware/config.txt"
if ! grep -q '^dtoverlay=dwc2,dr_mode=peripheral$' "${CONFIG}"; then
	cat >> "${CONFIG}" <<- 'EOF'

		[all]
		# Midwire: USB-C port in device (gadget) mode for usb-proxy.
		dtoverlay=dwc2,dr_mode=peripheral
	EOF
fi

install -m 644 files/midwire.conf "${ROOTFS_DIR}/etc/modules-load.d/midwire.conf"
