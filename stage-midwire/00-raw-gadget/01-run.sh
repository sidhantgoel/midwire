#!/bin/bash -e

# Put the .debs collected by build.sh where the chroot scripts can install
# them. Not /tmp: on_chroot mounts a tmpfs over it.
install -d "${ROOTFS_DIR}/var/tmp/midwire-debs"
install -m 644 "${STAGE_DIR}"/files/debs/*.deb "${ROOTFS_DIR}/var/tmp/midwire-debs/"
