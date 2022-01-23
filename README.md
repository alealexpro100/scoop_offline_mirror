mirror_sync
===========

## Dependencies

`bash jq sed` and (if used) `git`.

## About

Scripts for creating local scoop mirror of chosen manifests. It downloads needed binaries and edits manifests to make it working.

### What it does

* Replaces and exports "url" sections in manifest file. Takes attention to name of file.
* Auto-updates mirror repo (needs to be enabled).

### What it does NOT

* It does not resolve dependencies.
* If there any download by installer, it won't be mirrored. It is about packages like `cygwin`.
## Usage

* First of all, you need to copy `config.conf.example` to `config.conf` and edit it.
* Run `update_online_manifests.sh`. It will sync repositories from internet and place chosen manifests to `online_manifests` directory.
* Run `update_mirror_manifests.sh`. It will edit chosen manifests and place them into `offline_manifests` directory.
