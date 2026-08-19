# `webp.sh`

Recursively converts every JPEG, PNG and GIF under the current directory to WebP and
**deletes the original files**. There is no undo — work on a copy, or commit first.

## Usage

```sh
cd path/to/images
webp.sh                     # defaults: -m 6 -q 70 -mt -af -progress
webp.sh -q 85 -mt           # or pass your own cwebp flags
```

Any arguments you supply replace the default flag set entirely; see `cwebp -longhelp` for
the full list.

## Dependencies

```sh
brew install webp           # provides cwebp
```
