# `heroku-bulk-deploy.sh`

Lists every deployed Heroku app you can access, lets you tick the ones you want, then
rebuilds each one. Every build uses the commit in the app's current release and purges the
build cache first, so you get a full rebuild of what's already running, with the current
buildpack, PHP version and extensions.

## Usage

```sh
heroku-bulk-deploy.sh [--dry-run]
```

| Argument    | Meaning |
| ----------- | ------- |
| `--dry-run` | Find and download the source each ticked app would build, but don't purge or build anything. |

Builds run one at a time and stream the build log, so a ✓ means the build succeeded.

Apps that were never deployed and archived apps aren't listed.

## Keys

| Key            | Action |
| -------------- | ------ |
| `↑` / `↓`, `k` / `j` | Move the cursor |
| `space`        | Tick or untick the app under the cursor |
| `a`            | Tick all, or untick all if everything is ticked |
| `enter`        | Rebuild the ticked apps. With nothing ticked, rebuilds the app under the cursor. |
| `q`            | Quit without rebuilding anything |

## Where the source comes from

Heroku doesn't keep a usable copy of an old build's source, so the script fetches the live
commit again. It checks the app first, then the other apps in its pipeline, and in each one
tries:

1. The GitHub repo linked through Heroku's GitHub integration, downloaded with `gh`.
2. The app's Heroku git repo (`git.heroku.com/<app>.git`).

Production apps promoted from staging have an empty Heroku git repo, so their source usually
comes from the staging app in the same pipeline. An app whose live commit isn't found in any
of those places is reported as a failure and skipped.

Composer packages come from the `composer.lock` in that commit. To pick up newer packages,
run `composer-bulk-update --git` and deploy the new commit first.

A failed build doesn't stop the rest. A summary at the end lists each app with ✓ or ✗ and the
short commit hash, and the script exits 1 if any failed.

## Install

```sh
ln -s "$PWD/heroku-bulk-deploy/heroku-bulk-deploy.sh" /opt/homebrew/bin/heroku-bulk-deploy
```

## Test

```sh
bash heroku-bulk-deploy/heroku-bulk-deploy-test.sh
```

## Dependencies

```sh
brew install heroku/brew/heroku gh
heroku login
heroku plugins:install @heroku-cli/heroku-builds
gh auth login
```

`jq` is also required. macOS ships it at `/usr/bin/jq`.
