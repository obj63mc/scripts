# local dev scripts

A grab bag of shell scripts I use for local development on macOS.

## Scripts

| Script | What it does | Docs |
| ------ | ------------ | ---- |
| `addvhost.sh` | Creates an Apache vhost (HTTP + HTTPS with `mkcert` certs) and a `.loc` hosts entry for Homebrew httpd. | [docs/addvhost.md](docs/addvhost.md) |
| `webp.sh` | Recursively converts images to WebP and deletes the originals. | [docs/webp.md](docs/webp.md) |

## Requirements

- macOS with [Homebrew](https://brew.sh) installed at `/opt/homebrew` (Apple Silicon default).
  The scripts use absolute Homebrew paths, so an Intel Mac (`/usr/local`) needs those
  constants edited.
- Bash. `addvhost.sh` needs the shell features in Bash 3.2+, which macOS ships.

Per-script dependencies are listed in each script's doc page.

## Install

Clone anywhere and put the directory on your `PATH`, or symlink individual scripts:

```sh
ln -s "$PWD/addvhost.sh" /opt/homebrew/bin/addvhost
```
