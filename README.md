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

This repository only builds the image. It is a thin wrapper around
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
a network you share with others. There are three ways to get there:

| How | What happens |
|---|---|
| Ethernet to your router or switch | The Pi gets an address from your network, like any other device. |
| Ethernet straight to your computer | After about 30 seconds without an answer from a DHCP server, the Pi takes `10.42.1.1` and gives your computer an address. |
| Wi-Fi hotspot | The Pi creates a network called `Midwire-XXXX` (the last four characters differ per device) and is at `10.42.0.1`. |

The hotspot password is generated on the first boot and is different on
every device. To find it, shut the Pi down, put the SD card in a computer
and open `midwire-hotspot.txt` on the `bootfs` partition. To choose it
yourself instead, create that file before the first boot:

    SSID=MyMidwire
    PASSWORD=at-least-8-characters
    COUNTRY=GB

All three lines are optional. `COUNTRY` is the two-letter Wi-Fi regulatory
country; set it here or in Imager. Without one the hotspot still starts,
on 2.4 GHz channel 6, which is allowed everywhere.

If you move an Ethernet cable from a computer to a router or back, unplug it
for ten seconds first so the Pi notices and tries DHCP again.

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
2. Collects three `.deb` packages (`scripts/fetch-debs.sh`): usb-proxy and
   midwire-web-ui from their GitHub releases, and raw-gadget-dkms built from
   the pinned raw-gadget commit.
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
| `01-packages` | usb-proxy, midwire-web-ui | Installs both and enables the web UI. usb-proxy itself is started by the web UI, never at boot. |
| `02-gadget-port` | `config.txt`, `modules-load.d` | `dtoverlay=dwc2,dr_mode=peripheral` and loading `raw_gadget` at boot. |
| `03-network` | NetworkManager profiles, first-boot service | The two Ethernet profiles, and the service that creates the hotspot. |

The web UI changes the network settings later through NetworkManager and
relies on these profile names:

| Profile | Made by | Purpose |
|---|---|---|
| `midwire-eth-dhcp` | image | Ethernet as a DHCP client. Tried first. |
| `midwire-eth-direct` | image | Ethernet as a DHCP server at `10.42.1.1`. Used when DHCP fails. |
| `midwire-hotspot` | first boot | Wi-Fi access point at `10.42.0.1`. |
| `midwire-wifi` | web UI | Joining an existing Wi-Fi network. Preferred over the hotspot. |

Build-time defaults for the hotspot (a fixed default password, a default
country, the profile priority) are in
`stage-midwire/03-network/files/firstboot.conf`.

## Releases

Pushing a tag `v<version>` runs `.github/workflows/build.yml`, which builds
the image on a GitHub arm64 runner and attaches to the release:

- `midwire-<version>-arm64.img.xz` and its `.sha256`
- `os_list_midwire.json`, the file Raspberry Pi Imager reads

Before tagging, make sure the versions in `versions.env` exist as releases
of usb-proxy and midwire-web-ui. To update pi-gen, raw-gadget or either
package, change `versions.env`.

## License

MIT, see [LICENSE](LICENSE). That covers this repository's own files. The
image it builds contains Raspberry Pi OS and other software under their own
licenses. The `raw_gadget` module packaged by `raw-gadget-dkms/` is part of
the Linux kernel and is GPL-2.0; its source is fetched from
[xairy/raw-gadget](https://github.com/xairy/raw-gadget) at build time.

Midwire is not affiliated with or endorsed by Raspberry Pi Ltd.
