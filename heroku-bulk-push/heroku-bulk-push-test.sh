#!/bin/bash
#
# Self-checks, using local bare repos in place of Heroku:
#   - find_projects only lists immediate subfolders with a heroku remote
#   - heroku_branch follows the remote's HEAD, and falls back to main for an empty repo
#   - push_project pushes the current branch (e.g. dev) onto that branch

set -euo pipefail

source "$(dirname "$0")/heroku-bulk-push.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

# Isolate from the user's git config and give commits an identity.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# Make repo $1 on branch $2 with one commit, and a heroku remote at bare repo $3 whose
# default branch is $4.
make_project() {
    git init -q --bare -b "$4" "$3"
    git init -q -b "$2" "$1"
    echo hi > "$1/file.txt"
    git -C "$1" add -A
    git -C "$1" commit -qm init
    git -C "$1" remote add heroku "$3"
}

root="$tmp/sites"
mkdir -p "$root/plain" "$root/nested/deep"
git init -q "$root/plain"
make_project "$root/nag" dev "$tmp/nag.git" master
make_project "$root/site" main "$tmp/site.git" main
make_project "$root/nested/deep" main "$tmp/deep.git" main

expected=$(printf '%s\n' "$root/nag" "$root/site")
actual=$(find_projects "$root")
[ "$actual" = "$expected" ] || fail "find_projects: expected '$expected', got '$actual'"

# An empty bare repo has no HEAD to report yet.
[ "$(heroku_branch "$root/nag")" = main ] || fail "empty heroku repo should fall back to main"

git -C "$tmp/nag.git" symbolic-ref HEAD refs/heads/master
git -C "$root/nag" push -q heroku dev:master
echo more >> "$root/nag/file.txt"
git -C "$root/nag" commit -qam more
[ "$(heroku_branch "$root/nag")" = master ] || fail "heroku_branch should follow the remote HEAD"

push_project "$root/nag" dev false > /dev/null 2>&1 || fail "push_project returned non-zero"
[ "$(git -C "$tmp/nag.git" rev-parse master)" = "$(git -C "$root/nag" rev-parse dev)" ] ||
    fail "dev wasn't pushed to heroku master"
git -C "$tmp/nag.git" rev-parse -q --verify dev > /dev/null && fail "push created a dev branch on heroku"

# A dry run leaves the remote alone.
echo again >> "$root/nag/file.txt"
git -C "$root/nag" commit -qam again
push_project "$root/nag" dev true > /dev/null 2>&1 || fail "dry-run push returned non-zero"
[ "$(git -C "$tmp/nag.git" rev-parse master)" != "$(git -C "$root/nag" rev-parse dev)" ] ||
    fail "dry run pushed"

echo ok
