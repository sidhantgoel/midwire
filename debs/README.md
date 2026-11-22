# Local package overrides

`build.sh` installs three packages into the image:

| Package | Normally comes from |
|---|---|
| `usb-proxy_<version>_arm64.deb` | GitHub release of `sidhantgoel/usb-proxy` |
| `midwire-web-ui_<version>_all.deb` | GitHub release of `sidhantgoel/midwire-web-ui` |
| `raw-gadget-dkms_<version>_all.deb` | Built by `raw-gadget-dkms/` in this repo |

The versions are pinned in `versions.env`.

To build an image with a package that is not released yet, put its `.deb`
in this folder. A file here wins over the pinned release, whatever its
version. The `.deb` files in this folder are ignored by git.
