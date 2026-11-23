#!/bin/bash
# Tests net-gadget's control flow against a fake configfs and sysfs.
#
#   docker run --rm -v "$PWD:/midwire:ro" debian:trixie bash /midwire/midwire-base/tests/test-net-gadget.sh
#
# Run it in a throwaway container: it writes to /fake, /fakebin and /tmp.
#
# A plain directory cannot act like the kernel, so this test plays the
# kernel's part by hand: it creates the network interface the kernel would
# create when the gadget is bound. What it checks is the script's own logic:
# that the interface is found whatever it is called, and that a failed start
# never leaves the USB port taken, which would stop the proxy from starting.
# It does not prove anything about the real USB controller.
set -uo pipefail
S=$(cd "$(dirname "$0")/.." && pwd)/net-gadget
pass=0; fail=0
check() { if [ "$2" = True ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  [$2]"; fi; }

# Stand-ins for the commands that touch the real system.
mkdir -p /fakebin
cat > /fakebin/modprobe <<'EOF'
#!/bin/sh
echo "modprobe $*" >> /tmp/calls
EOF
cat > /fakebin/ip <<'EOF'
#!/bin/sh
echo "ip $*" >> /tmp/calls
[ -e /tmp/ip-fails ] && exit 1
exit 0
EOF
chmod +x /fakebin/*

fresh() { # a Pi with a device controller and nothing set up yet
	rm -rf /fake /tmp/calls /tmp/ip-fails
	mkdir -p /fake/config/usb_gadget /fake/sys/class/udc/1000480000.usb /fake/sys/class/net/eth0 /fake/run
	echo "aa:bb:cc:dd:ee:ff" > /fake/sys/class/net/eth0/address
}
run() { PATH=/fakebin:$PATH MIDWIRE_NET_GADGET_CONFIGFS=/fake/config MIDWIRE_NET_GADGET_SYS=/fake/sys \
	MIDWIRE_NET_GADGET_STATE=/fake/run/net-gadget.env bash "$S" "$@"; }
G=/fake/config/usb_gadget/midwire-net
# What the kernel does on bind: a network interface with the Pi-side address.
kernel_creates() { mkdir -p "/fake/sys/class/net/$1"; cat "$G/functions/ncm.usb0/dev_addr" > "/fake/sys/class/net/$1/address"; }
udc() { cat "$G/UDC" 2>/dev/null; }

echo "=== the name the script asks the kernel for ==="
fresh; run up >/dev/null 2>&1
NAME=$(cat "$G/functions/ncm.usb0/ifname" 2>/dev/null)
check "it asks for a name with exactly one %d (the kernel's rule): '$NAME'" "$([[ $NAME =~ ^[a-z]+%d$ ]] && echo True)"

echo "=== normal start: the kernel names the interface midwire0 ==="
fresh
( sleep 1; kernel_creates midwire0 ) &
OUT=$(run up 2>&1); RC=$?; wait; echo "      $OUT" | tr '\n' '|'; echo
check "up succeeds" "$([ $RC = 0 ] && echo True)"
check "the port is taken by the link" "$([ "$(udc)" = 1000480000.usb ] && echo True)"
check "the interface is switched on and addressed" "$(grep -q 'ip link set dev midwire0 up' /tmp/calls && grep -q 'ip address replace 10.42.2.1/24 dev midwire0' /tmp/calls && echo True)"
check "the DHCP service is told which interface" "$([ "$(cat /fake/run/net-gadget.env)" = INTERFACE=midwire0 ] && echo True)"
check "the device looks like a network adapter to the computer" "$([ "$(cat $G/idVendor)" = 0x1d6b ] && [ "$(cat $G/bDeviceClass)" = 0xEF ] && [ -L $G/configs/c.1/ncm.usb0 ] && echo True)"
OUT=$(run up 2>&1); RC=$?
check "up again changes nothing and succeeds" "$([ $RC = 0 ] && echo "$OUT" | grep -q 'already up' && echo True)"
run down >/dev/null 2>&1; RC=$?
check "down frees the port and clears the state file" "$([ $RC = 0 ] && [ -z "$(udc)" ] && [ ! -e /fake/run/net-gadget.env ] && echo True)"

echo "=== the 0.4.0 bug: the kernel calls the interface usb0 ==="
fresh
( sleep 1; kernel_creates usb0 ) &
OUT=$(run up 2>&1); RC=$?; wait
check "up still succeeds: the interface is found by its address, not its name" "$([ $RC = 0 ] && echo True)"
check "usb0 is switched on, which is what makes the computer see a connected cable" "$(grep -q 'ip link set dev usb0 up' /tmp/calls && echo True)"
check "the DHCP service follows it" "$([ "$(cat /fake/run/net-gadget.env)" = INTERFACE=usb0 ] && echo True)"

echo "=== upgrade from 0.4.0: bound, interface usb0, never switched on ==="
# The state 0.4.0 leaves behind. The interface cannot be renamed without a
# reboot, so the fix is to bring it up under the name it has.
: > /tmp/calls; rm -f /fake/run/net-gadget.env
OUT=$(run up 2>&1); RC=$?; echo "      $OUT" | tr '
' '|'; echo
check "up finds the link already attached and finishes the job" "$([ $RC = 0 ] && echo "$OUT" | grep -q 'already up' && echo True)"
check "usb0 is switched on and addressed" "$(grep -q 'ip link set dev usb0 up' /tmp/calls && grep -q 'ip address replace 10.42.2.1/24 dev usb0' /tmp/calls && echo True)"
check "the port stays with the link" "$([ "$(udc)" = 1000480000.usb ] && echo True)"

echo "=== failures must never leave the port taken ==="
fresh
OUT=$(run up 2>&1); RC=$?; echo "      $OUT" | tr '\n' '|'; echo
check "no interface appears: up fails" "$([ $RC != 0 ] && echo True)"
check "and the port is free again, so the proxy can start" "$([ -z "$(udc)" ] && echo True)"
check "and no state file is left for the DHCP service" "$([ ! -e /fake/run/net-gadget.env ] && echo True)"
fresh; touch /tmp/ip-fails
( sleep 1; kernel_creates midwire0 ) &
OUT=$(run up 2>&1); RC=$?; wait
check "the interface cannot be switched on: up fails and frees the port" "$([ $RC != 0 ] && [ -z "$(udc)" ] && echo True)"

echo "=== other states ==="
fresh; rm -rf /fake/sys/class/udc/*
OUT=$(run up 2>&1); RC=$?
check "no device controller: nothing is done, and that is not an error" "$([ $RC = 0 ] && [ ! -d $G ] && echo "$OUT" | grep -q 'no USB device controller' && echo True)"
fresh
run down >/dev/null 2>&1; check "down when nothing was ever set up succeeds" "$([ $? = 0 ] && echo True)"
run sideways >/dev/null 2>&1; check "an unknown command is a usage error" "$([ $? = 2 ] && echo True)"

echo; echo "gadget flow checks: $pass passed, $fail failed"
[ "$fail" = 0 ]
