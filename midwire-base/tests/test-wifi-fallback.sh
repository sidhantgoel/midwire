#!/bin/bash
# Tests wifi-fallback's decisions against a stand-in for NetworkManager.
#
#   docker run --rm -v "$PWD:/midwire:ro" debian:trixie bash /midwire/midwire-base/tests/test-wifi-fallback.sh
#
# Run it in a throwaway container: it writes to /fake, /fakebin and /tmp.
#
# The stand-in keeps profiles, the Wi-Fi interface's state and the networks
# in range as files, and copies the behaviour of the real thing that the
# script depends on: a scan returns nothing while the hotspot is up, joining
# a network fails when it is out of range or refuses the password, and
# taking the hotspot down leaves the interface idle. What this checks is the script's
# decisions. It proves nothing about a real radio.
set -uo pipefail
S=$(cd "$(dirname "$0")/.." && pwd)/wifi-fallback
pass=0; fail=0
check() { if [ "$2" = True ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1  [$2]"; fi; }

N=/fake/nm
mkdir -p /fakebin
cat > /fakebin/nmcli <<'EOF'
#!/bin/bash
N=/fake/nm
echo "nmcli $*" >> /tmp/calls
get=; fields=
while :; do
	case ${1:-} in
	-g) get=$2; shift 2 ;;
	-f) fields=$2; shift 2 ;;
	-t) shift ;;
	--wait) shift 2 ;;
	*) break ;;
	esac
