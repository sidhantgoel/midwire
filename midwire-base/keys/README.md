# Midwire archive key

`midwire-archive-keyring.asc` in this folder is the **public** half of the
key the Midwire apt repository is signed with. It is built into the
`midwire-base` package, and every device uses it to check that updates
really come from this project.

Only the public key belongs here. The private key lives in the GitHub
Actions secret `APT_SIGNING_KEY` and nowhere in this repository. The package
build refuses a file that contains a private key.

The key is created once with `scripts/make-signing-key.sh` (see "Signing
key" in the top-level README). Without it this folder has no key and
`midwire-base` cannot be built, except with a test key:

    MIDWIRE_ARCHIVE_KEY=/path/to/test-public-key.asc midwire-base/build-in-docker.sh out/
