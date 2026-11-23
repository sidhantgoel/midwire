# Midwire

Midwire is a Raspberry Pi image that turns a Pi 4 or Pi 5 into a USB proxy.
The Pi sits between a computer and a USB device, forwards the traffic, and
lets you watch, capture or change it from a web page.

It is Raspberry Pi OS Lite (64-bit, Debian trixie) plus:

- [usb-proxy](https://github.com/sidhantgoel/usb-proxy), which does the proxying.
- `midwire-web-ui`, the web page that starts and stops it.
- The `raw_gadget` kernel module usb-proxy needs. Raspberry Pi kernels are
  built without it, so this repo packages it with DKMS (`raw-gadget-dkms/`).
- The USB-C port switched to device mode, and network settings that make
  the web page reachable without any setup.
- `midwire-base` (`midwire-base/` in this repo): the updater behind the web
  page's Updates tab, and the apt source it installs from.

This repository builds the image and publishes the packages devices update
from. It is a thin wrapper around
[pi-gen](https://github.com/RPi-Distro/pi-gen), the tool that builds
Raspberry Pi OS itself.

## Using the image

### Flash it

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Either
pick "Use custom" and select the downloaded `midwire-<version>-arm64.img.xz`,
or add Midwire to Imager's list: in Imager's options, set the content
repository to

    https://github.com/sidhantgoel/midwire/releases/latest/download/os_list_midwire.json

Imager's customisation screen works as it does for Raspberry Pi OS: set a
user name and password, the Wi-Fi country, and SSH there. The image has no
default user or password of its own.

### Connect to it

Open **http://midwire.local** once you are on the same network as the Pi,
and log in with user name `admin`, password `admin`. The page offers to
change that password after the first login; do so before leaving the Pi on
a network you share with others. **https://midwire.local** works too: the
Pi creates its own certificate on first start, so your browser shows a
warning once that you have to accept. There are five ways to get there:

| How | What happens |
|---|---|
| Ethernet to your router or switch | The Pi gets an address from your network, like any other device. |
| Ethernet straight to your computer | After about 30 seconds without an answer from a DHCP server, the Pi takes `10.42.1.1` and gives your computer an address. |
| Wi-Fi hotspot | The Pi creates a network called `Midwire-XXXX` (the last four characters differ per device) and is at `10.42.0.1`. |
| Your own Wi-Fi | Once you have joined a network on the page's Network tab (or set one in Raspberry Pi Imager), the Pi joins it at every start instead of hosting the hotspot. |
| The USB-C cable itself | While the proxy is stopped, the USB-C port is a network adapter: the computer it is plugged into gets an address and reaches the Pi at `10.42.2.1`. The link drops while the proxy runs. |

The hotspot's password is `midwire-setup` on every new device. The setup
wizard on the first login asks you to change it, and the page keeps a
reminder up until you do. To start with your own name and password instead,
create `midwire-hotspot.txt` on the SD card's `bootfs` partition before the
first boot:

    SSID=MyMidwire
    PASSWORD=at-least-8-characters
    COUNTRY=GB

All three lines are optional. `COUNTRY` is the two-letter Wi-Fi regulatory
country; set it here or in Imager. Without one the hotspot still starts,
on 2.4 GHz channel 6, which is allowed everywhere.

If you move an Ethernet cable from a computer to a router or back, unplug it
for ten seconds first so the Pi notices and tries DHCP again.

The hotspot is the fallback for your own Wi-Fi. With a network saved, the
Pi gives it about 45 seconds at power-on and hosts the hotspot only if it
could not join. If the network disappears later, the hotspot comes up
within a few minutes, and when the network is back the Pi rejoins it. It
looks for the network at most every five minutes, and never while a
device is connected to the hotspot, because looking takes the hotspot
down for a few seconds. A network that refuses the Pi, for example after
its password was changed, is tried again every half hour; correct the
password on the Network tab.

### Wire it up

- The **USB-C port** goes to the computer. It is the only port that can act
  as a USB device, on both the Pi 4 and the Pi 5.
- The **USB device** you want to proxy goes in one of the USB-A ports.
- **Power:** the USB-C port is also the Pi's power input, and a computer's
  USB port often cannot supply enough, especially for a Pi 5. Power the Pi
  some other way and it is reliable: a USB-C power/data splitter, a PoE
  HAT, or 5 V on the GPIO header.
- Do not boot the Pi from a USB drive you might select as the device to
  proxy. Boot from the SD card.

Compute Module 4 and 5 are not supported: their USB ports are wired
differently.

## Building it

You need Linux with Docker and git, and plenty of free disk space: pi-gen
keeps a full copy of the system for every stage. On Windows, use WSL2 and clone the repository inside the Linux filesystem (for
example `~/midwire`), not under `/mnt/c`: pi-gen needs Linux file
permissions, and `build.sh` refuses to run from a Windows drive.

    git clone https://github.com/sidhantgoel/midwire.git
    cd midwire
    ./build.sh

The image is written to `deploy/midwire-<version>-arm64.img.xz`. On an x86
PC the ARM code is emulated, so the build is much slower than on an arm64
machine.

What `build.sh` does:

1. Clones pi-gen at the commit pinned in `versions.env` into `build/pi-gen`.
2. Collects four `.deb` packages (`scripts/fetch-debs.sh`): usb-proxy and
   midwire-web-ui from their GitHub releases, and raw-gadget-dkms and
   midwire-base built from this repo.
3. Copies `stage-midwire/` and `config` into pi-gen and runs its Docker
   build with the stages `stage0 stage1 stage2 stage-midwire`.

Useful variations:

| Command | Effect |
|---|---|
| `MIDWIRE_VERSION=1.2.3 ./build.sh` | Set the version in the file name. The default comes from `git describe`. |
| `CONTINUE=1 ./build.sh` | Resume after a failure, reusing the build container. |
| `ASSEMBLE_ONLY=1 ./build.sh` | Prepare `build/pi-gen` and stop, to inspect what would be built. |

### Building with unreleased packages

Put a `.deb` in `debs/` and it is used instead of the pinned release. See
[debs/README.md](debs/README.md).

### What the stage does

| Step | Files | What it adds |
|---|---|---|
| `00-raw-gadget` | DKMS, kernel headers, `raw-gadget-dkms` | Builds `raw_gadget` for both kernels in the image (Pi 4 and Pi 5 boot different ones). DKMS rebuilds it after kernel updates. |
| `01-packages` | usb-proxy, midwire-web-ui, midwire-base | Installs them and enables the web UI. usb-proxy itself is started by the web UI, never at boot. midwire-base adds the updater, the apt source and the udev rule below. |
| `02-gadget-port` | `config.txt`, `modules-load.d` | `dtoverlay=dwc2,dr_mode=peripheral` and loading `raw_gadget` at boot. |
| `03-network` | NetworkManager profiles, first-boot service | The two Ethernet profiles, and the service that creates the hotspot. |

The web UI changes the network settings later through NetworkManager and
relies on these profile names:

| Profile | Made by | Purpose |
|---|---|---|
| `midwire-eth-dhcp` | image | Ethernet as a DHCP client. Tried first. |
| `midwire-eth-direct` | image | Ethernet as a DHCP server at `10.42.1.1`. Used when DHCP fails. |
| `midwire-hotspot` | first boot | Wi-Fi access point at `10.42.0.1`. Does not connect automatically. |
| `midwire-wifi` | web UI | Joining an existing Wi-Fi network. Preferred over the hotspot. |

NetworkManager is not left to choose between the last two. At power-on it
starts whichever profile is ready first, and a hotspot is always ready
while a network to join has to be found by a scan, so the hotspot would
win every time and stay. `midwire-base` decides instead:

| Piece | What it does |
|---|---|
| `/usr/lib/midwire/wifi-fallback boot` | Run by `midwire-wifi-fallback.service` at power-on. Waits for NetworkManager to join a saved network and starts the hotspot only if it has not. |
| `/usr/lib/midwire/wifi-fallback check` | Run every two minutes by `midwire-wifi-fallback.timer`. Starts the hotspot when Wi-Fi has dropped, and moves from a fallback hotspot back to a saved network. |

A saved network is any Wi-Fi profile that joins a network and connects
automatically, so one from Raspberry Pi Imager counts too. A hotspot the
user switched on from the Network tab is not a fallback and is left alone
until the next restart. `journalctl -t midwire-wifi-fallback` shows what
was decided and why.

Build-time defaults for the hotspot (a fixed default password and a default
country) are in
`stage-midwire/03-network/files/firstboot.conf`.

Network interfaces on USB devices are left alone. Phones, drones and modems
often present a network adapter next to their other interfaces, and the Pi
would otherwise bring it up while the device waits to be proxied, putting
the device under test on a network with the Pi. A udev rule in the
`midwire-base` package (`/usr/lib/udev/rules.d/84-midwire-usb-net.rules`)
marks such interfaces as unmanaged, so NetworkManager keeps them down. To
use a USB Ethernet or Wi-Fi adapter with the Pi itself, switch the rule off
with an empty file of the same name in `/etc/udev/rules.d/` and reboot.

## Updates

A device updates itself from the web page's Updates tab. Only Midwire's own
four packages are upgraded: `midwire-base`, `midwire-web-ui`, `usb-proxy`
and `raw-gadget-dkms`. Raspberry Pi OS and the kernel are left alone.

How it works on the device, all of it from the `midwire-base` package:

| Piece | What it does |
|---|---|
| `/etc/apt/sources.list.d/midwire.sources` | Points apt at this project's package repository. |
| `/usr/share/keyrings/midwire-archive-keyring.gpg` | The public key that repository must be signed with. apt refuses anything else. |
| `/usr/lib/midwire/update check` | Downloads the package list and records which packages have a newer version. Run daily by `midwire-update-check.timer`, and when the page asks. |
| `/usr/lib/midwire/update install` | Upgrades those packages. Run by `midwire-update-install.service` when the user presses the button. |
| `/var/lib/midwire/update.json` | What the page shows: versions, the result of the last check and of the last installation. |
| polkit rule | Lets the web UI start those two services, and nothing else. It cannot choose packages or commands. |

The device needs internet access for this, so it has to be on Ethernet or
joined to a Wi-Fi network, not only hosting its hotspot.

## Network over the USB-C cable

The Pi has one USB port that can act as a device, the USB-C port, and it
can carry one gadget at a time. The proxy needs it while it runs. The rest
of the time it would sit unused, so `midwire-base` makes it a standard USB
network adapter (NCM) instead: the computer on the other end of the cable
sees a network card, gets an address from the Pi, and can open the web page
at `http://midwire.local` or `http://10.42.2.1`, with no Wi-Fi or Ethernet.

| When | The USB-C port is |
|---|---|
| The proxy is stopped | A network adapter. The Pi's end is the interface `midwire0`, `10.42.2.1`. |
| The proxy is running | The proxied device. The network link is gone; use Wi-Fi or Ethernet to watch the page. |
| The proxy stops, for any reason | A network adapter again, a few seconds later. |

It is a management link only. The Pi hands out an address and nothing else:
no gateway and no DNS server. The computer keeps its own internet
connection, and nothing is routed through the Pi, so the computer being
tested cannot reach your other networks this way. Windows 11, macOS and
Linux have the driver built in. Windows 10 loads its built-in one too, on
version 2004 or later.

The Network tab of the web page has a switch for it. Turn it off if the
computer you are testing should not see a network adapter when the proxy is
idle.

How it is put together, all in `midwire-base`:

| Piece | What it does |
|---|---|
| `/usr/lib/midwire/net-gadget up` and `down` | Creates the gadget through configfs and binds it to the port, or releases the port. |
| `midwire-net-gadget.service` | Runs `up` at boot and `down` when stopped. It conflicts with `usb-proxy.service`, so systemd stops it, and so frees the port, before the proxy starts. |
| `usb-proxy.service.d/20-midwire-net-gadget.conf` | Adds that ordering to the proxy's unit, and starts the network link again once the proxy has stopped. |
| `midwire-net-gadget-dhcp.service` | A DHCP server for `midwire0` only (dnsmasq), sending no gateway and no DNS. |

## SSH and login accounts

SSH is off on a new device, and the image has no login user unless you set
one in Raspberry Pi Imager. Both can be changed from the web page's Settings
tab, without taking the SD card out:

- turn SSH on or off;
- set the password of a login user, which creates the user if the device has
  none (it is put in the `sudo` group, and `sudo` asks for that password);
- add or remove SSH public keys for that user.

The page refuses the last two while its own admin password is still the
default or empty: with them, whoever can log in to the page can get a root
shell on the Pi.

The work is done by `/usr/lib/midwire/system` from the `midwire-base`
package. It runs as root, one process per request, behind the socket
`/run/midwire/system.sock`, which only the web UI's service user can open.
It acts only on ordinary login users (never `root` or a service account),
accepts only plain public keys (no options such as `command=`), and reads
and writes `authorized_keys` as the user the file belongs to.

A device flashed from the 0.1.0 image has no updater. Bring it up to date
once by hand, then it updates from the page:

    sudo apt install ./midwire-base_<version>_all.deb ./midwire-web-ui_<version>_all.deb

### The package repository

The repository is an ordinary signed apt repository whose files are the
assets of this repo's GitHub release tagged `apt`. `scripts/make-apt-repo.sh`
builds and signs it, and `scripts/publish-apt-repo.sh` uploads it. The
`apt` release is never marked "latest": Raspberry Pi Imager follows
`releases/latest`, which must stay an image release.

### Signing key

The repository is signed with one key, created once:

    scripts/make-signing-key.sh /some/folder/outside/this/repo

That writes two files:

| File | Where it goes |
|---|---|
| `midwire-base/keys/midwire-archive-keyring.asc`, the public key | Committed. It is built into `midwire-base`, and every device checks updates against it. |
| `midwire-apt-signing-PRIVATE-key.asc`, the private key | The GitHub Actions secret `APT_SIGNING_KEY` (repository Settings, Secrets and variables, Actions). Keep one offline copy and delete the rest. |

Without the public key `midwire-base` cannot be built, and without the
secret the Publish workflow stops with a message saying so. Publishing also
checks that the two are a pair before it uploads anything.

The private key is what lets someone push software to every device, so it
must never be committed. The script refuses to write it inside this
repository and refuses to replace an existing key: devices trust the key
already published, and one that is lost or leaked means every device has to
be given a new one by hand.

## Releases

`.github/workflows/build.yml` has two jobs:

1. **packages** collects the four `.deb` files and publishes them to the
   `apt` release. Devices see the new versions on their next check.
2. **image** builds the image from exactly those files and attaches to the
   release:
   - `midwire-<version>-arm64.img.xz` and its `.sha256`
   - `os_list_midwire.json`, the file Raspberry Pi Imager reads

Pushing a tag `v<version>` runs both. Running the workflow by hand
publishes the packages only, unless you tick "image": that is how to ship
an update to devices without making a new image.

To release a new version of anything, change `versions.env` (and
`midwire-base/debian/changelog` for midwire-base). Before publishing, make
sure the versions of usb-proxy and midwire-web-ui named there exist as
releases of those repositories.

A local `./build.sh` installs `midwire-base` into the image too, and the
image then runs `apt-get update` against the published repository while it
is being built. So the `apt` release has to exist before an image can be
built; `build.sh` checks and says so.

## License

MIT, see [LICENSE](LICENSE). That covers this repository's own files. The
image it builds contains Raspberry Pi OS and other software under their own
licenses. The `raw_gadget` module packaged by `raw-gadget-dkms/` is part of
the Linux kernel and is GPL-2.0; its source is fetched from
[xairy/raw-gadget](https://github.com/xairy/raw-gadget) at build time.

Midwire is not affiliated with or endorsed by Raspberry Pi Ltd.