done
escape() { sed 's/[:\\]/\\&/g'; }
profile() { # directory of the profile with this UUID or name
	local p
	for p in "$N"/profiles/*; do
		[ -d "$p" ] || continue
		if [ "$(basename "$p")" = "$1" ] || [ "$(cat "$p/name")" = "$1" ]; then echo "$p"; return 0; fi
	done
	return 1
}
case "${1:-} ${2:-}" in
"device status")
	echo "lo:connected (externally)"
	echo "eth0:unavailable"
	[ -e "$N/no-wifi-device" ] || echo "wlan0:$(cat "$N/state")"
	;;
"device show")
	[ "$get" = GENERAL.CONNECTION ] && escape < "$N/active"
	;;
"connection down")
	p=$(profile "$3") || exit 10
	[ "$(cat "$p/name")" = "$(cat "$N/active")" ] || exit 10
	echo disconnected > "$N/state"; : > "$N/active"
	;;
"device wifi")
	# NetworkManager does not scan while it hosts a hotspot.
	[ "$(cat "$N/active")" = midwire-hotspot ] && exit 0
	escape < "$N/visible"
	;;
"connection show")
	if [ -z "${3:-}" ]; then
		for p in "$N"/profiles/*; do
			[ -d "$p" ] || continue
			case $fields in
			NAME) escape < "$p/name" ;;
			UUID,TYPE) echo "$(basename "$p"):$(cat "$p/type")" ;;
			esac
		done
	else
		p=$(profile "$3") || exit 10
		case $get in
		802-11-wireless.mode) cat "$p/mode" ;;
		802-11-wireless.ssid) escape < "$p/ssid" ;;
		802-11-wireless.hidden) cat "$p/hidden" ;;
		connection.autoconnect) cat "$p/autoconnect" ;;
		esac
	fi
	;;
"connection modify")
	p=$(profile "$3") || exit 10
	[ "$4" = connection.autoconnect ] && echo "$5" > "$p/autoconnect"
	;;
"connection up")
	p=$(profile "$3") || exit 10
	if [ "$(cat "$p/mode")" = ap ]; then
		[ -e "$N/hotspot-fails" ] && exit 4
	elif [ "$(cat "$p/accepts")" != yes ] \
		|| { [ "$(cat "$p/hidden")" != yes ] && ! grep -qxF -- "$(cat "$p/ssid")" "$N/visible"; }; then
		echo disconnected > "$N/state"; : > "$N/active"
		exit 4
	fi
	echo connected > "$N/state"; cat "$p/name" > "$N/active"
	;;
esac
exit 0
EOF
# Devices connected to the hotspot.
cat > /fakebin/iw <<'EOF'
#!/bin/bash
for _ in $(seq 1 "$(cat /fake/nm/stations)"); do echo "Station 02:00:00:00:00:01 (on wlan0)"; done
EOF
# No real waiting. What NetworkManager does by itself while the script
# waits is put in /fake/nm/meanwhile by a test.
cat > /fakebin/sleep <<'EOF'
#!/bin/bash
echo "sleep $*" >> /tmp/calls
if [ -e /fake/nm/meanwhile ]; then bash /fake/nm/meanwhile; rm -f /fake/nm/meanwhile; fi
EOF
chmod +x /fakebin/*

# add UUID NAME MODE SSID [AUTOCONNECT] [ACCEPTS] [HIDDEN]
add() {
	mkdir -p "$N/profiles/$1"
	echo "$2" > "$N/profiles/$1/name"; echo 802-11-wireless > "$N/profiles/$1/type"
	echo "$3" > "$N/profiles/$1/mode"; echo "$4" > "$N/profiles/$1/ssid"
	echo "${5:-yes}" > "$N/profiles/$1/autoconnect"; echo "${6:-yes}" > "$N/profiles/$1/accepts"
	echo "${7:-no}" > "$N/profiles/$1/hidden"
}
# A Pi just powered on: Wi-Fi idle, nothing in range, the hotspot profile as
# 0.4.2 leaves it, an Ethernet profile, and a clean /run.
fresh() {
	rm -rf /fake /tmp/calls
	mkdir -p "$N/profiles/u-eth" /fake/sys/class/net/wlan0 /fake/run
	echo midwire-eth-dhcp > "$N/profiles/u-eth/name"; echo 802-3-ethernet > "$N/profiles/u-eth/type"
	add u-hot midwire-hotspot ap Midwire-AB12 no
	echo disconnected > "$N/state"; : > "$N/active"; : > "$N/visible"; echo 0 > "$N/stations"
	: > /tmp/calls
}
home() { add u-home midwire-wifi infrastructure "${1:-Home}" yes "${2:-yes}"; }
in_range() { printf '%s\n' "$@" > "$N/visible"; }
run() { PATH=/fakebin:$PATH MIDWIRE_WIFI_SYS=/fake/sys MIDWIRE_WIFI_RUN=/fake/run bash "$S" "$@"; }
go() { OUT=$(run "$@" 2>&1); RC=$?; [ -z "$OUT" ] || echo "      $OUT" | tr '\n' '|'; [ -z "$OUT" ] || echo; }
active() { cat "$N/active"; }
called() { grep -qF -- "$1" /tmp/calls; }
touched() { grep -qE 'connection up|connection down|device disconnect|connection modify' /tmp/calls; }
hosting() { [ "$(active)" = midwire-hotspot ]; }
marker() { [ -e /fake/run/wifi-fallback.hosting ]; }
long_ago() { echo 0 > "/fake/run/wifi-fallback.$1"; }
# The hotspot is up because the script fell back to it a while ago.
fallen_back() { echo connected > "$N/state"; echo midwire-hotspot > "$N/active"; long_ago hosting; : > /tmp/calls; }

echo "=== power-on ==="
fresh; rm -rf /fake/sys/class/net/wlan0
go boot
check "no Wi-Fi adapter: nothing is done, and that is not an error" "$([ $RC = 0 ] && ! touched && echo True)"

fresh
go boot
check "no saved network: the hotspot starts at once" "$([ $RC = 0 ] && hosting && ! called sleep && echo True)"

fresh; home; in_range Neighbour Home
cat > "$N/meanwhile" <<'EOF'
echo connected > /fake/nm/state; echo midwire-wifi > /fake/nm/active
EOF
go boot
check "saved network, NetworkManager joins it: the script only waits" "$([ $RC = 0 ] && [ "$(active)" = midwire-wifi ] && ! touched && echo True)"
check "and the hotspot was never started (the reported bug)" "$(! called 'connection up midwire-hotspot' && echo True)"

fresh; home; in_range Home
go boot
check "saved network in range but NetworkManager was slow: the script joins it" "$([ $RC = 0 ] && [ "$(active)" = midwire-wifi ] && called 'connection up u-home' && ! called 'connection up midwire-hotspot' && echo True)"

fresh; home; in_range Neighbour
go boot
check "saved network out of range: the hotspot starts, after the wait" "$([ $RC = 0 ] && hosting && called sleep && echo True)"
check "and it is marked as a fallback" "$(marker && echo True)"

echo "=== hosting as a fallback ==="
: > /tmp/calls
go check
check "soon after: no look for the saved network yet" "$(hosting && ! touched && echo True)"

fallen_back
go check
check "later, still out of range: a look, and the hotspot is back" "$(hosting && called 'connection down midwire-hotspot' && called 'connection up midwire-hotspot' && echo True)"
check "quietly, and the next look waits its turn" "$([ -z "$OUT" ] && [ "$(cat /fake/run/wifi-fallback.hosting)" -gt 0 ] && echo True)"

fallen_back; in_range Home; echo 1 > "$N/stations"
go check
check "saved network back, but a device is on the hotspot: left alone" "$(hosting && ! touched && echo True)"

echo 0 > "$N/stations"
go check
check "saved network back and nobody on the hotspot: it is joined" "$([ "$(active)" = midwire-wifi ] && echo True)"
check "and the fallback mark is gone" "$(! marker && echo True)"

echo "=== a saved network that refuses us (changed password) ==="
fresh; home Home no; in_range Home
go boot
check "the hotspot comes up instead" "$([ $RC = 0 ] && hosting && called 'connection up u-home' && echo True)"
check "and the refusal is remembered" "$([ -s /fake/run/wifi-fallback.failed ] && echo True)"
long_ago hosting; : > /tmp/calls
go check
check "it is not tried again while that is recent" "$(hosting && ! touched && echo True)"
long_ago failed; long_ago hosting
go check
check "it is tried again later, and the hotspot comes back when it still refuses" "$(hosting && called 'connection up u-home' && [ "$(cat /fake/run/wifi-fallback.failed)" -gt 0 ] && echo True)"
echo yes > "$N/profiles/u-home/accepts"; long_ago failed; long_ago hosting
go check
check "once it accepts again, it is joined and the refusal is forgotten" "$([ "$(active)" = midwire-wifi ] && [ ! -e /fake/run/wifi-fallback.failed ] && echo True)"

echo "=== Wi-Fi drops while joined ==="
fresh; home; in_range Neighbour
go check
check "the saved network is gone: the hotspot starts" "$([ $RC = 0 ] && hosting && marker && echo True)"
fresh; home; in_range Home
go check
check "the saved network is there after all: it is rejoined" "$([ "$(active)" = midwire-wifi ] && ! called 'connection up midwire-hotspot' && echo True)"

echo "=== states that must be left alone ==="
fresh; add u-imager preconfigured infrastructure Home; in_range Home
echo connected > "$N/state"; echo midwire-hotspot > "$N/active"
go check
check "a hotspot the user chose on the web page, with a saved network in range" "$(hosting && ! touched && echo True)"

fresh; home; in_range Home; echo connected > "$N/state"; echo midwire-wifi > "$N/active"; long_ago hosting
go check
check "joined to a saved network (and a stale fallback mark is cleared)" "$(! touched && ! marker && echo True)"

fresh; home; in_range Home; echo "connecting (getting IP configuration)" > "$N/state"; echo midwire-wifi > "$N/active"
go check
check "a connection in the making, e.g. a join from the web page" "$(! touched && echo True)"

fresh; echo unavailable > "$N/state"
go check
check "the radio switched off" "$([ $RC = 0 ] && ! touched && echo True)"

fresh; touch "$N/no-wifi-device"
go check
check "no Wi-Fi interface in NetworkManager" "$([ $RC = 0 ] && ! touched && echo True)"

fresh; home; in_range Home
( exec 9> /fake/run/wifi-fallback.lock; flock 9; /bin/sleep 3 ) &
/bin/sleep 1
go check
check "another run is busy: this one steps aside" "$([ $RC = 0 ] && [ ! -s /tmp/calls ] && echo True)"
wait

echo "=== the first start after updating from 0.4.1 ==="
# 0.4.1 let the hotspot start by itself, and it won the race at power-on.
upgraded() { fresh; echo yes > "$N/profiles/u-hot/autoconnect"; home; in_range Home; echo connected > "$N/state"; echo midwire-hotspot > "$N/active"; }
upgraded
go boot
check "the hotspot is told not to start by itself any more" "$([ "$(cat "$N/profiles/u-hot/autoconnect")" = no ] && echo True)"
check "the interface is never blocked from connecting by itself" "$(! called 'device disconnect' && echo True)"
check "and the Pi moves to the saved network" "$([ $RC = 0 ] && [ "$(active)" = midwire-wifi ] && echo True)"
upgraded; echo 2 > "$N/stations"
go boot
check "unless someone is on the hotspot: the setting changes, the hotspot stays" "$([ "$(cat "$N/profiles/u-hot/autoconnect")" = no ] && hosting && ! called 'connection down' && echo True)"
fresh; echo yes > "$N/profiles/u-hot/autoconnect"; echo connected > "$N/state"; echo midwire-hotspot > "$N/active"
go boot
check "hotspot only, no saved network: the setting changes, nothing else" "$([ $RC = 0 ] && hosting && ! called 'connection down' && ! called 'connection up' && echo True)"

echo "=== which profiles count as a saved network ==="
fresh; add u-off spare infrastructure Home no; in_range Home
go boot
check "one that is set not to connect automatically does not" "$(hosting && ! called 'connection up u-off' && echo True)"

fresh; add u-odd "Caf\\e: guest" infrastructure 'Home: 5G \ upstairs'; in_range Neighbour 'Home: 5G \ upstairs'
go boot
check "a name with a colon and a backslash is matched exactly" "$([ "$(active)" = 'Caf\e: guest' ] && echo True)"

fresh; add u-hid hidden-one infrastructure Cellar yes yes yes; in_range Neighbour
go boot
check "a hidden network is tried although no scan shows it" "$([ "$(active)" = hidden-one ] && echo True)"

fresh; add u-first first infrastructure Office; home; in_range Home
go boot
check "of several, the one in range is joined" "$([ "$(active)" = midwire-wifi ] && ! called 'connection up u-first' && echo True)"

echo "=== errors ==="
fresh; rm -rf "$N/profiles/u-hot"
go boot
check "no hotspot profile and no saved network: an error that says so" "$([ $RC != 0 ] && echo "$OUT" | grep -q 'no midwire-hotspot profile' && echo True)"
fresh; touch "$N/hotspot-fails"
go boot
check "the hotspot cannot be started: an error, and no fallback mark" "$([ $RC != 0 ] && ! marker && echo True)"
fresh
run sideways >/dev/null 2>&1; check "an unknown command is a usage error" "$([ $? = 2 ] && echo True)"

echo; echo "wifi fallback checks: $pass passed, $fail failed"
[ "$fail" = 0 ]
