mirror_sync
===========

## Dependencies

`bash jq sed md5sum sha256sum sha1sum sha512sum` and (if used) `git`.

## About

Scripts for creating local scoop mirror of chosen manifests. It downloads needed binaries and edits manifests to make it working. Works only with `*.json` files.

### What it does

* Replaces and exports "url" sections in manifest file. Takes attention to name of file.
* Auto-updates mirror repo (needs to be enabled).

### What it does NOT

* It does not resolve dependencies.
* If there any download by installer, it won't be mirrored. It is about packages like `cygwin`.
## Usage

* Copy `config.conf.example` to `config.conf` and edit it.
* Run `update_mirror_manifests.sh`. It will edit chosen manifests and place them into `offline_manifests` directory.
