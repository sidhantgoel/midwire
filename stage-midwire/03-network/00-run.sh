#!/bin/bash -e

# Ethernet: the same two profiles on every device, so they ship in the image.
# NetworkManager ignores profile files that are not root-only.
install -d -m 700 "${ROOTFS_DIR}/etc/NetworkManager/system-connections"
install -m 600 files/midwire-eth-dhcp.nmconnection files/midwire-eth-direct.nmconnection \
	"${ROOTFS_DIR}/etc/NetworkManager/system-connections/"

# Wi-Fi hotspot: its name and password differ per device, so a first-boot
# service creates the midwire-hotspot profile.
install -D -m 755 files/firstboot-network "${ROOTFS_DIR}/usr/lib/midwire/firstboot-network"
install -D -m 644 files/firstboot.conf "${ROOTFS_DIR}/etc/midwire/firstboot.conf"
install -D -m 644 files/midwire-firstboot.service \
	"${ROOTFS_DIR}/etc/systemd/system/midwire-firstboot.service"

# The udev rule that keeps NetworkManager off network interfaces on USB
# devices is in the midwire-base package (see 01-packages), so that devices
# already in use get it through an update.

on_chroot << EOF
systemctl enable midwire-firstboot.service
EOF
