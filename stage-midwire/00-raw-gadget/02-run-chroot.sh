#!/bin/bash -e
# Runs inside the image. The Raspberry Pi OS kernels are built without
# CONFIG_USB_RAW_GADGET, so raw_gadget comes from our DKMS package.

apt-get -o Acquire::Retries=3 install -y /var/tmp/midwire-debs/raw-gadget-dkms_*.deb

module_version=$(dpkg-query -W -f='${Version}' raw-gadget-dkms | sed 's/+.*//')

# `uname -r` here is the build machine's kernel, not the Pi's, so DKMS cannot
# be left to pick the kernel. Build for every kernel in the image.
for dir in /lib/modules/*/; do
	kernel=$(basename "$dir")
	if [ ! -e "$dir/build" ]; then
		echo "raw-gadget: no kernel headers for $kernel" >&2
		exit 1
	fi
	if ! dkms status -m raw-gadget -v "$module_version" -k "$kernel" | grep -q installed; then
		dkms install -m raw-gadget -v "$module_version" -k "$kernel"
	fi
	if ! ls "$dir"updates/dkms/raw_gadget.ko* >/dev/null 2>&1; then
		echo "raw-gadget: module was not installed for $kernel" >&2
		exit 1
	fi
done

dkms status
