#!/bin/bash
#
# Self-check for find_projects: only immediate subfolders with a composer.json are listed.

set -euo pipefail

source "$(dirname "$0")/composer-bulk-update.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/a" "$tmp/b" "$tmp/c d" "$tmp/e/nested"
touch "$tmp/composer.json" "$tmp/a/composer.json" "$tmp/c d/composer.json" "$tmp/e/nested/composer.json"

expected=$(printf '%s\n' "$tmp/a" "$tmp/c d")
actual=$(find_projects "$tmp")

if [ "$actual" != "$expected" ]; then
    printf 'FAIL\nexpected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    exit 1
fi
echo ok
